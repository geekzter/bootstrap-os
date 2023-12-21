param ( 
    [parameter(Mandatory=$false)][switch]$Force=$false
) 

# Validation
if ($PSVersionTable.PSEdition -eq "Core") {
    if (!$IsWindows) {
        Write-Output "Not running on Windows"
        exit
    }

    [System.Version]$windows11AndUp = "10.0.22000"
    [System.Version]$currentVersion = (Get-ComputerInfo).OsVersion
    if ($currentVersion -lt $windows11AndUp) {
        # Windows 10 and below needs Windows PowerShell
        Write-Output "Not running on Windows PowerShell"
        exit    
    }
}    
if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
    Write-Warning "Not running as Administrator"
}
if (!(Get-Command Add-AppxPackage -ErrorAction SilentlyContinue)) {
    Write-Warning "Install the App Installer before running this script: https://apps.microsoft.com/detail/9NBLGGH4NNS1"
    exit 1
}
if (!(Get-AppxPackage -Name Microsoft.DesktopAppInstaller)) {
    # Register winget
    Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe
}
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Warning "Winget failed to install. Get it at https://github.com/microsoft/winget-cli"
    exit 1
}

$wingetConfig = (Join-Path $PSScriptRoot configuration.dsc.yaml)
Write-Host "Applying winget configuration '${wingetConfig}'..."
if ($Force) {
    # $wingetArgs = "--accept-configuration-agreements --disable-interactivity"
    $wingetArgs = "--accept-configuration-agreements"
    # $wingetArgs = "--disable-interactivity "
}
winget configure -f $wingetConfig $wingetArgs


