param ( 
    [parameter(Mandatory=$false)][switch]$InstallToolsIfMissing
) 

$onWindows = ($IsWindows -or ($PSVersionTable.PSEdition -ne "Core"))
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

$exportRoot = (Join-Path -Path (Split-Path $PSScriptRoot -Parent) "data\gpo")
if (!(Test-Path $exportRoot)) {
    $null = New-Item -ItemType Directory -Force -Path $exportRoot
}
Write-Host "Exporting Local Policy to ${exportRoot}..."
lgpo /b $exportRoot

$exportDirectory = (Get-ChildItem $exportRoot | Sort-Object -Property LastWriteTime -Descending | Where-Object -Property Name -Match '(?im)^[{(]?[0-9A-F]{8}[-]?(?:[0-9A-F]{4}[-]?){3}[0-9A-F]{12}[)}]?$' | Select-Object -First 1)
Write-Host "Local Policy exported to ${exportDirectory}..."

# User & Machine policies
foreach ($policyScope in @("user","machine")) {
    Write-Host "Processing ${policyScope} policy..."

    $policy = (Join-Path $exportDirectory.FullName "DomainSysvol\GPO\User\registry.pol")
    if (!(Test-Path $policy)) {
        Write-Warning "Policy ${policy} not found, exiting"
        exit
    }
    $savedPolicy = (Join-Path $PSScriptRoot "${policyScope}.pol")
    $null = Copy-Item -Path $policy -Destination $savedPolicy -Force

    $policyText = (Join-Path $PSScriptRoot "${policyScope}-policy.txt")
    Write-Host "Parsing policy file ${policy} to ${policyText}..."
    lgpo /parse /u $policy | Out-File $policyText
}