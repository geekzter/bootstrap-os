# OS Bootstrap scripts
Every time you set up a new (virtual) machine, you always need to go through the same drill. Configuring the OS, to get rid of those anoying defauls and installing your default tools. Also, you like to keep them up to date. Tne bootstrap scrips in this project do that using package managers commonly used on each platform.

## Debian & Ubuntu
Invoke bootstrap directly from repo:   
`curl -sk https://raw.githubusercontent.com/geekzter/bootstrap-os/master/linux/bootstrap_linux.sh | bash`

## macOS
- Install Xcode Developer Tools by running `xcode-select --install`
- Clone repo: `git clone https://github.com/geekzter/bootstrap-os.git`
- Invoke bootstrap: `<repo>/macOS/bootsrap_mac.sh`

## Windows
Invoke bootstrap directly from repo:   
`PowerShell -ExecutionPolicy Bypass -Command "& {Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://raw.githubusercontent.com/geekzter/bootstrap-os/master/windows/bootstrap_windows.ps1'))}"`

## Limitations & Known Issues
- No Bash profile set up

## Resources
- [Chocolatey](https://chocolatey.org/)
- [Homebrew](https://brew.sh/)
- [PowerShell Core](https://github.com/PowerShell/PowerShell)
- [azure-devenv](https://github.com/geekzter/azure-devenv)

## Disclaimer
This rpo is provided as-is
