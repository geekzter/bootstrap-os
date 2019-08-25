#!/usr/bin/env pwsh

function AddorUpdateModule (
    [string]$moduleName
) {
    if (Get-InstalledModule $moduleName -ErrorAction SilentlyContinue) {
        $moduleVersionString = Get-InstalledModule $moduleName | Sort-Object -Descending Version | Select-Object -First 1 -ExpandProperty Version
        $moduleVersion = New-Object System.Version($moduleVersionString)
        $moduleUpdateVersionString = "{0}.{1}.{2}" -f $moduleVersion.Major, $moduleVersion.Minor, ($moduleVersion.Build + 1)
        # Check whether newer module exists
        if (Find-Module $moduleName -MinimumVersion $moduleUpdateVersionString -ErrorAction SilentlyContinue) {
            Write-Host "PowerShell Core $moduleName module $moduleVersionString is out of date. Updating Az modules..."
            Update-Module $moduleName -AcceptLicense -Force
        } else {
            Write-Host "PowerShell Core $moduleName module $moduleVersionString is up to date"
        }
    } else {
        # Install module if not present
        Write-Host "Installing PowerShell Core $moduleName module..."
        Install-Module $moduleName -Force -SkipPublisherCheck -AcceptLicense 
    }
}

# Create symbolic link for PowerShell Core profile directory
$psCoreProfileDirectory = Split-Path -Parent $PROFILE
if (!(Test-Path $psCoreProfileDirectory)) {
    mkdir $psCoreProfileDirectory
}
if (Test-Path $PROFILE) {
    Write-Host "Powershell Core profile $PROFILE already exists"
} else {
    $psProfileJunctionTarget = $(Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "profile.ps1")

    Write-Host "Creating symbolic link from $PROFILE to $psProfileJunctionTarget"
    New-Item -ItemType symboliclink -path "$PROFILE" -value "$psProfileJunctionTarget"
}  

# Check whether Az modules have been installed
AddorUpdateModule Az

if ($IsWindows) {
    AddorUpdateModule WindowsCompatibility
}