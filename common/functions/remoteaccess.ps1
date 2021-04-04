#Requires -Version 7.0
function Connect-TmuxSession (
    # Use Terraform workspace variable as default session name
    [string]$Workspace=($env:TF_WORKSPACE ? $env:TF_WORKSPACE : "default") 
) {
    if ($env:TMUX) {
        Write-Warning "Session already exixts: $env:TMUX"
        return
    }

    if (!(Get-Command tmux -ErrorAction SilentlyContinue)) {
        Write-Warning "tmux not found"
        return
    }

    if (!$Workspace -and (Get-Command terraform)) {
        # Getworkspace name from current Terraform workspace, if installed
        $Workspace = $(terraform workspace show 2>$null)
    }

    # Set locale as it may be missing and is required for tmux
    $env:LANG   ??= "en_US.UTF-8"
    $env:LC_ALL ??= $env:LANG

    $prexistingSession = $(tmux ls -F "#S" 2>$null) -match "^${Workspace}$"
    if (!$prexistingSession) {
        # Start session, but do not yet attach
        tmux new -d -s $Workspace

        # Initialize session
        Write-Verbose "`$env:TF_WORKSPACE='$Workspace'"
        tmux send-keys -t $Workspace "Init-TmuxSession -Workspace $Workspace -Path ${env:PATH}" Enter
    }

    # Attach to session
    tmux attach-session -d -t $Workspace

}
Set-Alias ct Connect-TmuxSession



function End-TmuxSession (
    [string]$Workspace
) {
    if ($Workspace) {
        tmux kill-session -t $Workspace
    } else {
        pkill -f tmux
    }
}
Set-Alias et End-TmuxSession

function Init-TmuxSession (
    [string]$Workspace,
    [string]$Path
)
{
    $script:environmentVariableNames = @()

    # Inherit PATH
    $env:PATH = $Path
    $script:environmentVariableNames += "PATH"

    # Set Terraform workspace to the name of the session
    $env:TF_WORKSPACE = $Workspace
    $script:environmentVariableNames += "TF_WORKSPACE"

    $regexCallback = {
        $terraformEnvironmentVariableName = "ARM_$($args[0])".ToUpper()
        $script:environmentVariableNames += $terraformEnvironmentVariableName
        "`n`$env:${terraformEnvironmentVariableName}"
    }

    $terraformDirectory = Find-TerraformDirectory
    $terraformWorkspaceVars = (Join-Path $terraformDirectory "${Workspace}.tfvars")
    if (Test-Path $terraformWorkspaceVars) {
        # $re = [regex]"client_id|client_secret|subscription_id|tenant_id"
        $re = [regex]"(?m)^[^#]*(client_id|client_secret|subscription_id|tenant_id)"
        $terraformVarsFileContent = (Get-Content $terraformWorkspaceVars | Select-String "(?m)^[^#]*(client_id|client_secret|subscription_id|tenant_id)") # Match relevant lines first
        # $terraformVarsFileContent = (Get-Content $terraformWorkspaceVars -Raw | Select-String $re.ToString()) # Match relevant lines first
        if ($terraformVarsFileContent) {
            $re = [regex]"client_id|client_secret|subscription_id|tenant_id"
            # $envScript = $re.Replace($terraformVarsFileContent,$regexCallback)
            $envScript = $re.Replace((Get-Content $terraformWorkspaceVars | Select-String $re.ToString()),$regexCallback)
            # $envScript = $re.Replace((Get-Content $terraformWorkspaceVars -Raw | Select-String $re.ToString()),$regexCallback)
            # $envScript = $re.Replace((Get-Content $terraformWorkspaceVars | select-string "^[^#]*=" | Select-String $re.ToString()),$regexCallback)
            # $envScript = ($envScript | Select-String "(?m)^[^#]*=") # Hide commented lines
            if ($envScript) {
                Write-Verbose $envScript
                Invoke-Expression $envScript
            } else {
                Write-Verbose "Nothing to set"
            }
        } else {
            Write-Verbose "No matches for '$($re.ToString())'"
        }
    }
    Get-ChildItem -Path Env: -Recurse -Include $script:environmentVariableNames | Sort-Object -Property Name

    Write-Debug "Environment variables: $script:environmentVariableNames"
}