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
    ./bootstrap_vso.ps1

.EXAMPLE
    pwsh -noexit -command {Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/vso/linux/bootstrap_vso.ps1')}
#> 
param ( 
    [parameter(Mandatory=$false)][switch]$SkipClone=$false,
    [parameter(Mandatory=$false)][string]$Repository="https://github.com/geekzter/bootstrap-os"
) 

if (!$SkipClone) {
    # Clone (the rest of) the repository
    $repoDirectory = Join-Path $HOME "src"
    if (!(Test-Path $repoDirectory)) {
        New-Item -ItemType Directory -Force -Path $repoDirectory
    }

    $bootstrapDirectory = Join-Path $repoDirectory "bootstrap-os"
    if (!(Test-Path $bootstrapDirectory)) {  
        Write-Host "Cloning $Repository into $repoDirectory..."
        git -C $repoDirectory clone $Repository   
    } else {
        # git update if repo already exists
        Write-Host "Pulling $Repository in $bootstrapDirectory..."
        git -C $bootstrapDirectory pull
    }
    $vsoBootstrapDirectory = Join-Path $bootstrapDirectory "vso/linux"
    if (!(Test-Path $vsoBootstrapDirectory)) {
        Write-Error "Clone of bootstrap repository was not successful"
        exit
    } else {
        Set-Location $vsoBootstrapDirectory
    }
}

# Invoke next stage
$stage2Script = "./bootstrap_vso2.ps1"
if (!(Test-Path $stage2Script)) {
    Write-Error "Stage 2 script $stage2Script not found, exiting"
    exit
}
if ($MyInvocation.line -match "ps1") {
    $stage2Command = $MyInvocation.line -replace "^.*ps1", $stage2Script -replace "-SkipClone", ""
} else {
    $stage2Command = $stage2Script
}

$stage2Command
Invoke-Expression "& ${stage2Command}" 