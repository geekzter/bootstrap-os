#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Setup common to Linux, macOS, Windows

.DESCRIPTION 
    Setup common to Linux, macOS, Windows. This also includes setup that is used by more than one OS, but not all.
#>
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false)][switch]$NoPackages=$false
) 

# Set up PowerShell Core (modules, profile)
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "bootstrap_pwsh.ps1") -NoPackages:$NoPackages

# Configure PowerShell as default shell on Linux & macOS
if ($IsLinux -or $IsMacos) {
    $pwshPath = (Get-Command pwsh).Source
    if (($pwshPath -ne $env:SHELL) -and (Get-Command sudo -ErrorAction SilentlyContinue)) {
        Write-Host "Replacing $env:SHELL with $pwshPath as default shell"
        sudo chsh -s $pwshPath
    }
}

# Set up dotfiles
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "create_dotfiles.ps1")

# Configure git
git config --global core.excludesfile (Join-Path $HOME .gitignore)

if (-not $NoPackages) {
    # Ruby gems
    if ((Get-Command sudo -ErrorAction SilentlyContinue) -and (Get-Command gem -ErrorAction SilentlyContinue)) {
        Write-Host "`nUpdating Ruby gems..."
        sudo gem update
        gem install --user-install bundler jekyll
    }

    # Azure CLI extensions
    if (Get-Command az -ErrorAction SilentlyContinue) {
        Write-Host "`nUpdating Azure CLI extensions..."
        az extension add -y -n azure-devops
        az extension add -y -n azure-firewall
        az extension add -y -n resource-graph
    }
}