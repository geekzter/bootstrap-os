#!/usr/bin/env pwsh

<#
.SYNOPSIS 
    Script used to bootstrap Windows workstation
 
.DESCRIPTION 
    Pre-git bootstrap stage
    - Installs git
    - Get's latest version of repo
    - Kicks off next stage

.EXAMPLE
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://github.com/geekzter/bootstrap-os/blob/master/vso/linux/bootstrap_vso.ps1'))
#> 
param ( 
    [parameter(Mandatory=$false)][string]$Repository="https://github.com/geekzter/bootstrap-os"
) 

# Clone (the rest of) the repository
$repoDirectory = Join-Path $HOME "src"
if (!(Test-Path $repoDirectory)) {
    New-Item -ItemType Directory -Force -Path $repoDirectory
}

$bootstrapDirectory = Join-Path $repoDirectory "bootstrap-os"
if (!(Test-Path $bootstrapDirectory)) {
    Set-Location $repoDirectory    
    Write-Host "Cloning $Repository into $repoDirectory..."
    git clone $Repository   
} else {
    # git update if repo already exists
    Set-Location $bootstrapDirectory
    Write-Host "Pulling $Repository in $bootstrapDirectory..."
    git pull
}
$vsoBootstrapDirectory = Join-Path $bootstrapDirectory "vso/linux"
if (!(Test-Path $vsoBootstrapDirectory)) {
    Write-Error "Clone of bootstrap repository was not successful"
    exit
} else {
    Set-Location $vsoBootstrapDirectory
}