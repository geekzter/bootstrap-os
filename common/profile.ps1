#!/usr/bin/env pwsh

# Define Functions
Write-Verbose "Defining functions..."
$functionsPath = (Join-Path (Split-Path $MyInvocation.MyCommand.Path –Parent) "functions")
Get-ChildItem $functionsPath -filter "*.ps1" | ForEach-Object {
    Write-Host "$($_.FullName) : loaded"
    . $_.FullName
}

# Define prompt
Write-Verbose "Defining prompt..."
function global:Prompt {
    if ($GitPromptScriptBlock) {
        # Use Posh-Git: https://github.com/dahlbyk/posh-git/wiki/Customizing-Your-PowerShell-Prompt
        # Use ~ for home directory in prompt
        $GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = $true 
        # Don't overwrite the title set in iTerm2/Windows Terminal
        $GitPromptSettings.WindowTitle = $null
        if ($env:CODESPACES -ieq "true") {
            $GitPromptSettings.DefaultPromptPrefix  = "[${env:GITHUB_REPOSITORY}]: "
        } else {
            if (IsElevated) {
                $GitPromptSettings.DefaultPromptSuffix = "`$('#' * (`$nestedPromptLevel + 1)) "
            } else {
                $GitPromptSettings.DefaultPromptSuffix = "`$('>' * (`$nestedPromptLevel + 1)) "
            }    
        }
        $prompt = (& $GitPromptScriptBlock)
    } else {
        $host.ui.rawui.WindowTitle = "PowerShell Core $($host.Version.ToString())"

        if ($executionContext.SessionState.Path.CurrentLocation.Path.StartsWith($home)) {
            $path = $executionContext.SessionState.Path.CurrentLocation.Path.Replace($home,"~")
        } else {
            $path = $executionContext.SessionState.Path.CurrentLocation.Path
        }

        $host.ui.rawui.WindowTitle += "$($executionContext.SessionState.Path.CurrentLocation.Path)"
        $branch = $(git rev-parse --abbrev-ref HEAD 2>$null)
        $prompt = $path
        if ($branch) {
            $prompt += ":$branch"
        }
        if (IsElevated) {
            $host.ui.rawui.WindowTitle += " # "
            $prompt += "$('#' * ($nestedPromptLevel + 1)) ";
        } else {
            $host.ui.rawui.WindowTitle += " - "
            $prompt += "$('>' * ($nestedPromptLevel + 1)) ";
        }
    }
    if ($prompt) { "$prompt" } else { " " }
}

# Only print when not in a nested shell, tmux session, or Codespace
$printMessages = (($nestedPromptLevel -eq 0) -and $($env:TERM -notmatch "^screen") -and $($env:TERM -notmatch "^tmux") -and (!($env:CLOUDENV_ENVIRONMENT_ID)))

if ($host.Name -eq 'ConsoleHost')
{
    Import-InstalledModule posh-git
    # Import-InstalledModule oh-my-posh
    # Requires PSReadLine 2.0
    #Set-Theme Agnoster
    #Set-Theme Paradox
    Import-InstalledModule Terminal-Icons
}

# Linux & macOS only:
if ($PSVersionTable.PSEdition -and ($PSVersionTable.PSEdition -eq "Core") -and ($IsLinux -or $IsMacOS)) {
    Write-Verbose "Updating PATH..."

    # Manage PATH environment variable
    [System.Collections.ArrayList]$pathList = $env:PATH.Split(":")
    if (!$pathList.Contains("/usr/local/bin")) {
        $pathList.Insert(1,"/usr/local/bin")
    }
    if ((Test-Path "~/.dotnet/tools") -and (!$pathList.Contains("~/.dotnet/tools"))) {
        $null = $pathList.Add("~/.dotnet/tools")
    }
    if ((Test-Path "/usr/local/share/dotnet") -and (!$pathList.Contains("/usr/local/share/dotnet"))) {
        $null = $pathList.Add("/usr/local/share/dotnet")
    }
    if (Get-Command ruby -ErrorAction SilentlyContinue) {
        $null = $(ruby --version) -match '^ruby *(?<version>[\d\.]+)' 
        $rubyVersion = [version]$Matches['version']
        $rubyVersionString = "$($rubyVersion.ToString(2)).0"
        if (!$pathList.Contains("~/.gem/ruby/${rubyVersionString}/bin")) {
            $null = $pathList.Insert(0,"~/.gem/ruby/${rubyVersionString}/bin")
        }
    }
    if ($IsMacOS -and (Test-Path "/usr/local/opt/tmux@2.6/bin") -and !$pathList.Contains("/usr/local/opt/tmux@2.6/bin")) {
        $null = $pathList.Insert(0,"/usr/local/opt/tmux@2.6/bin")
    }
    if ($IsMacOS -and (Test-Path "/opt/homebrew/opt/tmux@2.6/bin") -and !$pathList.Contains("/opt/homebrew/opt/tmux@2.6/bin")) {
        $null = $pathList.Insert(0,"/opt/homebrew/opt/tmux@2.6/bin")
    }
    if (!($(Get-Command tfenv -ErrorAction SilentlyContinue)) -and (Test-Path ~/.tfenv/bin) -and !$env:PATH.Contains("tfenv/bin")) {
        $null = $pathList.Add("${env:HOME}/.tfenv/bin")
    }
    $env:PATH = $pathList -Join ":"
}

# Source environment variables from ~/.config/powershell/environment.ps1
Write-Verbose "Sourcing environment.ps1..."
$environmentPath = (Join-Path (Split-Path $MyInvocation.MyCommand.Path –Parent) "environment.ps1")
if (Test-Path -Path $environmentPath) {
    . $environmentPath
    if ($printMessages) {
        Write-Host "${environmentPath}: sourced"
    }
} else {
    if ($printMessages -and (!$IsWindows)) {
        Write-Host "$environmentPath not found"
    }
}


if ($printMessages) {

    $azModule = Get-Module Az -ListAvailable | Select-Object -First 1     
    if ($azModule) {
        Write-Host "PowerShell $($azModule.Name) v$($azModule.Version)"
    }
 
    # Print message on bootstrap configuration
    $bootstrapDirectory = Split-Path -Parent (Split-Path -Parent (Get-Item $MyInvocation.MyCommand.Path).Target)
    Write-Host "To update configuration, run " -NoNewline
    if ($IsWindows) {
        Write-Host "(Windows PowerShell)`n$bootstrapDirectory\windows\bootstrap_windows.ps1"
    }
    if ($IsMacOS) {
        Write-Host "$bootstrapDirectory/macOS/bootstrap_mac.sh"
    }
    if ($IsLinux) {
        Write-Host "$bootstrapDirectory/linux/bootstrap_linux.sh"
    }

    # Show tmux sessions
    if (($IsLinux -or $IsMacOS) -and (Get-Command tmux -ErrorAction SilentlyContinue)) {
        $tmuxSessions = $(tmux ls 2>/dev/null)
        if ($tmuxSessions) {
            Write-Host "Active tmux sessions:"
            $tmuxSessions
        }
    }
}

# Go to home (not automatic for elevated prompt)
if (IsElevated) {
    # But only if not a nested shell
    $parentProcess = (Get-Process -id $pid).Parent
   if (($parentProcess.ProcessName -ine "code") -and ($parentProcess.Parent.ProcessName -ine "pwsh")) {        
        if ($home -and (Test-Path $home)) {
            Set-Location $home
        } else {
            if ($env:USERPROFILE -and (Test-Path $env:USERPROFILE)) {
                Set-Location $env:USERPROFILE
            } 
        }
    }
}

# Set environment variables
$env:SHELL = (Get-Command pwsh).Source