#  Powershell Profile Script
#  
#  Eric van Wijk <eric@van-wijk.com>
#return
#region Prepare Environment & Variables
if (Test-Path HKLM:\SOFTWARE\Classes\Applications\Quest.PowerGUI.ScriptEditor.exe\shell\open\command) {
	$__Editor = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Classes\Applications\Quest.PowerGUI.ScriptEditor.exe\shell\open\command" -Name "(default)" | Select-Object "(default)" | ForEach-Object {Write-Output $_."(default)"}).Split('"')[1]
} else {
	$__Editor = "notepad.exe"
}
#endregion


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

function prompt
{
	$host.ui.rawui.WindowTitle = "Windows PowerShell $($host.Version.ToString())"

	$path = $(Get-Location).Path

	Write-Host $path "" -NoNewline
	if ((New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
        $host.ui.rawui.WindowTitle += " # "
		Write-Host "#" -nonewline
	} else {
		$host.ui.rawui.WindowTitle += " - "
    	Write-Host "$" -nonewline
	}
    $host.ui.rawui.WindowTitle += $path
    return " "
}
#endregion

if ((Get-Location).ToString().StartsWith($env:SystemRoot,'CurrentCultureIgnoreCase')) {
	if (Test-Path $home) {
		Push-Location $home
	} else {
		Push-Location $env:USERPROFILE
	}
}

$bootstrapDirectory = Split-Path -Parent (Get-Item (Split-Path -Parent $PROFILE)).Target
$bootStrapCommand = "$bootstrapDirectory\windows\bootstrap_windows.ps1"
Write-Host "To update configuration, run" -NoNewline
if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
	Write-Host " (as Administrator)" -NoNewline
}
Write-Host ": `"$bootStrapCommand`""
