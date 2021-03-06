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
    if (($pwshPath -ne $env:SHELL) -and (CanElevate)) {
        Write-Host "Replacing $env:SHELL with $pwshPath as default shell"
        RunElevated chsh -s $pwshPath
    }
}

# Set up dotfiles
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "create_dotfiles.ps1")

# Configure Git
$settingsFile = (Join-Path $PSScriptRoot settings.json)
if (Test-Path $settingsFile) {
    $settings = (Get-Content (Join-Path $PSScriptRoot settings.json)) | ConvertFrom-Json
}
git config --global core.autocrlf true # May be needed for Windows to not mess up Git
git config --global core.excludesfile (Join-Path $HOME .gitignore)
git config --global pull.rebase false
if ($settings.GitEmail) {
    git config --global user.email $settings.GitEmail
}
if ($settings.GitName) {
    git config --global user.name $settings.GitName
}
if (CanElevate) {
    RunElevated git config --system core.longpaths true
}

if (-not $NoPackages) {
    # Azure CLI extensions
    if (Get-Command az -ErrorAction SilentlyContinue) {
        Write-Host "`nUpdating Azure CLI extensions..."
        az extension add -n azure-devops   --upgrade -y 2>&1
        az extension add -n azure-firewall --upgrade -y 2>&1
        az extension add -n resource-graph --upgrade -y 2>&1
    }
}