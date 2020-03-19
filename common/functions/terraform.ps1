$global:directoryStack = New-Object system.collections.stack

function Apply-Terraform {
    Invoke-TerraformCommand "terraform apply -auto-approve"
}
Set-Alias tfa Apply-Terraform

function ChangeTo-TerraformDirectory {
    $depth = 2

    $directoryStack.Push((Get-Location).Path)

    $directoryPath = Find-TerraformDirectory
    if ($directoryPath) {
        $null = Set-Location $directoryPath
        return $directoryPath
    } else {
        Write-Warning "Terraform directory not found"
        return
    }
}
Set-Alias cdtf ChangeTo-TerraformDirectory
Set-Alias tfcd ChangeTo-TerraformDirectory

function Clear-TerraformState {
    # terraform state list | ForEach-Object { 
    #     terraform state rm $_
    # }
    # 'terraform state rm' does not remove output (anymore)
    # HACK: Manipulate the state directly instead
    $tfState = terraform state pull | ConvertFrom-Json
    if ($tfState -and $tfState.outputs) {
        $tfState.outputs = New-Object PSObject # Empty output
        $tfState.resources = @() # No resources
        $tfState.serial++
        $tfState | ConvertTo-Json | terraform state push -
        if ($LASTEXITCODE -ne 0) {
            return
        }
        Write-Host "Terraform state cleared, it contains now:"
        terraform state pull 
    } else {
        Write-Host "Terraform state not populated" -ForegroundColor Yellow
        return
    }
}
Set-Alias tfclr Clear-TerraformState

function Destroy-Terraform {
    Invoke-TerraformCommand "terraform destroy" # -auto-approve
}
Set-Alias tfd Destroy-Terraform

function Find-TerraformDirectory {
    $depth = 2

    if (Test-Path *.tf) {
        return (Get-Location).Path
    } else {
        $main = Get-ChildItem -Path . -Filter main.tf -Recurse -Depth $depth | Select-Object -First 1
        if (!$main) {
            # Go one level below current directory
            $main = Get-ChildItem -Path .. -Filter main.tf -Recurse -Depth $depth | Select-Object -First 1
        }
        if ($main) {
            return $main.Directory.FullName
        }
        return $null
    }
}

function Get-TerraformInfo {
    ChangeTo-TerraformDirectory >$null
    try {
        $data = @{
            branch = $(git rev-parse --abbrev-ref HEAD 2>$null)
            resources = $((terraform state list).Count)
            workspace = $(terraform workspace show)
        }
        $data | Sort-Object -Property Name | Format-Table #-HideTableHeaders
        Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_* | Sort-Object -Property Name
    } finally {
        PopFrom-TerraformDirectory 
    }
}
Set-Alias tfi Get-TerraformInfo

function Invoke-TerraformCommand (
    [parameter(Mandatory=$true)][string]$cmd
) {
    $directory = ChangeTo-TerraformDirectory
    try {
        if ($directory) {
            Write-Host "${directory} " -ForegroundColor Green -NoNewline
        }
        Write-Host "($(terraform workspace show)): " -ForegroundColor Green -NoNewline
        Write-Host "$cmd" -ForegroundColor Green 
        Invoke-Expression $cmd
    } finally {
        PopFrom-TerraformDirectory 
    }
}

function List-TerraformState {
    Invoke-TerraformCommand "terraform state list"
}
Set-Alias tfls List-TerraformState

function Plan-Terraform {
    $workspace = $(terraform workspace show)
    Invoke-TerraformCommand "terraform plan -out='${workspace}.tfplan'"
}
Set-Alias tfp Plan-Terraform

function PopFrom-TerraformDirectory {
    if ($directoryStack.Count -gt 0) {
        $directoryPath = $directoryStack.Pop()
        $null = Set-Location $directoryPath
    } else {
        Write-Information "Stack is empty"
    }
}
Set-Alias cdtf- PopFrom-TerraformDirectory
Set-Alias tfcd- PopFrom-TerraformDirectory

# TODO
function Unlock-TerraformState {
    $tfdirectory = ChangeTo-TerraformDirectory

    if (!$env:ARM_ACCESS_KEY) {
        Write-Warning "Environment variable ARM_ACCESS_KEY needs to be set, exiting"
        return
    }
    try {
        $workspace = $(terraform workspace show)

        # Access Terraform (Azure) backend to get leases for each workspace
        Write-Information "Reading Terraform settings from ${tfdirectory}/.terraform/terraform.tfstate..."
        $tfConfig = $(Get-Content ${tfdirectory}/.terraform/terraform.tfstate | ConvertFrom-Json)
        if ($tfConfig.backend.type -ine "azurerm") {
            throw "This script only works with azurerm provider"
        }
        $backendStorageAccountName = $tfConfig.backend.config.storage_account_name
        $backendStorageContainerName = $tfConfig.backend.config.container_name
        $backendStateKey = $tfConfig.backend.config.key
        $backendStorageKey = $env:ARM_ACCESS_KEY
        $backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -StorageAccountKey $backendStorageKey
        if ($workspace -eq "default") {
            $blobName = $backendStateKey
        } else {
            $blobName = "${backendStateKey}env:${workspace}"
        }

        Write-Information "Retrieving blob https://${backendStorageAccountName}.blob.core.windows.net/${backendStorageContainerName}/${blobName}..."
        $tfStateBlob = Get-AzStorageBlob -Context $backendstorageContext -Container $backendStorageContainerName -Blob $blobName -ErrorAction SilentlyContinue
        if (!($tfStateBlob)) {
            Write-Host "{$tfdirectory}: Workspace '${workspace}' state not found" -ForegroundColor Red
            return
        }

        if ($tfStateBlob.ICloudBlob.Properties.LeaseStatus -ieq "Unlocked") {
            Write-Host "{$tfdirectory}: Workspace '${workspace}' is not locked" -ForegroundColor Yellow
            return
        } else {
            # Prompt to continue
            Write-Host "{$tfdirectory}: If you wish to proceed to unlock workspace '${workspace}', please reply 'yes' - null or N aborts" -ForegroundColor Cyan
            $proceedanswer = Read-Host

            if ($proceedanswer -ne "yes") {
                Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Yellow
                return
            }
            Write-Host "Unlocking workspace '${workspace}' by breaking lease on blob $($tfStateBlob.ICloudBlob.Uri.AbsoluteUri)..."
            $lease = $tfStateBlob.ICloudBlob.BreakLease()
            if ($lease.Ticks -eq 0) {
                Write-Host "Unlocked workspace '${workspace}'"
            } else {
                Write-Host "Lease has unexpected value for 'Ticks'" -ForegroundColor Yellow
                $lease
            }
        }
    } finally {
        PopFrom-TerraformDirectory 
    }
}
Set-Alias tfu Unlock-TerraformState

function Validate-Terraform {
    Invoke-TerraformCommand "terraform validate"
}
Set-Alias tfv Validate-Terraform