@echo off

PowerShell -Command "& {Set-ExecutionPolicy Bypass -Scope Process -Force; Invoke-Expression '%~dp0\bootstrap_windows.ps1 -All'}"
rem PowerShell -ExecutionPolicy Bypass -Command "& {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/windows/bootstrap_windows.ps1'))}"

pause