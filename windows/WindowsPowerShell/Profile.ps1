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
        $GitPromptSettings.WindowTitle = $null
        if (IsElevated) {
            $GitPromptSettings.DefaultPromptSuffix = "`$('#' * (`$nestedPromptLevel + 1)) "
        } else {
            $GitPromptSettings.DefaultPromptSuffix = "`$('>' * (`$nestedPromptLevel + 1)) "
        }
        $prompt = (& $GitPromptScriptBlock)
    } else {
        $host.ui.rawui.WindowTitle = "PowerShell Core $($host.Version.ToString())"

        if ($executionContext.SessionState.Path.CurrentLocation.Path.StartsWith($home)) {
            $path = $executionContext.SessionState.Path.CurrentLocation.Path.Replace($home,"~")
        } else {
            $path = $executionContext.SessionState.Path.CurrentLocation.Path
        }

        $host.ui.rawui.WindowTitle += "$($executionContext.SessionState.Path.CurrentLocation.Path)"
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
    }
    if ($prompt) { "$prompt" } else { " " }
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
