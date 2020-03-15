function Apply-Terraform {
    terraform apply -auto-approve
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
}
Set-Alias cdtf CD-Terraform
Set-Alias tfcd CD-Terraform

function Clear-TerraformState {
    #terraform state list | xargs -L 1 terraform state rm
    terraform state list | ForEach-Object { 
        terraform state rm $_
    }
}
Set-Alias tfclr Clear-TerraformState

function Destroy-Terraform {
    terraform destroy # -auto-approve
}
Set-Alias tfd Destroy-Terraform

function List-TerraformState {
    terraform state list
}
Set-Alias tfls List-TerraformState
