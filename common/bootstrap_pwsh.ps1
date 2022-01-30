#!/usr/bin/env pwsh
#Requires -Version 7
param ( 
    [parameter(Mandatory=$false)][switch]$NoPackages=$false
) 

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$functionsDirectory = Join-Path $scriptDirectory functions
# Load Functions
. (Join-Path $functionsDirectory functions.ps1)


if (-not $NoPackages) {
    # Check whether Az modules have been installed
    AddorUpdateModule -ModuleName Az -AllowClobber
    #AddorUpdateModule AzureADPreview
    #AddorUpdateModule MicrosoftPowerBIMgmt
    #AddorUpdateModule MicrosoftTeams
    AddorUpdateModule Oh-My-Posh
    AddorUpdateModule Posh-Git
    # https://docs.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-72?view=powershell-7.2#separating-dsc-from-powershell-7-to-enable-future-improvements
    if ($PSVerSionTable.PSVersion -ge 7.2) {
        # The PSDesiredStateConfiguration module was removed from the PowerShell 7.2 package and is now published to the PowerShell Gallery
        AddorUpdateModule PSDesiredStateConfiguration
    }
    # AddorUpdateModule PSReadLine
    # https://docs.microsoft.com/en-us/powershell/scripting/whats-new/what-s-new-in-powershell-72?view=powershell-7.2#psreadline-21-predictive-intellisense
    $psReadLineOptionCommand = (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)
    if ($psReadLineOptionCommand -and $psReadLineOptionCommand.Version -ge 2.1) {
        Set-PSReadLineOption -PredictionSource History
    }
    AddorUpdateModule SqlServer
    AddorUpdateModule Terminal-Icons
    AddorUpdateModule VSTeam
    if ($IsWindows) {
        AddorUpdateModule WindowsCompatibility
    }
}

# Create symbolic link for PowerShell Core profile directory
$profileDirectory = Split-Path -Parent $profile.CurrentUserAllHosts
$profileName = Split-Path -Leaf $profile.CurrentUserAllHosts
$null = New-Item -ItemType Directory -Force -Path $profileDirectory 

LinkFile -File $profileName -SourceDirectory $scriptDirectory -TargetDirectory $profileDirectory
LinkDirectory -SourceDirectory (Join-Path $profileDirectory functions) -TargetDirectory $functionsDirectory