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

function Get-TerraformEnvironment {
    Write-Host "Environment variables:" -ForegroundColor Green
    Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_* | Sort-Object -Property Name
}
Set-Alias tfe Get-TerraformEnvironment
# Don't overwrite https://github.com/tfutils/tfenv
#Set-Alias tfenv Get-TerraformEnvironment 

function Get-TerraformInfo {
    $directory = ChangeTo-TerraformDirectory
    try {
        if ($directory) {
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
                $jmesPath = "[?properties.lease.status != 'unlocked']" 

                $lockedBlobs = Get-Blobs -BackendStorageAccountName $backendStorageAccountName -BackendStorageContainerName $backendStorageContainerName -JmesPath $jmesPath
                $lockedBlobs | ForEach-Object {
                    $lockedWorkspace = $_.name -replace "${backendStateKey}env:","" -replace "${backendStateKey}","default"
                    Write-Host "Workspace '${lockedWorkspace}' has status '$($_.properties.lease.status)'`n" -ForegroundColor Yellow
                }
            }

            # Environment variables
            Write-Host "Environment variables:" -ForegroundColor Green
            Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_* | Sort-Object -Property Name

            # Azure resources
            $resourceQuery = "Resources | where tags['provisioner']=='terraform' | summarize ResourceCount=count() by Application=tostring(tags['application']), Environment=tostring(tags['environment']), Workspace=tostring(tags['workspace']), Suffix=tostring(tags['suffix']) | order by Application asc, Environment asc, Workspace asc, Suffix asc"
            Write-Information "Executing graph query:`n$resourceQuery"
            Write-Host "`nAzure resources:`n" -ForegroundColor Green
            az extension add --name resource-graph 2>$null
            az graph query -q $resourceQuery -o table
        }
    } finally {
        PopFrom-TerraformDirectory 
    }
}
Set-Alias tfi Get-TerraformInfo

function Get-Blobs (
    [parameter(Mandatory=$true)][string]$BackendStorageAccountName,
    [parameter(Mandatory=$true)][string]$BackendStorageContainerName,
    [parameter(Mandatory=$true)][string]$JmesPath
) {
    Write-Information "Retrieving blobs from https://${BackendStorageAccountName}.blob.core.windows.net/${BackendStorageContainerName}..."
    if ($env:ARM_ACCESS_KEY) {
        $blobs = az storage blob list -c $BackendStorageContainerName --account-name $BackendStorageAccountName --account-key $env:ARM_ACCESS_KEY --query $JmesPath | ConvertFrom-Json
    } else {
        if ($env:ARM_SAS_TOKEN) {
            $blobs = az storage blob list -c $BackendStorageContainerName --account-name $BackendStorageAccountName --sas-token $env:ARM_SAS_TOKEN --query $JmesPath | ConvertFrom-Json
        } else {
            Write-Information "Environment variable ARM_ACCESS_KEY or ARM_SAS_TOKEN not set, trying az auth"
            $blobs = az storage blob list -c $BackendStorageContainerName --account-name $BackendStorageAccountName --auth-mode login --query $JmesPath | ConvertFrom-Json
            if (!$blobs) {
                Write-Information "No access to storage using KEY, SAS or SSO. Trying to obtain key..."
                $storageKey = az storage account keys list -n $BackendStorageAccountName --query "[?keyName=='key1'].value" -o tsv
                if ($storageKey) {
                    $blobs = az storage blob list -c $BackendStorageContainerName --account-name $BackendStorageAccountName --account-key $storageKey --query $JmesPath | ConvertFrom-Json
                } else {
                    Write-Error "Insufficient permissions (set environment variable ARM_SAS_TOKEN or ARM_ACCESS_KEY)"
                    return
                }
            }
        }
    }
    return $blobs
}

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

function List-TerraformOutput {
    Invoke-TerraformCommand "terraform output"
}
Set-Alias tfo List-TerraformOutput

function List-TerraformState (
    [parameter(Mandatory=$false)][string]$SearchPattern
 ) {
    $command = "terraform state list"
    if ($SearchPattern) {
        $command += " | Select-String -Pattern '$SearchPattern'"
    }
    $command += " | Sort-Object"
    Invoke-TerraformCommand $command
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

function RemoveFrom-TerraformState (
    [parameter(Mandatory=$true)][string]$Resource
) {
    Invoke-TerraformCommand "terraform state rm $Resource"
}
Set-Alias tfrm RemoveFrom-TerraformState

function Set-TerraformWorkspace (
    [parameter(Mandatory=$true)][string]$Workspace
) {
    Invoke-TerraformCommand "terraform workspace select $Workspace"
}
Set-Alias tfw Set-TerraformWorkspace  

function Taint-TerraformResource (
    [parameter(Mandatory=$true)][string]$Resource
) {
    Invoke-TerraformCommand "terraform taint $Resource"
}
Set-Alias tft Taint-TerraformResource 

function Unlock-TerraformState (
    [parameter(Mandatory=$false,HelpMessage="The workspace to break lease for")][string]$Workspace=$env:TF_WORKSPACE
) {
    $tfdirectory = ChangeTo-TerraformDirectory

    try {
        if ($tfdirectory) {
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

            if ($Workspace -eq "default") {
                $blobName = $backendStateKey
            } else {
                $blobName = "${backendStateKey}env:${Workspace}"
            }

            $jmesPath = "[?properties.lease.status != 'unlocked' && name == '${blobName}']"

            $lockedBlob = Get-Blobs -BackendStorageAccountName $backendStorageAccountName -BackendStorageContainerName $backendStorageContainerName -JmesPath $jmesPath
            if (!$lockedBlob) {
                Write-Host "${tfdirectory}: Workspace '${Workspace}' is not locked" -ForegroundColor Yellow
                return
            } else {
                # Prompt to continue
                Write-Host "${tfdirectory}: If you wish to proceed to unlock workspace '${Workspace}', please reply 'yes' - null or N aborts" -ForegroundColor Cyan
                $proceedanswer = Read-Host

                if ($proceedanswer -ne "yes") {
                    Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Yellow
                    return
                }
                Write-Host "Unlocking workspace '${Workspace}' by breaking lease on blob '${blobName}'..."
                if ($env:ARM_ACCESS_KEY) {
                    $ticks = az storage blob lease break -b $blobName -c $backendStorageContainerName --account-name $BackendStorageAccountName --account-key $env:ARM_ACCESS_KEY
                } else {
                    if ($env:ARM_SAS_TOKEN) {
                        $ticks = az storage blob lease break -b $blobName -c $backendStorageContainerName --account-name $BackendStorageAccountName --sas-token $env:ARM_SAS_TOKEN
                    } else {
                        Write-Information "Environment variable ARM_ACCESS_KEY or ARM_SAS_TOKEN not set, trying az auth"
                        $ticks = az storage blob lease break -b $blobName -c $backendStorageContainerName --account-name $BackendStorageAccountName --auth-mode login
                        if (!$ticks) {
                            Write-Information "No access to storage using KEY, SAS or SSO. Trying to obtain key..."
                            $storageKey = az storage account keys list -n $BackendStorageAccountName --query "[?keyName=='key1'].value" -o tsv
                            if ($storageKey) {
                                $ticks = az storage blob lease break -b $blobName -c $backendStorageContainerName --account-name $BackendStorageAccountName --account-key $storageKey
                            } else {
                                Write-Error "Insufficient permissions (set environment variable ARM_SAS_TOKEN or ARM_ACCESS_KEY)"
                                return
                            }
                        }
                    }
                }
                if ($ticks -eq 0) {
                    Write-Host "Unlocked workspace '${Workspace}'"
                } else {
                    Write-Host "Lease has unexpected value for 'Ticks': $ticks" -ForegroundColor Yellow
                }
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