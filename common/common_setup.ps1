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

$scriptDirectory = (Split-Path -Parent -Path $MyInvocation.MyCommand.Path)

# Load Functions
. (Join-Path (Join-Path $scriptDirectory functions) functions.ps1)

# Set up PowerShell Core (modules, profile)
& (Join-Path $scriptDirectory "bootstrap_pwsh.ps1") -NoPackages:$NoPackages

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
& (Join-Path $scriptDirectory "create_dotfiles.ps1")

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
        az extension list --query "[].name" -o tsv | Set-Variable azExtensions
        foreach ($azExtension in $azExtensions) {
            Write-Host "Updating Azure CLI extension '$azExtension'..."
            az extension update -n $azExtension --only-show-errors
        }

        Compare-Object -ReferenceObject $azExtensions `
                       -DifferenceObject @('azure-devops', `
                                           'azure-firewall', `
                                           'resource-graph') | Where-Object -Property SideIndicator -eq '=>' `
                                                             | ForEach-Object {
            Write-Host "Adding Azure CLI extension '$($_.InputObject)'..."
            az extension add -n $_.InputObject --only-show-errors
        }
    }
}

Clone-GitHubRepositories