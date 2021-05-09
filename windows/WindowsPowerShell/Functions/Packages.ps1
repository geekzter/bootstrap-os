function Install-Terraform (
    [parameter(Mandatory=$false)][string]$Version="0.14.11"
) {
    if (get-command choco -ErrorAction SilentlyContinue) {
        choco upgrade terraform --version $Version --allow-downgrade -y
    } else {
        Write-Warning "This depends on Chocolatey, which was not found"
        return
    }
}