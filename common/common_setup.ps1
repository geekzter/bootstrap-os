#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Setup common to Linux, macOS, Windows

.DESCRIPTION 
    Setup common to Linux, macOS, Windows. This also includes setup that is used by more than one OS, but not all.
#>

# Set up PowerShell Core (modules, profile)
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "bootstrap_pwsh.ps1")


# Set up dotfiles
& (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "create_dotfiles.ps1")

