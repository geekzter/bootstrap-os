function AddorUpdateModule (
    [parameter(Mandatory=$true)][string]$ModuleName,
    [parameter(Mandatory=$false)][string]$DesiredVersion,
    [parameter(Mandatory=$false)][switch]$AllowClobber=$false
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
                Install-Module $moduleName -Force -SkipPublisherCheck -AcceptLicense -RequiredVersion $desiredVersion -AllowPrerelease -Scope $scope -AllowClobber:$AllowClobber
            } else {
                Write-Host "PowerShell Core $moduleName module version $desiredVersion is not available on $($PSVersionTable.OS)" -ForegroundColor Red
            }
        } else {
            Write-Host "Installing PowerShell Core $moduleName module..."
            Install-Module $moduleName -Force -SkipPublisherCheck -AcceptLicense -Scope $scope -AllowClobber:$AllowClobber
        }
    }
}

function Clone-GitHubRepositories (
    [parameter(Mandatory=$false)][string]$User
) {
    if (!(Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning "git not found, no repositories to clone"
        return
    }
    if (!$User) {
        $gitUser = ((git config --get remote.origin.url) -replace '^https://(?<host>[\w\.]+)/(?<user>\w+)/([\w\-]+)(\.git)?$' , '${user}')
        if ($gitUser) {
            $User = $gitUser
        } else {
            Write-Warning "Unable to determine GitHub user name"
            return
        }
    }
    # Set repo root
    if ($IsWindows) {
        $repoRoot = "~\Source\GitHub\${User}"
    } else {
        $repoRoot = "~/src/github/${User}"
    }
    $repoRoot = (Resolve-Path $repoRoot).Path
    New-Item -ItemType Directory -Force -Path $repoRoot | Out-Null
    Push-Location $repoRoot

    # Retrieve repositories for user
    Write-Host "Looking for GitHub repositories for user '${User}'..."
    Invoke-RestMethod https://api.github.com/users/${User}/repos | Set-Variable repos

    # Clone repositories
    $printMessage = $true
    foreach ($repo in $repos) {
        Join-Path $repoRoot $repo.name | Set-Variable repoDirectory
        if (Test-Path $repoDirectory) {
            Write-Verbose "Repo '$($repo.html_url)' already exists locally in '$repoDirectory'"
        } else {
            if ($printMessage) {
                Write-Host "Cloning GitHub repositories for user '${User}' into '$repoRoot'..."
                $printMessage = $false
            }
            Write-Host "Cloning '$($repo.html_url)' into '$repoDirectory'"
            git clone https://github.com/${User}/$($repo.name)
        }
    }
    if ($printMessage) {
        Write-Host "Nothing (more) to clone for user '${User}'"
    }
    Invoke-Item $repoRoot
}

function Import-InstalledModule (
    [parameter(Mandatory=$true)][string]$ModuleName
) {
    if (Get-Module $ModuleName -ErrorAction SilentlyContinue) {
        Write-Verbose "module ${ModuleName} already imported"
    } else {
        Write-Verbose "Getting module ${ModuleName} installation status..."
        # if (Get-InstalledModule $ModuleName -ErrorAction SilentlyContinue) {
        if (Get-Module -ListAvailable -Name $ModuleName) {
            Write-Verbose "Importing module ${ModuleName}..."
            Import-Module $ModuleName
        }
    }
}

function ChangeTo-Directory (
    [parameter(Mandatory=$true)][string]$Directory   
) {
    if (Test-Path $Directory) {
        Push-Location $Directory
    } else {
        $sibling = (Join-Path .. $Directory)
        if (Test-Path $sibling) {
            Push-Location $sibling
        }
    }
}

function ChangeTo-GitHubRepositoryRoot () {
    $startLocation = (Get-Location).Path

    if (Test-Path ~/src/github) {
        Push-Location "~/src/github"
    }
    if (Test-Path ~/source/github) {
        Push-Location "~/source/github"
    }

    if ((Get-Location).Path -ieq $startLocation) {
        Write-Warning "GitHUb repos root directory not found"
    }
}
Set-Alias cdgh ChangeTo-GitHubRepositoryRoot

function ChangeTo-GoogleDrive () {
    if (!$IsMacOS) {
        Write-Warning "Not yet implemented for not available on $($PSVersionTable.OS)"
        return
    }
    $startLocation = (Get-Location).Path

    if (Test-Path "/Volumes/GoogleDrive") {
        Push-Location "/Volumes/GoogleDrive"
    }

    if ((Get-Location).Path -ieq $startLocation) {
        Write-Warning "Google Drive directory not found"
    }
}
Set-Alias cdg ChangeTo-GoogleDrive

function ChangeTo-GrandGrandParent {
    Push-Location (Join-Path .. .. ..)
}
Set-Alias .... ChangeTo-GrandGrandParent

function ChangeTo-GrandParent {
    Push-Location (Join-Path .. ..)
}
Set-Alias ... ChangeTo-GrandParent

function ChangeTo-iCloudDrive () {
    $startLocation = (Get-Location).Path

    if ($IsMacOS) {
        if (Test-Path "~/Library/Mobile Documents/com~apple~CloudDocs") {
            Push-Location "~/Library/Mobile Documents/com~apple~CloudDocs"
        }
    }
    if ($IsWindows) {
        if (Test-Path "$HOME\iCloudDrive") {
            Push-Location "$HOME\iCloudDrive"
        }
    }

    if ((Get-Location).Path -ieq $startLocation) {
        Write-Warning "iCloud Drive directory not found"
    }
}
Set-Alias cdi ChangeTo-iCloudDrive

function ChangeTo-OneDrive () {
    $startLocation = (Get-Location).Path

    if ($IsMacOS) {
        if (Test-Path ~/Library/CloudStorage/OneDrive) {
            Push-Location ~/Library/CloudStorage/OneDrive
        } if (Test-Path ~/Library/CloudStorage/OneDrive*) {
            Push-Location (Get-ChildItem ~/Library/CloudStorage -Filter OneDrive* -Directory | Select-Object -First 1)
        }
    }
    if ($IsWindows) {
        if ($env:OneDrive) {
            Push-Location "$env:OneDrive"
        }
    }

    if ((Get-Location).Path -ieq $startLocation) {
        Write-Warning "OneDrive directory not found"
    }
}
Set-Alias cdo ChangeTo-OneDrive

function ChangeTo-Previous {
    Pop-Location
}
Set-Alias cd- ChangeTo-Previous

function ChangeTo-Parent {
    Push-Location ..
}
Set-Alias .. ChangeTo-Parent

function ChangeTo-Scripts {
    ChangeTo-Directory scripts
}
Set-Alias cds ChangeTo-Scripts

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
	$global:ErrorActionPreference = "Continue"
	Write-Host `$ErrorActionPreference = $global:ErrorActionPreference
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

function global:CanElevate {
    if (IsElevated) {
        return $true
    }

	if ($IsWindows) {
        # Windows requires a new Administrative shell to be started
        return $false
    }
    
    if ($PSVersionTable.Platform -eq 'Unix') {
        if (Get-Command sudo -ErrorAction SilentlyContinue) {
            return $true
        }
    }

    return $false
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
function global:RunElevated () {
    $commandJoined = $args -join " " 
    Write-Debug "commandJoined: $commandJoined"
    if (IsElevated) {
        return Invoke-Expression $commandJoined
    } else {
        if ($IsWindows) {
            throw "Windows requires a new Administrative shell to be started, can't run '$commandJoined' elevated"
        }

        if ($PSVersionTable.Platform -eq 'Unix') {
            if (Get-Command sudo -ErrorAction SilentlyContinue) {
                return Invoke-Expression "sudo $commandJoined"
            } else {
                throw "sudo not found, can't run '$commandJoined' elevated"
            }
        }

        throw "Operating system not detected, can't run '$commandJoined' elevated"
    }
}

function CopyFile (
    [parameter(Mandatory=$true)][string]$File,
    [parameter(Mandatory=$true)][string]$SourceDirectory,
    [parameter(Mandatory=$true)][string]$TargetDirectory
) {
    $target = $(Join-Path $TargetDirectory $File)
    $source = $(Join-Path $SourceDirectory $File)

    Write-Information "Copying $source => $target"
    $item = Copy-Item -LiteralPath $source -Destination $target -Force -PassThru
    Write-Host "$($item.FullName) <= $source"
} 

function LinkDirectory (
    [parameter(Mandatory=$true)][string]$SourceDirectory,
    [parameter(Mandatory=$true)][string]$TargetDirectory
) {
    if (!(Test-Path $SourceDirectory)) {
        Write-Information "Creating symbolic link $SourceDirectory -> $TargetDirectory"
        $link = New-Item -ItemType symboliclink -path "$SourceDirectory" -value "$TargetDirectory"
    } else {
        $link = Get-Item $SourceDirectory -Force
    }
    if ($link.Target) {
        Write-Host "$($link.FullName) -> $($link.Target)"
    } else {
        Write-Warning "$($link.FullName) already exists as directory" 
    }
} 
function LinkFile (
    [parameter(Mandatory=$true)][string]$File,
    [parameter(Mandatory=$true)][string]$SourceDirectory,
    [parameter(Mandatory=$true)][string]$TargetDirectory,
    [parameter(Mandatory=$false)][switch]$ReplaceEmptyFile
) {
    # Reverse
    $linkSource = $(Join-Path $TargetDirectory $File)
    $linkTarget = $(Join-Path $SourceDirectory $File)

    if (!(Test-Path $linkSource)) {
        Write-Information "Creating symbolic link $linkSource -> $linkTarget"
        $link = New-Item -ItemType symboliclink -path "$linkSource" -value "$linkTarget"
    } else {
        $link = Get-Item $linkSource -Force
    }

    if ($ReplaceEmptyFile -and [String]::IsNullOrWhiteSpace((Get-Content $link.FullName))) {
        Write-Warning "Replacing empty file $($link.FullName)"
        Remove-Item $link.FullName -Force
    }

    if ($link.Target) {
        Write-Host "$($link.FullName) -> $($link.Target)"
    } else {
        Write-Warning "$($link.FullName) already exists as file"
    }
} 

function global:Load-Functions {
    $functionsPath = (Join-Path (Split-Path $Profile –Parent) "functions")
    Get-ChildItem $functionsPath -filter "*.ps1" | ForEach-Object {
        Write-Host "$($_.FullName) : loaded"
		. $_.FullName
	}
}
Set-Alias lf Load-Functions
Set-Alias rlf Load-Functions

function Search-History (
    [parameter(Mandatory=$true)][string]$Search
) {
    Get-History | Where-Object {$_.CommandLine -Like "*${Search}*"}
}
Set-Alias sh Search-History
