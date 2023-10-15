if (Get-Command podman -ErrorAction SilentlyContinue) {
    Set-Alias docker podman
    Set-Alias docker-compose podman-compose
}
Set-Alias his Get-History
Set-Alias ih Invoke-History
