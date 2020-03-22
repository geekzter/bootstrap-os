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
    $directory = ChangeTo-TerraformDirectory
    try {
        $data = @{
            directory = $directory
            branch = $(git rev-parse --abbrev-ref HEAD 2>$null)
            resources = $((terraform state list).Count)
            workspace = $(terraform workspace show)
        }
        $stateFile = Join-Path $directory .terraform terraform.tfstate
        if (Test-Path $stateFile) {
            Write-Information "Reading Terraform settings from ${stateFile}..."
            $tfConfig = $(Get-Content $stateFile | ConvertFrom-Json)
            if ($tfConfig.backend.type -ne "azurerm") {
                throw "This script only works with azurerm provider"
            }
            $data["storageaccount"] = $tfConfig.backend.config.storage_account_name
            $data["storagecontainer"] = $tfConfig.backend.config.container_name
        }

        Write-Host "`nGeneral information:" -ForegroundColor Green
        $data.GetEnumerator() | Sort-Object -Property Name | Format-Table -HideTableHeaders

        if (Test-Path $stateFile) {
            Write-Information "Checking lease status of backend blobs..."
            
            $backendStorageAccountName = $tfConfig.backend.config.storage_account_name
            $backendStorageContainerName = $tfConfig.backend.config.container_name
            $backendStateKey = $tfConfig.backend.config.key
            if ($env:ARM_ACCESS_KEY) {
                $backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -StorageAccountKey $env:ARM_ACCESS_KEY
            } else {
                if ($env:ARM_SAS_TOKEN) {
                    $backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -SasToken $env:ARM_SAS_TOKEN
                } else {
                    Write-Warning "Environment variable ARM_ACCESS_KEY or ARM_SAS_TOKEN needs to be set, exiting"
                    return
                }
            }
            Write-Information "Retrieving blobs from https://${backendStorageAccountName}.blob.core.windows.net/${backendStorageContainerName}..."
            $tfStateBlobs = Get-AzStorageBlob -Context $backendstorageContext -Container $backendStorageContainerName 
            $tfStateBlobs | ForEach-Object {
                $storageWorkspaceName = $($_.Name -Replace "${backendStateKey}env:","" -Replace $backendStateKey,"default")
                $leaseStatus = $_.ICloudBlob.Properties.LeaseStatus
                if ($leaseStatus -ine "Unlocked") {
                    Write-Host "Workspace '${storageWorkspaceName}' has status '${leaseStatus}'`n" -ForegroundColor Yellow
                }
            }
        }

        # Environment variables
        Write-Host "Environment variables:" -ForegroundColor Green
        Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_* | Sort-Object -Property Name

        # Azure resources
        $resourceQuery = "Resources | where tags['provisioner']=='terraform' | summarize ResourceCount=count() by Application=tostring(tags['application']), Environment=tostring(tags['environment']), Workspace=tostring(tags['workspace']), Suffix=tostring(tags['suffix']) | order by Application asc, Environment asc, Workspace asc, Suffix asc"
        Write-Information "Executing graph query:`n$resourceQuery"
        Write-Host "`nAzure resources:" -NoNewline -ForegroundColor Green
        Search-AzGraph -Query $resourceQuery | Format-Table
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

function Unlock-TerraformState (
    [parameter(Mandatory=$false,HelpMessage="The workspace to break lease for")][string]$Workspace=$env:TF_WORKSPACE
) {
    $tfdirectory = ChangeTo-TerraformDirectory

    try {
        if (!$Workspace) {
            $Workspace = $(terraform workspace show)
        }

        # Access Terraform (Azure) backend to get leases for each workspace
        Write-Information "Reading Terraform settings from ${tfdirectory}/.terraform/terraform.tfstate..."
        $tfConfig = $(Get-Content ${tfdirectory}/.terraform/terraform.tfstate | ConvertFrom-Json)
        if ($tfConfig.backend.type -ine "azurerm") {
            throw "This script only works with azurerm provider"
        }
        $backendStorageAccountName = $tfConfig.backend.config.storage_account_name
        $backendStorageContainerName = $tfConfig.backend.config.container_name
        $backendStateKey = $tfConfig.backend.config.key
        if ($env:ARM_ACCESS_KEY) {
            $backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -StorageAccountKey $env:ARM_ACCESS_KEY
        } else {
            if ($env:ARM_SAS_TOKEN) {
                $backendstorageContext = New-AzStorageContext -StorageAccountName $backendStorageAccountName -SasToken $env:ARM_SAS_TOKEN
            } else {
                Write-Warning "Environment variable ARM_ACCESS_KEY or ARM_SAS_TOKEN needs to be set, exiting"
                return
            }
        }
        if ($Workspace -eq "default") {
            $blobName = $backendStateKey
        } else {
            $blobName = "${backendStateKey}env:${Workspace}"
        }

        Write-Information "Retrieving blob https://${backendStorageAccountName}.blob.core.windows.net/${backendStorageContainerName}/${blobName}..."
        $tfStateBlob = Get-AzStorageBlob -Context $backendstorageContext -Container $backendStorageContainerName -Blob $blobName -ErrorAction SilentlyContinue
        if (!($tfStateBlob)) {
            Write-Host "{$tfdirectory}: Workspace '${Workspace}' state not found" -ForegroundColor Red
            return
        }

        if ($tfStateBlob.ICloudBlob.Properties.LeaseStatus -ieq "Unlocked") {
            Write-Host "{$tfdirectory}: Workspace '${Workspace}' is not locked" -ForegroundColor Yellow
            return
        } else {
            # Prompt to continue
            Write-Host "{$tfdirectory}: If you wish to proceed to unlock workspace '${Workspace}', please reply 'yes' - null or N aborts" -ForegroundColor Cyan
            $proceedanswer = Read-Host

            if ($proceedanswer -ne "yes") {
                Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Yellow
                return
            }
            Write-Host "Unlocking workspace '${Workspace}' by breaking lease on blob $($tfStateBlob.ICloudBlob.Uri.AbsoluteUri)..."
            $lease = $tfStateBlob.ICloudBlob.BreakLease()
            if ($lease.Ticks -eq 0) {
                Write-Host "Unlocked workspace '${Workspace}'"
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