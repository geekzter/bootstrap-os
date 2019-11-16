#!/usr/bin/env pwsh

pwsh -noexit -command {Invoke-Expression (New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/vso/linux/bootstrap_vso.ps1')}
