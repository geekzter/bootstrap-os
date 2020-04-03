function Connect-TmuxSession (
    [string]$Workspace
) {
    if (!$Workspace -and (Get-Command terraform)) {
        $Workspace = $(terraform workspace show 2>$null)
    }
    if (!$Workspace) {
        $Workspace = "default"
    }

    $prexistingSession = $(tmux ls -F "#S" 2>$null) -match "^${Workspace}$"
    if ($prexistingSession) {
        tmux attach-session -d -t $Workspace
    } else {
        tmux new -s $Workspace
    }

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