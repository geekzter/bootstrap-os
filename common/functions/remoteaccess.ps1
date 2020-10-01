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
        # Set Terraform workspace to the name of the session
        Write-Verbose "`$env:TF_WORKSPACE='$Workspace'"
        tmux send-keys -t $Workspace "`$env:TF_WORKSPACE='$Workspace'" Enter
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