function Connect-TmuxSession (
    [string]$Workspace=($env:TF_WORKSPACE ? $env:TF_WORKSPACE : "default")
) {
    if ($env:TMUX) {
        Write-Warning "Session already exixts: $env:TMUX"
        return
    }

    if (!$Workspace -and (Get-Command terraform)) {
        $Workspace = $(terraform workspace show 2>$null)
    }

    $prexistingSession = $(tmux ls -F "#S" 2>$null) -match "^${Workspace}$"
    if (!$prexistingSession) {
        # Start session, but do not yet attach
        tmux new -d -s $Workspace
        Write-Verbose "`$env:TF_WORKSPACE='$Workspace'"
        tmux send-keys -t $Workspace "`$env:TF_WORKSPACE='$Workspace'" Enter
    }

    # Attach
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