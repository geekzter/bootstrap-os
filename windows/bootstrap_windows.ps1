# No shebang, as Windows only
<#
    Pre-git bootstrap stage
    - Installs git
    - Get's latest version of repo
    - Kicks off next stage
#>
param ( 
    [parameter(Mandatory=$false)][switch]$Packages=$false,
    [parameter(Mandatory=$false)][switch]$PowerShell=$false,
    [parameter(Mandatory=$false)][switch]$Settings=$false,
    [parameter(Mandatory=$false)][string]$Repository="https://github.com/geekzter/bootstrap-os"
) 

# Validation
if ($PSVersionTable.PSEdition -and ($PSVersionTable.PSEdition -eq "Core") -and !$IsWindows) {
    Write-Output "Not running on Windows"
    exit
}
if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
    Write-Output "Not running as Administrator"
    exit
}

# Provide at least one argument
if (!($Packages -or $Powershell -or $Settings)) {
    $All = $true
    Write-Host "No selective switches provided, bootstrapping everything"
    #Get-Help $MyInvocation.MyCommand.Definition # won't work with script downloaded using System.Net.WebClient.DownloadString()
}

# Disable IE Enhanced Security Mode
$ieSecMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IsInstalled
if ($ieSecMode -and ($ieSecMode -ne 0)) {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 
    Stop-Process -Name Explorer -Force # Should spawn a new process
}

# Install Chocolatey
if (!(Get-Command "choco.exe" -ErrorAction SilentlyContinue)) {
    Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

# Install Chocolatey packages
choco install git.install -y
refreshenv # This should update the path with changes made by Chocolatey

# Clone (the rest of) the repository
$repoDirectory = Join-Path $HOME "Source\Public"
if (!(Test-Path $repoDirectory)) {
    New-Item -ItemType Directory -Force -Path $repoDirectory
}
$bootstrapDirectory = Join-Path $repoDirectory "bootstrap-os"
$gitPath = (Get-Command "git.exe" -ErrorAction SilentlyContinue).Source
if (!($gitPath)) {
    $gitPath = "$env:ProgramFiles\Git\Bin"
}
if ($gitPath) {
    $env:Path += ";$gitPath"
} else {
    Write-Error "Git not found, quiting..."
    exit
}
if (!(Test-Path $bootstrapDirectory)) {
    Set-Location $repoDirectory    
    Write-Host "Cloning $Repository into $repoDirectory..."
    git clone $Repository   
} else {
    # git update if repo already exists
    Set-Location $bootstrapDirectory
    Write-Host "Pulling $Repository in $bootstrapDirectory..."
    git pull
}
$windowsBootstrapDirectory = Join-Path $bootstrapDirectory "windows"
if (!(Test-Path $windowsBootstrapDirectory)) {
    Write-Error "Clone of bootstrap repository was not successful"
    exit
} else {
    Set-Location $windowsBootstrapDirectory
}

# Invoke next stage
$stage2Script = "bootstrap_windows2.ps1"
if (!(Test-Path $stage2Script)) {
    Write-Error "Stage 2 script $stage2Script not found, exiting"
    exit
}
& ".\$stage2Script" -All:$All -Packages:$Packages -PowerShell:$PowerShell -Settings:$Settings
