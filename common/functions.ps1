
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

function Connect-TmuxSession (
    [string]$Workspace
) {
    if (!$Workspace -and (Get-Command terraform)) {
        $Workspace = $(terraform workspace show)
    }

    $prexistingSession = $(tmux ls -F "#S") -match "^${Workspace}$"
    if ($prexistingSession) {
        tmux attach-session -d -t $Workspace
    } else {
        tmux new -s $Workspace
    }

}
Set-Alias ct Connect-TmuxSession

function End-TmuxSession (
    [string]$Workspace
) {
    if ($Workspace) {
        tmux kill-session -t $Workspace
    } else {
        pkill -f tmux
    }
}
Set-Alias et End-TmuxSession

function Disable-Warning {
	Disable-Information

	$global:WarningPreference = "SilentlyContinue"
	Write-Host `$WarningPreference = $global:WarningPreference
}
Set-Alias warning- Disable-Warning

function Disable-Information {
	Disable-Verbose

	$global:InformationPreference = "SilentlyContinue"
	Write-Host `$InformationPreference = $global:InformationPreference
}
Set-Alias information- Disable-Information

function Disable-Verbose {
	Disable-Debug

	$global:VerbosePreference = "SilentlyContinue"
	Write-Host `$VerbosePreference = $global:VerbosePreference
}
Set-Alias verbose- Disable-Verbose

function Disable-Debug {
	$global:DebugPreference = "SilentlyContinue"
	Write-Host `$DebugPreference = $global:DebugPreference
}
Set-Alias debug- Disable-Debug

function  Enable-Warning {
	$global:ErrorPreference = "Continue"
	Write-Host `$ErrorPreference = $global:ErrorPreference
	$global:WarningPreference = "Continue"
	Write-Host `$WarningPreference = $global:WarningPreference
	Write-Warning "Warning tracing enabled"
}
Set-Alias warning Enable-Warning

function  Enable-Information {
	Enable-Warning

	$global:InformationPreference = "Continue"
	Write-Host `$InformationPreference = $global:InformationPreference
	Write-Information "Information tracing enabled"
}
Set-Alias information Enable-Information

function  Enable-Verbose {
	Enable-Information

	$global:VerbosePreference = "Continue"
	Write-Host `$VerbosePreference = $global:VerbosePreference
	Write-Verbose "Verbose tracing enabled"
}
Set-Alias verbose Enable-Verbose

function  Enable-Debug {
	Enable-Verbose
	
	$global:DebugPreference = "Continue"
	Write-Host `$DebugPreference = $global:DebugPreference
	Write-Debug "Debug tracing enabled"
}
Set-Alias debug Enable-Debug

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

function CopyFile (
    [string]$File,
    [string]$SourceDirectory,
    [string]$TargetDirectory
) {
    $target = $(Join-Path $TargetDirectory $File)
    $source = $(Join-Path $SourceDirectory $File)

    Write-Information "Copying $source => $target"
    $item = Copy-Item -LiteralPath $source -Destination $target -Force -PassThru
    Write-Host "$($item.FullName) <= $source"
} 
function LinkFile (
    [string]$File,
    [string]$SourceDirectory,
    [string]$TargetDirectory
) {
    $linkSource = $(Join-Path $TargetDirectory $File)
    $linkTarget = $(Join-Path $SourceDirectory $File)

    if (!(Test-Path $linkSource)) {
        Write-Information "Creating symbolic link $linkSource -> $linkTarget"
        $link = New-Item -ItemType symboliclink -path "$linkSource" -value "$linkTarget"
    } else {
        $link = Get-Item $linkSource -Force
    }
    if ($link.Target) {
        Write-Host "$($link.FullName) -> $($link.Target)"
    } else {
        Write-Information "$($link.FullName) already exists as file"
    }
} 