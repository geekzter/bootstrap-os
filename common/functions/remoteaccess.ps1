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
        # Match relevant lines first
        $terraformVarsFileContent = (Get-Content $terraformWorkspaceVars | Select-String "(?m)^[^#]*(client_id|client_secret|subscription_id|tenant_id)")
        if ($terraformVarsFileContent) {
            $envScript = [regex]::replace($terraformVarsFileContent,"(client_id|client_secret|subscription_id|tenant_id)",$regexCallback,[System.Text.RegularExpressions.RegexOptions]::Multiline)
            if ($envScript) {
                Write-Verbose $envScript
                Invoke-Expression $envScript
            } else {
                Write-Warning "[regex]::replace removed all content from script"
            }
        } else {
            Write-Verbose "No matches"
        }
    }
    Get-ChildItem -Path Env: -Recurse -Include $script:environmentVariableNames | Sort-Object -Property Name

    Write-Debug "Environment variables: $script:environmentVariableNames"
}