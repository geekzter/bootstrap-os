#!/usr/bin/env pwsh
<#
.SYNOPSIS 
    Creates.* in dotfiles to users home directory

.DESCRIPTION 
    Links .* in dotfiles to users home directory fromn dotfiles
    Copies .* from dotfiles/templates and updates those as req'd
    This uses PowerShell Core, so we can use it on Windows too
#>

# Load Functions
. (Join-Path (Split-Path -parent -Path $MyInvocation.MyCommand.Path) "functions.ps1")

# Link files from dotfiles
# This works on Windows only when elevated
if ((!$IsWindows) -or (IsElevated)) {
    $dotFilesDirectory = $(Join-Path (Split-Path -parent (Split-Path -parent -Path $MyInvocation.MyCommand.Path)) "dotfiles")
    Write-Information "Creating dotfiles in $HOME by linking them to ${dotFilesDirectory}..."
    $dotFiles = Get-ChildItem -Path (Join-Path $dotFilesDirectory .*) -Force
    foreach ($dotFile in $dotFiles) {
        LinkFile -File $dotFile.Name -SourceDirectory $dotFilesDirectory -TargetDirectory $HOME
    }
}

# # Copy files from dotfiles/templates
# $dotTemplatesDirectory = Join-Path $dotFilesDirectory templates
# Write-Information "Creating dotfiles in $HOME by copying them from ${dotTemplatesDirectory}..."
# $dotFiles = Get-ChildItem -Path (Join-Path $dotTemplatesDirectory .*) -Force
# foreach ($dotFile in $dotFiles) {
#     CopyFile -File $dotFile.Name -SourceDirectory $dotTemplatesDirectory -TargetDirectory $HOME
# }
