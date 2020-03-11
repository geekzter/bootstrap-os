#  Powershell Profile Script


#region Load Functions
#&{
	$functionsPath = (Join-Path (Split-Path $Profile –Parent) "Functions")
	Write-Output "Loading functions from $functionsPath" 
	Get-ChildItem $functionsPath -filter "*.ps1" | ForEach-Object {
		Write-Output $_.Name 
		. $_.FullName
	}
	Write-Output " " # empty line 
#}
#endregion

function global:IsElevated {
    return (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")
}
function prompt
{
    if ($GitPromptScriptBlock) {
        # Use Posh-Git: https://github.com/dahlbyk/posh-git/wiki/Customizing-Your-PowerShell-Prompt
        # Use ~ for home directory in prompt
        $GitPromptSettings.DefaultPromptAbbreviateHomeDirectory = $true 
        # Don't overwrite the title set in iTerm2/Windows Terminal
        $GitPromptSettings.EnableWindowTitle = $null
        if (IsElevated) {
            $GitPromptSettings.DefaultPromptSuffix = "`$('#' * (`$nestedPromptLevel + 1)) "
        } else {
            $GitPromptSettings.DefaultPromptSuffix = "`$('>' * (`$nestedPromptLevel + 1)) "
        }
        & $GitPromptScriptBlock
    } else {
		$host.ui.rawui.WindowTitle = "Windows PowerShell $($host.Version.ToString())"

		$path = $(Get-Location).Path

		Write-Host $path "" -NoNewline
		if (IsElevated) {
			$host.ui.rawui.WindowTitle += " # "
			Write-Host "#" -nonewline
		} else {
			$host.ui.rawui.WindowTitle += " - "
			Write-Host "$" -nonewline
		}
		$host.ui.rawui.WindowTitle += $path
		return " "
    }
}
#endregion

if (Get-InstalledModule Posh-Git) {
	Import-Module Posh-Git
}

if ((Get-Location).ToString().StartsWith($env:SystemRoot,'CurrentCultureIgnoreCase')) {
	if (Test-Path $home) {
		Push-Location $home
	} else {
		Push-Location $env:USERPROFILE
	}
}

$bootstrapDirectory = Split-Path -Parent (Get-Item (Split-Path -Parent $PROFILE)).Target
$bootStrapCommand = "$bootstrapDirectory\bootstrap_windows.ps1"
Write-Host "To update configuration, run" -NoNewline
if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
	Write-Host " (as Administrator)" -NoNewline
}
Write-Host ": $bootStrapCommand"
