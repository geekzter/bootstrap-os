# No shebang, as Windows only
param ( 
    [parameter(Mandatory=$false)][string]$Branch=$(git -C $PSScriptRoot rev-parse --abbrev-ref HEAD 2>$null || "master")
) 

Write-Host "`$Branch value is $Branch"
Write-Host "Current branch is $(git -C $PSScriptRoot rev-parse --abbrev-ref HEAD)"
