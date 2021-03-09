param ( 
    [parameter(Mandatory=$false)][switch]$InstallToolsIfMissing
) 

$onWindows = ($IsWindows -or ($PSVersionTable.PSVersion.Major -le 5))
if (!$onWindows) {
    Write-Warning "This can only be run from Windows, exiting"
    exit
}
$elevated = (New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")
if (!$elevated) {
    Write-Warning "Policy export requires administrative permissions, exiting"
    exit
}
if (!(Get-Command lgpo -ErrorAction SilentlyContinue)) {
    if ($InstallToolsIfMissing -and (Get-Command choco -ErrorAction SilentlyContinue)) {
        choco install winsecuritybaseline
    }
}
if (!(Get-Command lgpo -ErrorAction SilentlyContinue)) {
    Write-Warning "LGPO not found. Please install by running 'choco install winsecuritybaseline' from an elevated shell, or downloading and installing it from https://www.microsoft.com/en-us/download/details.aspx?id=55319"
    exit
}

# Find root repo directory
$userPolicyText = (Join-Path $PSScriptRoot "user-policy.txt")
if (!(Test-Path $userPolicyText)) {
    Write-Warning "Policy text file ${userPolicyText} not found, exiting"
    exit
}

Write-Host "Importing policy text file ${userPolicyText}..."
lgpo /t $userPolicyText
gpupdate /Target:User /Force