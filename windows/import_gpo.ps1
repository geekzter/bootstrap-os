param ( 
    [parameter(Mandatory=$false)][string]$PolicyFile=(Join-Path $PSScriptRoot "user-policy.txt"),
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
if (!(Test-Path $PolicyFile)) {
    Write-Warning "Policy text file ${PolicyFile} not found, exiting"
    exit
}

Write-Host "Importing policy file ${PolicyFile}..."
if ($PolicyFile -imatch "pol$") {
    lgpo /u:${env:username}   $PolicyFile /v
}
if ($PolicyFile -imatch "txt$") {
    lgpo /t $PolicyFile /v
}


gpupdate /Target:User /Force