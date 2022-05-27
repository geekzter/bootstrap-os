# No shebang, as Windows only
<#
.SYNOPSIS 
    Script used to bootstrap Windows workstation
 
.DESCRIPTION 
    Pre-git bootstrap stage
    - Installs git
    - Get's latest version of repo
    - Kicks off next stage

.EXAMPLE
    cmd.exe /c start PowerShell.exe -ExecutionPolicy Bypass -Noexit -Command "& {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://github.com/geekzter/bootstrap-os/blob/master/windows/bootstrap_windows.ps1'))}"
#> 
param ( 
    [parameter(Mandatory=$false)][switch]$All=$false,
    [parameter(Mandatory=$false)][ValidateSet("Desktop", "Developer", "Minimal", "None")][string[]]$Packages=@("Minimal"),
    [parameter(Mandatory=$false)][bool]$PowerShell=$false,
    [parameter(Mandatory=$false)][bool]$Settings=$true,
    [parameter(Mandatory=$false)][string]$Repository="https://github.com/geekzter/bootstrap-os",
    [parameter(Mandatory=$false)][string]$Branch=$(git -C $PSScriptRoot rev-parse --abbrev-ref HEAD 2>$null)
) 

# Validation
if ($PSVersionTable.PSEdition -eq "Core") {
    if (!$IsWindows) {
        Write-Output "Not running on Windows"
        exit
    }

    [System.Version]$windows11AndUp = "10.0.22000"
    [System.Version]$currentVersion = (Get-ComputerInfo).OsVersion
    if ($currentVersion -lt $windows11AndUp) {
        # Windows 10 and below needs Windows PowerShell
        Write-Output "Not running on Windows PowerShell"
        exit    
    }
}    
if (!(New-Object System.Security.Principal.WindowsPrincipal([System.Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole("Administrators")) {
    Write-Output "Not running as Administrator"
    exit
}

# Disable IE Enhanced Security Mode
$ieSecMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IsInstalled
if ($ieSecMode -and ($ieSecMode -ne 0)) {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Type DWord -Value 0 
    $killExplorer = $true
}
$ieSecMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty IsInstalled
if ($ieSecMode -and ($ieSecMode -ne 0)) {
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Type DWord -Value 0 
    $killExplorer = $true
}
if ($killExplorer) {
    Stop-Process -Name Explorer -Force -ErrorAction SilentlyContinue # Should spawn a new process
}

# Install Chocolatey
if (!(Get-Command "choco.exe" -ErrorAction SilentlyContinue)) {
    if ((Get-ExecutionPolicy) -ine "ByPass") {
        Set-ExecutionPolicy Bypass -Scope Process -Force
    } 
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
}

# Install Chocolatey packages
choco install git -y
if (Get-Command refreshenv -ErrorAction SilentlyContinue) {
    refreshenv # This should update the path with changes made by Chocolatey
}

# Clone (the rest of) the repository
$repoDirectory = Join-Path $HOME "Source\GitHub\geekzter"
if (!(Test-Path $repoDirectory)) {
    $null = New-Item -ItemType Directory -Force -Path $repoDirectory
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
if ($Branch) {
    git -C $bootstrapDirectory switch $Branch
}
$windowsBootstrapDirectory = Join-Path $bootstrapDirectory "windows"
if (!(Test-Path $windowsBootstrapDirectory)) {
    Write-Error "Clone of bootstrap repository was not successful"
    exit
} else {
    Set-Location $windowsBootstrapDirectory
}

# Invoke next stage
$userExecutionPolicy = Get-ExecutionPolicy -Scope CurrentUser
if (($userExecutionPolicy -ieq "AllSigned") -or ($userExecutionPolicy -ieq "Undefined")) {
    if ((Get-ExecutionPolicy) -ine "ByPass") {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    } 
}
$stage2Script = "bootstrap_windows2.ps1"
if (!(Test-Path $stage2Script)) {
    Write-Error "Stage 2 script $stage2Script not found, exiting"
    exit
}
& ".\$stage2Script" -All:$All -Packages:$Packages -PowerShell:$PowerShell -Settings:$Settings
