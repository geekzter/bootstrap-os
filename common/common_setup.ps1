#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Setup common to Linux, macOS, Windows

.DESCRIPTION 
    Setup common to Linux, macOS, Windows. This also includes setup that is used by more than one OS, but not all.
#>

# Set up PowerShell Core (modules, profile)
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "bootstrap_pwsh.ps1")

# Configure PowerShell as default shell on Linux & macOS
if ($IsLinux -or $IsMacos) {
    $pwshPath = (Get-Command pwsh).Source
    if ($pwshPath -ne $env:SHELL) {
        Write-Host "Replacing $env:SHELL with $pwshPath as default shell"
        sudo chsh -s $pwshPath
    }
}

# Set up dotfiles
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "create_dotfiles.ps1")

# Configure git
git config --global core.excludesfile (Join-Path $HOME .gitignore)
