#!/usr/bin/env pwsh

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

# Define prompt
function global:Prompt {
    $host.ui.rawui.WindowTitle = "PowerShell Core $($host.Version.ToString())"

    if ($executionContext.SessionState.Path.CurrentLocation.Path.StartsWith($home)) {
        $path = $executionContext.SessionState.Path.CurrentLocation.Path.Replace($home,"~")
    } else {
        $path = $executionContext.SessionState.Path.CurrentLocation.Path
    }

    $branch = $(git rev-parse --abbrev-ref HEAD 2>$null)
    $prompt = $path
    if ($branch) {
        $prompt += ":$branch"
    }
    if (IsElevated) {
        $host.ui.rawui.WindowTitle += " # "
        $prompt += "$('#' * ($nestedPromptLevel + 1)) ";
	} else {
        $host.ui.rawui.WindowTitle += " - "
        $prompt += "$('>' * ($nestedPromptLevel + 1)) ";
	}

    $host.ui.rawui.WindowTitle += "$($executionContext.SessionState.Path.CurrentLocation.Path)"

    $prompt
}

if ($host.Name -eq 'ConsoleHost')
{
    Import-Module posh-git
    Import-Module oh-my-posh
    # Wait until PSReadLine 2.0.0 is released
    #Set-Theme Agnoster
    #Set-Theme Paradox
}

$bootstrapDirectory = Split-Path -Parent (Split-Path -Parent (Get-Item $MyInvocation.MyCommand.Path).Target)
Write-Host "To update configuration, run " -NoNewline
if ($IsWindows) {
    Write-Host "(Windows PowerShell)`n$bootstrapDirectory\windows\bootstrap_windows.ps1"
}
if ($IsMacOS) {
    Write-Host "$bootstrapDirectory/macOS/bootstrap_mac.sh"
}
if ($IsLinux) {
    Write-Host "$bootstrapDirectory/linux/bootstrap_linux.sh"
}

# Linux & macOS only:
if ($PSVersionTable.PSEdition -and ($PSVersionTable.PSEdition -eq "Core") -and ($IsLinux -or $IsMacOS)) {
    # Manage PATH environment variable
    [System.Collections.ArrayList]$pathList = $env:PATH.Split(":")
    if (!$pathList.Contains("/usr/local/bin")) {
        $pathList.Insert(1,"/usr/local/bin")
    }
    if (!$pathList.Contains("~/.dotnet/tools")) {
        $null = $pathList.Add("~/.dotnet/tools")
    }
    if (!$pathList.Contains("/usr/local/share/dotnet")) {
        $null = $pathList.Add("/usr/local/share/dotnet")
    }
    if (!($(Get-Command tfenv -ErrorAction SilentlyContinue)) -and (Test-Path ~/.tfenv/bin) -and !$env:PATH.Contains("tfenv/bin")) {
        $null = $pathList.Add("${env:HOME}/.tfenv/bin")
    }
    $env:PATH = $pathList -Join ":"

    # Source environment variables from ~/.config/powershell/environment.ps1
    $environmentPath = (Join-Path (Split-Path $MyInvocation.MyCommand.Path –Parent) "environment.ps1")
    if (Test-Path -Path $environmentPath) {
        Write-Output "Sourcing $environmentPath"
        . $environmentPath
    } else {
        Write-Output "$environmentPath not found"
    }
}

# Install Az module if not present
if (!(Get-Module Az -ListAvailable)) {
    Write-Host "Az modules not present, installing..."
    Install-Module Az
}
Get-Module Az -ListAvailable | Select-Object -First 1 -Property Name, Version

# Functions
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

# Go to home (not automatic for elevated prompt)
if (IsElevated) {
    # But only if not a nested shell
    if ((Get-Process -id $pid).Parent.Parent.ProcessName -ne "pwsh") {        
        if ($home -and (Test-Path $home)) {
            Set-Location $home
        } else {
            if ($env:USERPROFILE -and (Test-Path $env:USERPROFILE)) {
                Set-Location $env:USERPROFILE
            } 
        }
    }
}