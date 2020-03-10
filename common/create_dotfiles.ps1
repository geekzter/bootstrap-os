#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Creates.* in dotfiles to users home directory

.DESCRIPTION 
    Links .* in dotfiles to users home directory fromn dotfiles
    Copies .* from dotfiles/templates and updates those as req'd
    This uses PowerShell Core, so we can use it on Windows too
#>

function IsElevated {
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
function CopyFileToHome (
    [string]$File,
    [string]$DotfilesDirectory
) {
    $target = $(Join-Path $HOME $File)
    $source = $(Join-Path $DotfilesDirectory $File)

    Write-Information "Copying $source => $target"
    $item = Copy-Item -LiteralPath $source -Destination $target -Force -PassThru
    Write-Host "$($item.FullName) <= $source"
} 
function LinkFileToHome (
    [string]$File,
    [string]$DotfilesDirectory
) {
    $linkSource = $(Join-Path $HOME $File)
    $linkTarget = $(Join-Path $DotfilesDirectory $File)

    if (!(Test-Path $linkSource)) {
        Write-Information "Creating symbolic link $linkSource -> $linkTarget"
        $link = New-Item -ItemType symboliclink -path "$linkSource" -value "$linkTarget"
    } else {
        $link = Get-Item $linkSource -Force
    }
    if ($link.Target) {
        Write-Host "$($link.FullName) -> $($link.Target)"
    } else {
        Write-Information "$($link.FullName) already exists as file"
    }
} 

# Link files from dotfiles
# This works on Windows only when elevated
if ((!$IsWindows) -or (IsElevated)) {
    $dotFilesDirectory = $(Join-Path (Split-Path -parent (Split-Path -parent -Path $MyInvocation.MyCommand.Path)) "dotfiles")
    Write-Information "Creating dotfiles in $HOME by linking them to ${dotFilesDirectory}..."
    $dotFiles = Get-ChildItem -Path (Join-Path $dotFilesDirectory .*) -Force
    foreach ($dotFile in $dotFiles) {
        LinkFileToHome -File $dotFile.Name -DotfilesDirectory $dotFilesDirectory
    }
}

# Copy files from dotfiles/templates
$dotTemplatesDirectory = Join-Path $dotFilesDirectory templates
Write-Information "Creating dotfiles in $HOME by copying them from ${dotTemplatesDirectory}..."
$dotFiles = Get-ChildItem -Path (Join-Path $dotTemplatesDirectory .*) -Force
foreach ($dotFile in $dotFiles) {
    CopyFileToHome -File $dotFile.Name -DotfilesDirectory $dotTemplatesDirectory
}

# Updated copied dotfiles as needed
$tmuxConf = Join-Path $HOME .tmux.conf
if (Test-Path $tmuxConf) {
    Write-Host "Configure $tmuxConf"
    (Get-Content $tmuxConf) -replace "^set-option.*default-shell.*$","set-option -g default-shell $((Get-Command pwsh).Source)" | Out-File $tmuxConf
}