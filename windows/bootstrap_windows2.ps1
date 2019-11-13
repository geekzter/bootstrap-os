# No shebang, as Windows only
<#
    Post-git bootstrap stage
#>
param ( 
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][switch]$Packages=$false,
    [parameter(Mandatory=$false)][switch]$PowerShell=$false,
    [parameter(Mandatory=$false)][switch]$Settings=$false
) 

function AddorUpdateModule (
    [string]$moduleName
) {
    if (Get-InstalledModule $moduleName -ErrorAction SilentlyContinue) {
        $azModuleVersionString = Get-InstalledModule $moduleName | Sort-Object -Descending Version | Select-Object -First 1 -ExpandProperty Version
        $azModuleVersion = New-Object System.Version($azModuleVersionString)
        $azModuleUpdateVersionString = "{0}.{1}.{2}" -f $azModuleVersion.Major, $azModuleVersion.Minor, ($azModuleVersion.Build + 1)
        # Check whether newer module exists
        if (Find-Module $moduleName -MinimumVersion $azModuleUpdateVersionString -ErrorAction SilentlyContinue) {
            Write-Host "Windows PowerShell $moduleName module $azModuleVersionString is out of date. Updating $moduleName module..."
            Update-Module $moduleName -Force #-AcceptLicense
        } else {
            Write-Host "Windows PowerShell $moduleName module $azModuleVersionString is up to date"
        }
    } else {
        # Install module if not present
        Write-Host "Installing Windows PowerShell $moduleName module..."
        Install-Module $moduleName -Force -SkipPublisherCheck # -AcceptLicense 
    }
}

function UpdateStoreApps () {
    $namespaceName = "root\cimv2\mdm\dmmap"
    $className = "MDM_EnterpriseModernAppManagement_AppManagement01"
    $wmiObj = Get-WmiObject -Namespace $namespaceName -Class $className
    $wmiObj.UpdateScanMethod()
}

# Script should be called from stage 1 script
$stage1Script = "bootstrap_windows.ps1"
if ((Get-PSCallStack | Select-Object -Skip 1 -First 1 -ExpandProperty Command) -ne $stage1Script) {
    Write-Host "This script shouldn't be invoked directly, please execute $stage1Script instead."
    #exit
}

$startTime = Get-Date

$osType = Get-ComputerInfo | Select-Object WindowsInstallationType -ExpandProperty WindowsInstallationType
Write-Host "OS Type: $osType"
try {
    $metadataContent = Invoke-WebRequest -Headers @{"Metadata"='true'} -Uri http://169.254.169.254/metadata/instance?api-version=2017-04-02 -UseBasicParsing -TimeOutSec 1 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Content
} catch [System.Net.WebException],[System.IO.IOException] {
    # No metadata endpoint available, i.e. not running in the cloud
    $metadataContent = $null
}

if ($All -or $Packages) {
    # Install Chocolatey packages
    choco install chocolatey-developer.config -r -y
    if ($metadataContent) {
        if ($osType -ieq "Client") {
            # Cloud hosted Client OS, install desktop (productivity) apps
            choco install chocolatey-desktop.config -r -y
        } else {
            Write-Host "Not a client OS, skipping desktop config"
        }
    } else {
        Write-Host "Not a cloud hosted computer, skipping desktop config"
    }

    choco upgrade all -r -y 
    refreshenv # This should update the path with changes made by Chocolatey

    # Move shortcuts of installed applications
    $desktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name "Desktop"    
    $allUsersDesktopFolder = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name "common Desktop"    
    $installedAppsFolder = Join-Path $desktopFolder "Installed"
    if (!(Test-Path $installedAppsFolder)) {
        mkdir $installedAppsFolder
    }
    Get-ChildItem -Path $desktopFolder -Filter *.lnk | Where-Object {$_.LastWriteTime -ge $startTime} | Move-Item -Destination $installedAppsFolder
    Get-ChildItem -Path $allUsersDesktopFolder -Filter *.lnk | Where-Object {$_.LastWriteTime -ge $startTime} | Move-Item -Destination $installedAppsFolder
    if (!(Get-ChildItem -Path $installedAppsFolder)) {
        Remove-Item -Path $installedAppsFolder
    }
}

if ($All -or $Settings) {
    $settingsFile = Join-Path (Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)) "common\settings.json"
    if (Test-Path $settingsFile) {
        $config = Get-Content $settingsFile | ConvertFrom-Json

        # Git
        if ($config.GitEmail) {
            git config --global user.email $config.GitEmail
        }
        if ($config.GitName) {
            git config --global user.name $config.GitName
        }

        # Regional settings
        if ($config.TimeZone) {
            tzutil /s $config.TimeZone
        }
        if ($config.UserCulture) {
            Set-Culture $config.UserCulture
        }
        if ($config.UserGeoID) {
            Set-WinHomeLocation $config.UserGeoID
        }
        if ($config.UserLanguage) {
            Set-WinUserLanguageList $config.UserLanguage -Force
        }
    } else {
        Write-Host "Settings file $settingsFile not found, skipping personalization"
    }

    # Disable autostarts
    Get-ScheduledTask -TaskName ServerManager -ErrorAction SilentlyContinue | Disable-ScheduledTask
    Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name "Docker Desktop" -ErrorAction SilentlyContinue

    # Display Setting customization
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name IconSpacing -PropertyType String -Value -1125 -ErrorAction SilentlyContinue
    if ($metadataContent) {
        # Cloud hosted, so no wallpapers
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" ""
        Set-ItemProperty -Path "HKCU:\Control Panel\Colors" -Name "Background" "45 125 154"
        
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DisableLogonBackgroundImage -PropertyType DWord -Value 1 -ErrorAction SilentlyContinue

        $bgInfoCommand = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "BGInfo" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "BGInfo"
        if (!($bgInfoCommand)) {
            # Configure BGInfo of not already done so (e.g. by VM extension)
            $bgInfoExe = Get-command "bginfo.exe"
            if ($bgInfoExe) {
                $bgInfoPath = $bgInfoExe.Source
                $bgInfoConfig = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "config.bgi"
                $bgInfoCommand = "$bgInfoPath $bgInfoConfig /NOLICPROMPT /timer:0"
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "BGInfo" $bgInfoCommand
            }
        }
        # Execute BGInfo regardless, as we just removed the wallpaper
        if ($bgInfoCommand) {
            Invoke-Expression $bgInfoCommand
        }
    }
}

if ($All -or $Powershell) {
    # Create directory junction for Windows PowerShell profile directory
    $documentsFolder = Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders" | Select-Object -ExpandProperty Personal
    $windowsPowerShellFolder = Join-Path $documentsFolder "WindowsPowershell"
    #$windowsPowerShellFolder = Split-Path -parent $PROFILE # Doesn't work if run from PowerShell Core
    if (Test-Path $windowsPowerShellFolder) {
        if (Get-ChildItem -Path $windowsPowerShellFolder) {
            Write-Host "Windows Powershell profile directory $windowsPowerShellFolder already exists"
        } else {
            # Remove Windows PowerShell folder if it doesn't contain anything, so we can create a symbolic link later
            Remove-Item -Path $windowsPowerShellFolder
        }
    }
    if (!(Test-Path $windowsPowerShellFolder)) {
        $windowsPowerShellJunctionTarget = $(Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "WindowsPowerShell")
        Write-Host "Creating symbolic link from $windowsPowerShellFolder to $windowsPowerShellJunctionTarget"
        New-Item -ItemType symboliclink -path "$windowsPowerShellFolder" -value "$windowsPowerShellJunctionTarget"
    }

    # Windows PowerShell modules
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap
    AddorUpdateModule PowerShellGet  
    AddorUpdateModule AzureAD
    #AddorUpdateModule AzureADPreview
    AddorUpdateModule AzureRM
    AddorUpdateModule MSOnline
    AddorUpdateModule SqlServer
    UpdateStoreApps

    # Find PowerShell Core
    if (!(Get-Command "pwsh.exe" -ErrorAction SilentlyContinue)) {
        # PowerShell Core is not in the path (yet)
        $psCoreExec = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\pwsh.exe" -Name "(default)" -ErrorAction SilentlyContinue
        if ($psCoreExec) {
            $psCorePath = Split-Path -Parent $psCoreExec
            $env:Path += ";$psCorePath"
        } else {
            Write-Error "PowerShell Core pwsh.exe not found"
        }
    }
 
    # Let PowerShell Core configure itself
    $psCoreSetupScript = $(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "common\bootstrap_pwsh.ps1")
    pwsh.exe -nop -File $psCoreSetupScript
}
