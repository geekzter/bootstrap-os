#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Links .* in dotfiles to users home directory

.DESCRIPTION 
    Links .* in dotfiles to users home directory.
    This uses PowerShell Core, so we can use it on Windows too
#>

function DisplayLink (
    [object]$Link
) {
    if ($Link.Target) {
        Write-Host "$($Link.FullName) -> $($Link.Target) link created"
    } else {
        Write-Host "$($Link.FullName) already exists as file"
    }
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
        $link = Get-Item (Join-Path $HOME $File) -Force
    }
    DisplayLink -Link $link
} 

$dotFilesDirectory = $(Join-Path (Split-Path -parent (Split-Path -parent -Path $MyInvocation.MyCommand.Path)) "dotfiles")
Write-Verbose "dotfiles directory: $dotFilesDirectory"
$dotFiles = Get-ChildItem -Path (Join-Path $dotFilesDirectory .*) -Hidden
foreach ($dotFile in $dotFiles) {
    LinkFileToHome -File $dotFile.Name -DotfilesDirectory $dotFilesDirectory
}