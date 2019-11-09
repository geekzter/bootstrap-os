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
    Not invoked directly
#> 

$MyInvocation.line

# Install snap package manager
if ($(Get-Command "snap" -ErrorAction SilentlyContinue) -eq $null) {
    sudo apt install snapd
}

# Set up terraform with tfenv
if (!(Test-Path ~/.tfenv)) {
    git clone https://github.com/tfutils/tfenv.git ~/.tfenv
    # Profile update will add tfenv to path
} else {
    git -C ~/.tfenv pull
}
tfenv install latest

# Configure PowerShell Core
pwsh -nop -file ../../common/bootstrap_pwsh.ps1
