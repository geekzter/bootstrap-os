#!/usr/bin/env pwsh

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path
$functionsDirectory = Join-Path $scriptDirectory functions
# Load Functions
. (Join-Path $functionsDirectory functions.ps1)


# Check whether Az modules have been installed
AddorUpdateModule -ModuleName Az -AllowClobber
#AddorUpdateModule AzureADPreview
#AddorUpdateModule MicrosoftPowerBIMgmt
#AddorUpdateModule MicrosoftTeams
AddorUpdateModule Oh-My-Posh
AddorUpdateModule Posh-Git
AddorUpdateModule PSReadLine
AddorUpdateModule SqlServer
AddorUpdateModule VSTeam
if ($IsWindows) {
    AddorUpdateModule WindowsCompatibility
}

# Create symbolic link for PowerShell Core profile directory
$profileDirectory = Split-Path -Parent $profile.CurrentUserAllHosts
$profileName = Split-Path -Leaf $profile.CurrentUserAllHosts
$null = New-Item -ItemType Directory -Force -Path $profileDirectory 

LinkFile -File $profileName -SourceDirectory $scriptDirectory -TargetDirectory $profileDirectory
LinkDirectory -SourceDirectory (Join-Path $profileDirectory functions) -TargetDirectory $functionsDirectory