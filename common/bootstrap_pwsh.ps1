#!/usr/bin/env pwsh

function AddorUpdateModule (
    [string]$moduleName,
    [string]$desiredVersion
) {
    if (IsElevated) {
        $scope = "AllUsers"
    } else {
        $scope = "CurrentUser"
    }
    if (Get-InstalledModule $moduleName -ErrorAction SilentlyContinue) {
        $moduleVersionString = Get-InstalledModule $moduleName | Sort-Object -Descending Version | Select-Object -First 1 -ExpandProperty Version
        if ($moduleVersionString -Match "-") {
            # Installed module is pre-release, but we did not request a pre-release. So remove the pre-release moniker to get the desired version
            $desiredVersion = $moduleVersionString -Replace "-.*$",""
        }
        if ($desiredVersion) {
            $newModule = Find-Module $moduleName -RequiredVersion $desiredVersion -AllowPrerelease -ErrorAction SilentlyContinue
            $allowPrerelease = $true
        } else {
            $moduleVersion = New-Object System.Version($moduleVersionString)
            $desiredVersion = "{0}.{1}.{2}" -f $moduleVersion.Major, $moduleVersion.Minor, ($moduleVersion.Build + 1)
            $newModule = Find-Module $moduleName -MinimumVersion $desiredVersion -ErrorAction SilentlyContinue
        }
        
        # Check whether newer module exists
        if ($newModule -and ($($newModule.Version) -ne $moduleVersionString)) {
            Write-Host "PowerShell Core $moduleName module $moduleVersionString is out of date. Updating $moduleName module to $($newModule.Version)..."
            if ($allowPrerelease) {
                Update-Module $moduleName -AcceptLicense -Force -RequiredVersion ${newModule.Version} -AllowPrerelease -Scope $scope
            } else {
                Update-Module $moduleName -AcceptLicense -Force -RequiredVersion ${newModule.Version} -Scope $scope
            }
        } else {
            Write-Host "PowerShell Core $moduleName module $moduleVersionString is up to date"
        }
    } else {
        # Install module if not present
        if ($desiredVersion) {
            $newModule = Find-Module $moduleName -RequiredVersion $desiredVersion -AllowPrerelease -ErrorAction SilentlyContinue
            if ($newModule) {
                Write-Host "Installing PowerShell Core $moduleName module $desiredVersion..."
                Install-Module $moduleName -Force -SkipPublisherCheck -AcceptLicense -RequiredVersion $desiredVersion -AllowPrerelease -Scope $scope
            } else {
                Write-Host "PowerShell Core $moduleName module version $desiredVersion is not available on $($PSVersionTable.OS)" -ForegroundColor Red
            }
        } else {
            Write-Host "Installing PowerShell Core $moduleName module..."
            Install-Module $moduleName -Force -SkipPublisherCheck -AcceptLicense -Scope $scope
        }
    }
}

function global:IsElevated {
	if ($IsWindows -and (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
        return $true
    }
    
    if ($PSVersionTable.Platform -eq 'Unix') {
        if ((id -u) -eq 0) {
            return $true
        }
    }

    return $false
}

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
$psCoreProfileDirectory = Split-Path -Parent $PROFILE
$targetProfile = $($profile.CurrentUserAllHosts)
if (Test-Path $targetProfile) {
    Write-Host "Powershell Core profile $targetProfile already exists"
} else {
    if (!(Test-Path $psCoreProfileDirectory)) {
        Write-Host "Creating profile directory $psCoreProfileDirectory"
        $null = New-Item -ItemType Directory -Path $psCoreProfileDirectory -Force
    }

    $psProfileJunctionTarget = $(Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "profile.ps1")
    Write-Host "Creating symbolic link from $targetProfile to $psProfileJunctionTarget"
    $null = New-Item -ItemType symboliclink -path "$targetProfile" -value "$psProfileJunctionTarget"
}

# Non-pwsh common tasks
if (Get-Command az -ErrorAction SilentlyContinue) {
    Write-Host "`nUpdating az-cli extensions"
    az extension add --name azure-devops
}