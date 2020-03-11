#!/usr/bin/env pwsh

$scriptDirectory = Split-Path -Parent -Path $MyInvocation.MyCommand.Path

# Load Functions
. (Join-Path $scriptDirectory "functions.ps1")


# Check whether Az modules have been installed
AddorUpdateModule Az
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

LinkFile -File $profileName -SourceDirectory $scriptDirectory -TargetDirectory $profileDirectory
LinkFile -File functions.ps1 -SourceDirectory $scriptDirectory -TargetDirectory $profileDirectory

# Non-pwsh common tasks
if (Get-Command az -ErrorAction SilentlyContinue) {
    Write-Host "`nUpdating az-cli extensions"
    az extension add --name azure-devops
}
