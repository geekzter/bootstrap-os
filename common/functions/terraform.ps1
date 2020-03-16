function Apply-Terraform {
    Invoke "terraform apply -auto-approve"
}
Set-Alias tfa Apply-Terraform

function CD-Terraform {
    $depth = 2

    $main = Get-ChildItem -Path . -Filter main.tf -Recurse -Depth $depth | Select-Object -First 1
    if (!$main) {
        # Go one level below current directory
        $main = Get-ChildItem -Path .. -Filter main.tf -Recurse -Depth $depth | Select-Object -First 1
    }
    if ($main) {
        Push-Location $main.Directory.FullName
    } else {
        Write-Warning "Terraform directory not found"
    }

    return $main
}
Set-Alias cdtf CD-Terraform
Set-Alias tfcd CD-Terraform

function Clear-TerraformState {
    terraform state list | ForEach-Object { 
        terraform state rm $_
    }
}
Set-Alias tfclr Clear-TerraformState

function Destroy-Terraform {
    Invoke "terraform destroy" # -auto-approve
}
Set-Alias tfd Destroy-Terraform

function Get-TerraformInfo {
    if (Get-Command git -ErrorAction SilentlyContinue) {
        Invoke-Command -ScriptBlock {
            $Private:ErrorActionPreference = "SilentlyContinue"
            $branch = $(git rev-parse --abbrev-ref HEAD 2>$null)
            if ($branch) {
                Write-Host "Git branch: $branch"
            }
        }
    }
    Write-Host "Terraform workspace: $(terraform workspace show)"
    Get-ChildItem -Path Env: -Recurse -Include ARM_*,TF_* | Sort-Object -Property Name
}
Set-Alias tfi Get-TerraformInfo

function Invoke (
    [string]$cmd
) {
    Write-Host "`n$cmd" -ForegroundColor Green 
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        exit
    }
}

function Invoke-Terraform (
    [string]$cmd
) {
    $main = CD-Terraform
    Write-Host "`n$cmd" -ForegroundColor Green 
    Invoke-Expression $cmd
    if ($LASTEXITCODE -ne 0) {
        exit
    }
    if ($main) {
        Pop-Location
    }
}

function List-TerraformState {
    Invoke "terraform state list"
}
Set-Alias tfls List-TerraformState
