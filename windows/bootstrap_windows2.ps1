# No shebang, as Windows only
<#
    Post-git bootstrap stage
#>
param ( 
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][ValidateSet("Desktop", "Developer", "Minimal", "None")][string[]]$Packages=@("Minimal"),
    [parameter(Mandatory=$false)][bool]$PowerShell=$false,
    [parameter(Mandatory=$false)][bool]$Settings=$true
) 

function global:AddorUpdateModule (
    [string]$ModuleName,
    [switch]$AllowClobber=$false
) {
    if (IsElevated) {
        $scope = "AllUsers"
    } else {
        $scope = "CurrentUser"
    }
    if (Get-InstalledModule $moduleName -ErrorAction SilentlyContinue) {
        $azModuleVersionString = Get-InstalledModule $moduleName | Sort-Object -Descending Version | Select-Object -First 1 -ExpandProperty Version
        $azModuleVersion = New-Object System.Version($azModuleVersionString)
        $azModuleUpdateVersionString = "{0}.{1}.{2}" -f $azModuleVersion.Major, $azModuleVersion.Minor, ($azModuleVersion.Build + 1)
        # Check whether newer module exists
        if (Find-Module $moduleName -MinimumVersion $azModuleUpdateVersionString -ErrorAction SilentlyContinue) {
            Write-Host "Windows PowerShell $moduleName module $azModuleVersionString is out of date. Updating $moduleName module..."
            Update-Module $moduleName -Force -Scope $scope #-AcceptLicense
        } else {
            Write-Host "Windows PowerShell $moduleName module $azModuleVersionString is up to date"
        }
    } else {
        # Install module if not present
        Write-Host "Installing Windows PowerShell $moduleName module..."
        Install-Module $moduleName -Force -SkipPublisherCheck -Scope $scope -AllowClobber:$AllowClobber # -AcceptLicense 
    }
}

function global:FindApplication (
    [string]$Application
) {
    if ($Application) {
        $userStartFolder = (Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name "Start Menu" | Select-Object -ExpandProperty "Start Menu")
        $commonStartFolder = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name "Common Start Menu" | Select-Object -ExpandProperty "Common Start Menu")

        $shortcut = Get-ChildItem -Path $userStartFolder,$commonStartFolder -File -Filter $Application -Recurse -Depth 5 | Select-Object -First 1
        return $shortcut
    }
}

function global:PinToQuickAccess (
    [string]$Folder
) {
    if ($Folder -and (Test-Path $Folder)) {
        $shell = New-Object -com Shell.Application
        $folderObject = $shell.Namespace($Folder)
        if ($folderObject) {
            $folderObject.Self.InvokeVerb("pintohome")
        }
    }
}

function global:PinTo (
    [string]$Application,
    [switch]$StartMenu=$falase,
    [switch]$Taskbar=$false
) {
    if ($Application -and (Get-Command syspin -ErrorAction SilentlyContinue)) {
        $shortcut = FindApplication $Application

        if ($shortcut) {
            if ($StartMenu) {
                syspin $shortcut.FullName "Pin to start"
            }
            if ($TaskBar) {
                syspin $shortcut.FullName "Pin to taskbar"
            }
        }
    }
}

function global:RemoveFromTaskbar (
    [string]$Shortcut
) {
    if ($Shortcut -and (Get-Command syspin -ErrorAction SilentlyContinue)) {
        syspin $Shortcut "Unpin from taskbar"
    }
}

function global:IsElevated {
    return (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")
}

function global:UpdateStoreApps () {
    $namespaceName = "root\cimv2\mdm\dmmap"
    $className = "MDM_EnterpriseModernAppManagement_AppManagement01"
    $wmiObj = Get-WmiObject -Namespace $namespaceName -Class $className
    Write-Host "Updating Windows store apps using WMI class $($wmiObj.__CLASS)..."
    $null = $wmiObj.UpdateScanMethod()
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
} catch {
    # No metadata endpoint available, i.e. not running in the cloud
    $metadataContent = $null
}

$minimal = ($Packages.Contains("Desktop") -or $Packages.Contains("Developer") -or $Packages.Contains("Minimal"))
if ($All -or $minimal) {
    # Install Chocolatey packages

    # Always setup Minimal set of packages
    choco install chocolatey-minimal.config -r -y
    choco install chocolatey-windows-developer.config -r -y -s windowsfeatures
 
    if (($All -and $osType -ieq "Client") -or $Packages.Contains("Desktop")) {
        choco install chocolatey-desktop.config -r -y

        # Windows capabilities
        $capabilities  = Get-WindowsCapability -Online -Name "Language.*en-US*" | Where-Object {$_.State -ne "Installed"}
        $capabilities += Get-WindowsCapability -Online -Name "Language.*nl-NL*" | Where-Object {$_.State -ne "Installed"}
        $capabilities += Get-WindowsCapability -Online -Name OpenSSH.Client     | Where-Object {$_.State -ne "Installed"}
        foreach ($capability in $capabilities) {
            if ($capability -and $capability.Name) {
                Write-Host "Installing Windows Capability '$($capability.DisplayName)'..."
                $capability | Add-WindowsCapability -Online
            }
        }

        # Store
        Get-AppxPackage -AllUsers "Microsoft.DesktopAppInstaller" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.Services.Store.Engagement" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.StorePurchaseApp" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.WindowsStore" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
    
        # Store Apps
        Get-AppxPackage -AllUsers "Microsoft.MicrosoftOfficeHub" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.MicrosoftPowerBIForWindows" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.MSPaint" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.NetworkSpeedTest" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.OfficeLens" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.Office.OneNote" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.Office.Sway" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.RemoteDesktop" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        Get-AppxPackage -AllUsers "Microsoft.Whiteboard" | ForEach-Object {Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml"}
        
        UpdateStoreApps
    }

    if ($All -or $Packages.Contains("Developer")) {
        choco install chocolatey-developer.config -r -y

        PinToQuickAccess "$env:HOME\Source"
        PinTo -Application "Visual Studio Code.lnk" -StartMenu -Taskbar 
        PinTo -Application "Windows PowerShell.lnk" -StartMenu
        PinTo -Application "Windows Terminal*" -StartMenu -Taskbar

        # Enable long paths
        Set-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Type DWord -Value 1 
    }

    choco upgrade all -r -y 
    if (Get-Command refreshenv -ErrorAction SilentlyContinue) {
        refreshenv # This should update the path with changes made by Chocolatey
    }

    PinTo -Application "Microsoft Edge*" -Taskbar 

    # Replace IE
    $defaultBrowser = "Microsoft Edge"
    $edge = Get-ItemProperty -Path "HKCU:\SOFTWARE\Clients\StartMenuInternet\$defaultBrowser" -ErrorAction SilentlyContinue
    if ($edge) {
        Write-Host "Setting '$defaultBrowser' as default browser"
        Set-Item -Path "HKCU:\SOFTWARE\Clients\StartMenuInternet" -Value $defaultBrowser
        $removeIE = $true
    }
    $edge = Get-ItemProperty -Path "HKLM:\SOFTWARE\Clients\StartMenuInternet\$defaultBrowser" -ErrorAction SilentlyContinue
    if ($edge) {
        Write-Host "Setting '$defaultBrowser' as default browser"
        Set-Item -Path "HKLM:\SOFTWARE\Clients\StartMenuInternet" -Value $defaultBrowser
        $removeIE = $true
    }
    if ($removeIE) {
        Write-Host "Removing 'Internet Explorer'..."
        # Taken from https://github.com/Disassembler0
        Get-WindowsOptionalFeature -Online | Where-Object { $_.FeatureName -like "Internet-Explorer-Optional*" } | Disable-WindowsOptionalFeature -Online -NoRestart -WarningAction SilentlyContinue | Out-Null
        Get-WindowsCapability -Online | Where-Object { $_.Name -like "Browser.InternetExplorer*" } | Remove-WindowsCapability -Online | Out-Null
    }

    # Move shortcuts of installed applications
    Invoke-Command -ScriptBlock {
        $private:ErrorActionPreference = "SilentlyContinue"
        $script:desktopFolder = Get-ItemPropertyValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name "Desktop" -ErrorAction SilentlyContinue  
    }
    # $desktopFolder may be emoty when executing before first logon
    if ($desktopFolder) {
        $allUsersDesktopFolder = Get-ItemPropertyValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders" -Name "common Desktop"    
        $installedAppsFolder = Join-Path $desktopFolder "Installed"
        if (!(Test-Path $installedAppsFolder)) {
            $null = mkdir $installedAppsFolder
        }
        Get-ChildItem -Path $desktopFolder -Filter *.lnk | Where-Object {$_.LastWriteTime -ge $startTime} | Move-Item -Destination $installedAppsFolder -Force
        Get-ChildItem -Path $allUsersDesktopFolder -Filter *.lnk | Where-Object {$_.LastWriteTime -ge $startTime} | Move-Item -Destination $installedAppsFolder -Force
        if (!(Get-ChildItem -Path $installedAppsFolder)) {
            Remove-Item -Path $installedAppsFolder
        }
    }
} else {
    if ($Powershell) {
        choco install powershell-core -y
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
    Get-ScheduledTask -TaskName ServerManager -ErrorAction SilentlyContinue | Disable-ScheduledTask | Out-Null
    Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name "Docker Desktop" -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path HKCU:\Software\Microsoft\Windows\CurrentVersion\Run -Name "KeePassXC" -ErrorAction SilentlyContinue

    # Show hidden files
    Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "Hidden" -Type DWord -Value 1

    # Display Setting customization
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value 0 -ErrorAction SilentlyContinue
    New-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name IconSpacing -PropertyType String -Value -2730 -ErrorAction SilentlyContinue
    Set-ItemProperty -Path "HKCU:\Control Panel\Desktop\WindowMetrics" -Name IconSpacing -Value -2730 -ErrorAction SilentlyContinue
    if ($metadataContent) {
        # Cloud hosted, so no wallpapers
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper" ""
        Set-ItemProperty -Path "HKCU:\Control Panel\Colors" -Name "Background" "45 125 154"
        
        New-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name DisableLogonBackgroundImage -PropertyType DWord -Value 1 -ErrorAction SilentlyContinue

        $bgInfoCommand = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "BGInfo" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty "BGInfo"
        if ($bgInfoCommand) {
            $bgInfoExe = ($bgInfoCommand -replace "BGInfo.exe.*$","BGInfo.exe")
        } else {
            # Configure BGInfo of not already done so (e.g. by VM extension)
            $bgInfoExe = Get-Command "bginfo.exe" -ErrorAction SilentlyContinue
            if ($bgInfoExe) {
                $bgInfoPath = $bgInfoExe.Source
                $bgInfoConfig = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "config.bgi"
                $bgInfoCommand = "$bgInfoPath $bgInfoConfig /NOLICPROMPT /timer:0"
                Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -Name "BGInfo" $bgInfoCommand
            }
        }

        # Configure DPI scaling for BGInfo
        if ($bgInfoExe) {
            New-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" -Name $bgInfoExe -PropertyType String -Value "^ DPIUNAWARE" -ErrorAction SilentlyContinue
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers" -Name $bgInfoExe -Value  "^ DPIUNAWARE" -ErrorAction SilentlyContinue
        }

        if ($bgInfoCommand) {
            # Execute BGInfo regardless, as we just have removed the wallpaper
            Invoke-Expression $bgInfoCommand

            # Schedule task to be run whenever user connects via RDP
            schtasks.exe /create /f /rl HIGHEST /tn "BGInfo" /tr "$bgInfoCommand" /SC ONEVENT /EC Security /MO "*[System[Provider[@Name='Microsoft-Windows-Security-Auditing'] and EventID=4672]]"
        }

        # Install Apple US International keyboard layout
        if ((Get-ChildItem -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layouts" | Get-ItemProperty | Select-Object -ExpandProperty "Layout File") -inotcontains "USIAPPLE.dll") {
            $keyboardLayountResponse = (Invoke-RestMethod -Uri https://api.github.com/repos/geekzter/mac-us-international-keyboard-windows/releases/latest)
            if ($keyboardLayountResponse.assets.browser_download_url) {
                Invoke-Webrequest -Uri $keyboardLayountResponse.assets.browser_download_url -OutFile ~\Downloads\keyboardLayout.zip -UseBasicParsing 
                New-Item -ItemType Directory -Path (Join-Path $([System.IO.Path]::GetTempPath()) $([System.Guid]::NewGuid())) | Select-Object -ExpandProperty FullName | Set-Variable keyboardExtractDirectory
                Expand-Archive -Path ~\Downloads\keyboardLayout.zip -DestinationPath $keyboardExtractDirectory
                $keyboardSetupDirectory = Join-Path $keyboardExtractDirectory $($keyboardLayountResponse.assets.name -replace ".zip","")
                Invoke-Item $keyboardSetupDirectory\setup.exe
            }
        }
    }

    # Set up application settings
    & (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "create_settings.ps1")

    # Set UAC for Desktop OS
    if ($osType -ieq "Client") {
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ConsentPromptBehaviorAdmin" -Type DWord -Value 5
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "FilterAdministratorToken" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "EnableLUA" -Type DWord -Value 1
        Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name "PromptOnSecureDesktop" -Type DWord -Value 1   
    }

    # Import GPO
    if ($All -or $Packages.Contains("Developer")) {
        if (!(Get-Command lgpo -ErrorAction SilentlyContinue)) {
            $gpoDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) "data\gpo")
            $null = New-Item -ItemType Directory -Force -Path $gpoDirectory 
            $lgpoExeDirectory = (Join-Path $gpoDirectory "LGPO_30")
            if (!(Test-Path $lgpoExeDirectory)) {
                Write-Warning "LGPO not found"
                $lgoArchive = (Join-Path $gpoDirectory "lgpo.zip")
                $lgpoUrl = 'https://download.microsoft.com/download/8/5/C/85C25433-A1B0-4FFA-9429-7E023E7DA8D8/LGPO.zip'
                Write-Host "Retrieving lgpo from ${lgpoUrl}..."
                Invoke-WebRequest -Uri $lgpoUrl -UseBasicParsing -OutFile $lgoArchive
                Write-Host "Extracting ${lgoArchive} in ${$gpoDirectory}..."
                Expand-Archive -Path $lgoArchive -DestinationPath $gpoDirectory -Force
                Write-Host "Extracted ${lgoArchive}"
            }
            $env:PATH += ";${lgpoExeDirectory}"
        }
        if (Get-Command lgpo -ErrorAction SilentlyContinue) {
            foreach ($policyScope in @("user","machine")) {
                $policyText = (Join-Path $PSScriptRoot "${policyScope}-policy.txt")
                if (Test-Path $policyText) {
                    Write-Host "Importing policy text file ${policyText}..."
                    lgpo /t $policyText /v
                    if ($policyScope -eq "user") {
                        $policyTarget = "User"
                    } else {
                        $policyTarget = "Computer"
                    }
                    gpupdate /Target:${policyTarget} /Force
                } else {
                    Write-Warning "Policy text file ${policyText} not found, skipping import"
                }
            }
        } else {
            Write-Warning "LGPO not found. Please install by running 'choco install winsecuritybaseline' from an elevated shell, or downloading and installing it from https://www.microsoft.com/en-us/download/details.aspx?id=55319"
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
        $null = New-Item -ItemType symboliclink -path "$windowsPowerShellFolder" -value "$windowsPowerShellJunctionTarget"
    }

    # Windows PowerShell modules
    Write-Host "Installing NuGet package provider..."
    $null = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ForceBootstrap
    AddorUpdateModule PowerShellGet  
    #AddorUpdateModule Az
    AddorUpdateModule AzureAD
    #AddorUpdateModule AzureADPreview
    #AddorUpdateModule AzureRM
    #AddorUpdateModule MicrosoftPowerBIMgmt
    #AddorUpdateModule MicrosoftTeams
    #AddorUpdateModule MSOnline
    AddorUpdateModule Posh-Git
    #AddorUpdateModule SqlServer
    #AddorUpdateModule VSTeam

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
    $psCoreSetupScript = $(Join-Path (Get-Item (Split-Path -parent -Path $MyInvocation.MyCommand.Path)).Parent.FullName "common\common_setup.ps1")
    pwsh.exe -nop -File $psCoreSetupScript
}
