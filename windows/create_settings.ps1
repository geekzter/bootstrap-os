<#
.SYNOPSIS 
    Creates links to various settings files in windows\settings 

.DESCRIPTION 
    Some applications (e.g. Windows Terminal) store their settings in a text file.
    This script create symbolic links for those files to files contained in the repository at windows\settings\<application>
#>

function LinkFileToHome (
    [string]$File,
    [string]$SettingsDirectory,
    [string]$AppDataDirectory,
    [switch]$Overwrite=$false
) {
    $linkSource = $(Join-Path $AppDataDirectory $File)
    $linkTarget = $(Join-Path $SettingsDirectory $File)

    if ($Overwrite -or !(Test-Path $linkSource)) {
        Write-Information "Creating symbolic link $linkSource -> $linkTarget"
        $link = New-Item -ItemType symboliclink -path "$linkSource" -value "$linkTarget" -Force
    } else {
        $link = Get-Item $linkSource -Force
    }
    if ($link.Target) {
        Write-Host "$($link.FullName) -> $($link.Target)"
    } else {
        Write-Host "$($link.FullName) already exists as file" -ForegroundColor Yellow

        # Prompt to overwrite
        Write-Host "Do you want to replace file ${linkSource} with a link to ${linkTarget}? , please reply 'yes' - null or N aborts" -ForegroundColor Cyan
        $proceedanswer = Read-Host 

        if ($proceedanswer -eq "yes") {
            # Recurse with 'Force' option
            LinkFileToHome -File $File -SettingsDirectory $SettingsDirectory -AppDataDirectory $AppDataDirectory -Overwrite
        } else {
            Write-Host "Reply is not 'yes' - leaving file ${linkSource} untouched" -ForegroundColor Yellow
        }
    }
} 

if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
    Write-Warning "Can't create symbolic links when not running as administrator, exiting $($MyInvocation.MyCommand.Path)"
    exit
}

$settingsDirectory = $(Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "settings")

LinkFileToHome -File profiles.json -SettingsDirectory $settingsDirectory\windowsterminal -AppDataDirectory $env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState

