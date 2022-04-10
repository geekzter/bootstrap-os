$global:directoryStack = New-Object system.collections.stack

function Apply-Terraform {
    Invoke-TerraformCommand "terraform apply"
}
Set-Alias tfa Apply-Terraform

function ForceApply-Terraform {
    Invoke-TerraformCommand "terraform apply -auto-approve"
}
Set-Alias tfaf ForceApply-Terraform

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

function Clear-TerraformState(
    [parameter(Mandatory=$false)][switch]$Force
) {
    # terraform state list | ForEach-Object { 
    #     terraform state rm $_
    # }
    # 'terraform state rm' does not remove output (anymore)
    # HACK: Manipulate the state directly instead
    $tfState = terraform state pull | ConvertFrom-Json
    $terraformSupportedVersions = @("0.12","0.13","0.14","0.15", "1.0", "1.1")
    $terraformSupportedVersionRegEx = "^($($terraformSupportedVersions -join "|"))"
    if ($tfState.terraform_version -notmatch $terraformSupportedVersionRegEx) {
        Write-Warning "Terraform state is maintained by version $($tfState.terraform_version), expected $terraformSupportedVersions"
        return
    }
    if ($tfState -and $tfState.outputs) {
        if (!$Force) {
            Write-Host "If you wish to clear Terraform state, please reply 'yes' - null or N aborts" -ForegroundColor Cyan
            $proceedanswer = Read-Host

            if ($proceedanswer -ne "yes") {
                Write-Host "`nReply is not 'yes' - Aborting " -ForegroundColor Yellow
                return
            }
        }

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

function Destroy-Terraform(
    [parameter(Mandatory=$false)][switch]$Force
) {
    Invoke-TerraformCommand "terraform destroy $($Force ? '-auto-approve' : $null)"
}
Set-Alias tfd Destroy-Terraform

function Erase-TerraformAzureResources {
    [CmdletBinding(DefaultParameterSetName="Workspace")]
    param (
        [parameter(Mandatory=$false)]
        [string]
        $Repository,
        
        [parameter(Mandatory=$false,ParameterSetName="Workspace")]
        [string]
        $Workspace=$env:TF_WORKSPACE,
        
        [parameter(Mandatory=$false,ParameterSetName="DeploymentName")]
        [string]
        $DeploymentName,
        
        [parameter(Mandatory=$false,ParameterSetName="Suffix")]
        [string[]]
        $Suffix,
        
        [parameter(Mandatory=$false,ParameterSetName="Workspace")]
        [bool]
        $ClearTerraformState=$true,
        
        [switch]
        $Destroy=$false,
        
        [parameter(Mandatory=$false)]
        [switch]
        $Force=$false,

        [parameter(Mandatory=$false)]
        [switch]
        $Wait=$false,

        [parameter(Mandatory=$false)]
        [int]
        $TimeoutMinutes=50
    ) 

    Write-Verbose $MyInvocation.line
    Write-Debug "`$PSCmdlet.ParameterSetName: $($PSCmdlet.ParameterSetName)"

    $tfdirectory = ChangeTo-TerraformDirectory
    if ($Workspace) {
        Set-TerraformWorkspace $Workspace
    } else {
        # Ensure this is always populated
        $Workspace = $(terraform workspace show)
    }
    if ($Workspace -imatch "prod") {
        Write-Warning "The workspace name '${Workspace}' indicates this may be a production workload. Exiting..."
        return
    }

    try {

        if (!$Repository) {
            $Repository = Find-RepositoryDirectory            
        }
        if (!$Repository) {
            Write-Warning "Repository not specified, exiting"
            return
        } else {
            $Repository = (Split-Path -Leaf $Repository)
        }

        if ($ClearTerraformState -and ($PSCmdlet.ParameterSetName -ieq "Workspace")) {
            Clear-TerraformState -Force:$Force
        }
    
        if ($Destroy) {
            $baseTagQuery = "[?tags.repository == '${Repository}'].id"
            switch ($PSCmdlet.ParameterSetName) {
                "DeploymentName" {
                    $baseTagQuery = $baseTagQuery -replace "\]", " && tags.deployment == '${DeploymentName}']"
                }
                "Suffix" {
                    $suffixQuery = "("
                    foreach ($suff in $Suffix) {
                        if ($suffixQuery -ne "(") {
                            $suffixQuery += " || "
                        }
                        $suffixQuery += "tags.suffix == '${suff}'"
                    }
                    $suffixQuery += ")"
                    $baseTagQuery = $baseTagQuery -replace "\]", " && $suffixQuery]"
                }
                "Workspace" {
                    $baseTagQuery = $baseTagQuery -replace "\]", " && tags.workspace == '${Workspace}']"
                }
            }
            $tagQuery = $baseTagQuery -replace "\]", " && properties.provisioningState != 'Deleting']"
            Write-Host "Removing resources which match JMESPath `"$tagQuery`"" -ForegroundColor Green
            if (!$Force) {
                $proceedanswer = $null
                Write-Host "Do you wish to proceed removing '${Repository}' resources? `nplease reply 'yes' - null or N aborts" -ForegroundColor Cyan
                $proceedanswer = Read-Host
                if ($proceedanswer -ne "yes") {
                    return
                }
            }
    
            # Remove resource groups 
            Write-Host "Removing '${Repository}' resource groups (async)..."
            $resourceGroupIDs = $(az group list --query "$tagQuery" -o tsv)
            if ($resourceGroupIDs -and $resourceGroupIDs.Length -gt 0) {
                Write-Verbose "Starting job 'az resource delete --ids $resourceGroupIDs'"
                Start-Job -Name "Remove Resource Groups" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceGroupIDs | Out-Null
            }
    
            # Remove other tagged resources
            Write-Host "Removing '${Repository}' resources (async)..."
            $resourceIDs = $(az resource list --query "$tagQuery" -o tsv)
            if ($resourceIDs -and $resourceIDs.Length -gt 0) {
                Write-Verbose "Starting job 'az resource delete --ids $resourceIDs'"
                Start-Job -Name "Remove Resources" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceIDs | Out-Null
            }
    
            # Remove resources in the NetworkWatcher resource group
            Write-Host "Removing '${Repository}' network watchers from shared resource group 'NetworkWatcherRG' (async)..."
            $resourceIDs = $(az resource list -g NetworkWatcherRG --query "$tagQuery" -o tsv)
            if ($resourceIDs -and $resourceIDs.Length -gt 0) {
                Write-Verbose "Starting job 'az resource delete --ids $resourceIDs'"
                Start-Job -Name "Remove Resources from NetworkWatcherRG" -ScriptBlock {az resource delete --ids $args} -ArgumentList $resourceIDs | Out-Null
            }
    
            # Remove DNS records using tags expressed as record level metadata
            $metadataQuery = $tagQuery -replace "tags\.","metadata."
            Write-Verbose "JMESPath Metadata Query: $metadataQuery"
            # Synchronous operation, as records will clash with new deployments
            Write-Host "Removing '${Repository}' records from shared DNS zone (sync)..."
            $dnsZones = $(az network dns zone list | ConvertFrom-Json)
            foreach ($dnsZone in $dnsZones) {
                Write-Verbose "Processing zone '$($dnsZone.name)'..."
                $dnsResourceIDs = $(az network dns record-set list -g $dnsZone.resourceGroup -z $dnsZone.name --query "$metadataQuery" -o tsv)
                if ($dnsResourceIDs) {
                    Write-Verbose "Removing DNS records from zone '$($dnsZone.name)'..."
                    az resource delete --ids $dnsResourceIDs -o none
                }
            }
    
            # Remove policy (set) definitions with tags expressed as metadata
            $metadataQuery = $baseTagQuery -replace "tags\.","metadata."
            Write-Verbose "JMESPath Metadata Query: $metadataQuery"
            Write-Host "Removing '${Repository}' policy set definitions (sync)..."
            az policy set-definition list --query "${metadataQuery}" -o json | ConvertFrom-Json | Set-Variable policySets
            foreach ($policySet in $policySets) {
                Write-Verbose "Deleting policy set '$($policySet.name)'..."
                az policy set-definition delete --name $policySet.name
            }
            Write-Host "Removing '${Repository}' policy definitions (sync)..."
            az policy definition list --query "${metadataQuery}" -o json | ConvertFrom-Json | Set-Variable policies
            foreach ($policy in $policies) {
                Write-Verbose "Deleting policy '$($policy.name)'..."
                az policy definition delete --name $policy.name
            }

            $jobs = Get-Job -State Running | Where-Object {$_.Command -match "az resource"}
            $jobs | Format-Table -Property Id, Name, Command, State
            if ($Wait -and $jobs) {
                # Waiting for async operations to complete
                WaitFor-Jobs -Jobs $jobs -TimeoutMinutes $TimeoutMinutes
            }
        }
    } finally {
        PopFrom-TerraformDirectory 
    }
}
Set-Alias tferase Erase-TerraformAzureResources

function Find-RepositoryDirectory {
    $depth = 2

    if (Test-Path LICENSE) {
        return (Get-Location).Path
    } else {
        $license = Get-ChildItem -Path . -Filter LICENSE -Recurse -Depth $depth -ErrorAction SilentlyContinue | Select-Object -First 1
        if (!$license) {
            # Go one level below current directory
            $license = Get-ChildItem -Path .. -Filter LICENSE -Recurse -Depth $depth -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($license) {
            return $license.Directory.FullName
        }
        return $null
    }
}

function Find-TerraformDirectory {
    $depth = 2

    if (Test-Path *.tf) {
        return (Get-Location).Path
    } else {
        $main = Get-ChildItem -Path . -Filter main.tf -Recurse -Depth $depth -ErrorAction SilentlyContinue | Select-Object -First 1
        if (!$main) {
            # Go one level below current directory
            $main = Get-ChildItem -Path .. -Filter main.tf -Recurse -Depth $depth -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($main) {
            return $main.Directory.FullName
        }
        return $null
    }
}

function Get-TerraformEnvironment {
    Write-Host "Environment variables:" -ForegroundColor Green
    Get-ChildItem -Path Env: -Recurse -Include ARM_*,AWS_*,TF_* | Sort-Object -Property Name
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
                Write-Verbose "Reading Terraform settings from ${stateFile}..."
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
                Write-Verbose "Checking lease status of backend blobs..."
                
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
            Get-ChildItem -Path Env: -Recurse -Include ARM_*,AWS_*,TF_* | Sort-Object -Property Name

            # Azure resources
            $resourceQuery = "Resources | where tags['provisioner']=='terraform' | summarize ResourceCount=count() by Repository=tostring(tags['repository']), Deployment=tostring(tags['deployment-name']), Environment=tostring(tags['environment']), Workspace=tostring(tags['workspace']), Suffix=tostring(tags['suffix']) | order by Repository asc, Environment asc, Workspace asc, Suffix asc"
            Write-Verbose "Executing graph query:`n$resourceQuery"
            Write-Host "`nAzure resources:`n" -ForegroundColor Green
            az extension add --name resource-graph 2>$null
            az graph query -q $resourceQuery --query "data" -o table
        }
    } finally {
        PopFrom-TerraformDirectory 
    }
}
Set-Alias tfi Get-TerraformInfo

function Get-TerraformWorkspace () {
    if ($env:TF_WORKSPACE) {
        Write-Debug "Get-TerraformWorkspace: $($env:TF_WORKSPACE)"
        return $env:TF_WORKSPACE
    }

    $null = ChangeTo-TerraformDirectory
    try {
        $workspace = $(terraform workspace show)
    } finally {
        PopFrom-TerraformDirectory 
    }

    Write-Debug "Get-TerraformWorkspace: $workspace"
    return $workspace
}
Set-Alias gtfw Get-TerraformWorkspace 
Set-Alias tfwg Get-TerraformWorkspace 

function Get-Blobs (
    [parameter(Mandatory=$true)][string]$BackendStorageAccountName,
    [parameter(Mandatory=$true)][string]$BackendStorageContainerName,
    [parameter(Mandatory=$true)][string]$JmesPath
) {
    Write-Verbose "Retrieving blobs from https://${BackendStorageAccountName}.blob.core.windows.net/${BackendStorageContainerName}..."
    if ($env:ARM_ACCESS_KEY) {
        $blobs = az storage blob list -c $BackendStorageContainerName --account-name $BackendStorageAccountName --account-key $env:ARM_ACCESS_KEY --query $JmesPath | ConvertFrom-Json
    } else {
        if ($env:ARM_SAS_TOKEN) {
            $blobs = az storage blob list -c $BackendStorageContainerName --account-name $BackendStorageAccountName --sas-token $env:ARM_SAS_TOKEN --query $JmesPath | ConvertFrom-Json
        } else {
            Write-Verbose "Environment variable ARM_ACCESS_KEY or ARM_SAS_TOKEN not set, trying az auth"
            $blobs = az storage blob list -c $BackendStorageContainerName --account-name $BackendStorageAccountName --auth-mode login --query $JmesPath | ConvertFrom-Json
            if (!$blobs) {
                Write-Verbose "No access to storage using KEY, SAS or SSO. Trying to obtain key..."
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

function List-TerraformOutput (
    [parameter(Mandatory=$false)][string]$SearchPattern
) {
    $command = "terraform output"
    if ($SearchPattern) {
        if ($SearchPattern -match "\*") {
            $command += " | Select-String -Pattern '$SearchPattern'"
        } else {
            $command += " $SearchPattern"
        }
    }
    Invoke-TerraformCommand $command
}
Set-Alias tfo List-TerraformOutput

function Search-TerraformOutput (
    [parameter(Mandatory=$true)][string]$Substring
) {
    Invoke-TerraformCommand "terraform output | Select-String -Pattern '^.*${Substring}.*$'"
}
Set-Alias tfos Search-TerraformOutput

function List-TerraformState (
    [parameter(Mandatory=$false)][string]$SearchPattern
) {
    $command = "terraform state list"
    if ($SearchPattern) {
        $command += " | Select-String -Pattern $SearchPattern"
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
        Write-Verbose "Stack is empty"
    }
}
Set-Alias cdtf- PopFrom-TerraformDirectory
Set-Alias tfcd- PopFrom-TerraformDirectory

function RemoveFrom-TerraformState (
    [parameter(Mandatory=$true,ValueFromPipeline=$true)][string]$Resource
) {
    process {
        foreach ($res in $Resource) {
            Invoke-TerraformCommand "terraform state rm $res"
        }
    }
}
Set-Alias tfrm RemoveFrom-TerraformState

function Set-TerraformAzureSubscription(
    [parameter(Mandatory=$true,Position=0)][string]$SubscriptionID
) {
    $env:ARM_SUBSCRIPTION_ID = $SubscriptionID
    az account set --subscription $env:ARM_SUBSCRIPTION_ID
    az account show
}
Set-Alias stas Set-TerraformAzureSubscription

function Set-TerraformWorkspace (
    [parameter(Mandatory=$true)][string]$Workspace
) {
    if ($env:TF_WORKSPACE) {
        if ($env:TF_WORKSPACE -eq $Workspace) {
            Write-Verbose "Using `$env:TF_WORKSPACE = `'$($env:TF_WORKSPACE)`', nothing to set"
            return
        } else {
            Write-Warning "Specified workspace '$Workspace' while `$env:TF_WORKSPACE = `'$($env:TF_WORKSPACE)`'"
        }
    }
    Invoke-TerraformCommand "terraform workspace select $Workspace"
    Set-TerraformWorkspaceEnvironmentVariables -Workspace $Workspace
}
Set-Alias ctfw Set-TerraformWorkspace  
Set-Alias ctf Set-TerraformWorkspace  
Set-Alias tfws Set-TerraformWorkspace  
Set-Alias tfw Set-TerraformWorkspace  

function Set-TerraformWorkspaceEnvironmentVariables (
    [parameter(Mandatory=$false)][string]$Workspace=$env:TF_WORKSPACE
) {
    if (!$Workspace) {
        Write-Warning "No workspace specified, nothing to do"
    }

    $script:environmentVariableNames = @()

    $regexCallback = {
        $terraformEnvironmentVariableName = "ARM_$($args[0])".ToUpper()
        $script:environmentVariableNames += $terraformEnvironmentVariableName
        "`n`$env:${terraformEnvironmentVariableName}"
    }

    # $env:TF_WORKSPACE = $Workspace
    # $script:environmentVariableNames += "TF_WORKSPACE"

    $terraformDirectory = Find-TerraformDirectory
    if ($terraformDirectory) {
        $terraformWorkspaceVars = (Join-Path $terraformDirectory "${Workspace}.tfvars")
        if (Test-Path $terraformWorkspaceVars) {
            # Match relevant lines first
            $terraformVarsFileContent = (Get-Content $terraformWorkspaceVars | Select-String "(?m)^[^#\w]*(client_id|client_secret|subscription_id|tenant_id)")
            if ($terraformVarsFileContent) {
                $envScript = [regex]::replace($terraformVarsFileContent,"(client_id|client_secret|subscription_id|tenant_id)",$regexCallback,[System.Text.RegularExpressions.RegexOptions]::Multiline)
                if ($envScript) {
                    Write-Verbose $envScript
                    Invoke-Expression $envScript
                    Get-ChildItem -Path Env: -Recurse -Include $script:environmentVariableNames | Sort-Object -Property Name
                } else {
                    Write-Warning "[regex]::replace removed all content from script"
                }
            } else {
                Write-Verbose "No matches"
            }
        }
    }    
}
Set-Alias tfwe Set-TerraformWorkspaceEnvironmentVariables  

function Taint-TerraformResource (
    [parameter(Mandatory=$true,ValueFromPipeline=$true)][string[]]$Resource
) {
    process {
        foreach ($res in $Resource) {
            $res = ($res -replace "`"","`\`"")
            Invoke-TerraformCommand "terraform taint '$res'"
        }
    }
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
            Write-Verbose "Reading Terraform settings from ${tfdirectory}/.terraform/terraform.tfstate..."
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
                        Write-Verbose "Environment variable ARM_ACCESS_KEY or ARM_SAS_TOKEN not set, trying az auth"
                        $ticks = az storage blob lease break -b $blobName -c $backendStorageContainerName --account-name $BackendStorageAccountName --auth-mode login
                        if (!$ticks) {
                            Write-Verbose "No access to storage using KEY, SAS or SSO. Trying to obtain key..."
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

function WaitFor-Jobs (
    [parameter(Mandatory=$true)][object[]]$Jobs,
    [parameter(Mandatory=$false)][int]$TimeoutMinutes=5
) {
    if ($Jobs) {
        $updateIntervalSeconds = 10 # Same as Terraform
        $stopWatch = New-Object -TypeName System.Diagnostics.Stopwatch     
        $stopWatch.Start()
    
        Write-Host "Waiting for jobs to complete..."
    
        do {
            $runningJobs = $Jobs | Where-Object {$_.State -like "Running"}
            $elapsed = $stopWatch.Elapsed.ToString("m'm's's'")
            Write-Host "$($runningJobs.Count) jobs in running state [$elapsed elapsed]"
            $null = Wait-Job -Job $Jobs -Timeout $updateIntervalSeconds
        } while ($runningJobs -and ($stopWatch.Elapsed.TotalMinutes -lt $TimeoutMinutes)) 
    
        $jobs | Format-Table -Property Id, Name, State
        if ($waitStatus) {
            Write-Warning "Jobs did not complete before timeout (${TimeoutMinutes}m) expired"
        } else {
            # Timeout expired before jobs completed
            $elapsed = $stopWatch.Elapsed.ToString("m'm's's'")
            Write-Host "Jobs completed in $elapsed"
        }
    }
}