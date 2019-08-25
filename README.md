# OS Bootstrap scripts
Every time you set up a new (virtual) machine, you always need to go through the same drill. Configuring the OS, to get rid of those anoying defauls and installing your default tools. Also, you like to keep them up to date. Tne bootstrap scrips in this project do that using package managers commonly used on each platform.

## Usage
- macOS: Clone this repo and run bootstrap script from OS directory. Review [manual steps](./Mac/README.md) not automated
- Ubuntu: Clone this repo and run bootstrap script from OS directory
- Windows: Copy/download `bootstrap_windows.cmd` & `bootstrap_windows.ps1`, and run `bootstrap_windows.cmd` (this also installs Git, as this not on a vanilla Windows install)

## Limitations & Known Issues
- No Bash profile set up
- This does not (yet) integrate with a VM provisioning service e.g. Azure DevTest Labs

## Resources
- [Chocolatey](https://chocolatey.org/)
- [Homebrew](https://brew.sh/)
- [PowerShell Core](https://github.com/PowerShell/PowerShell)

## Disclaimer
This project is provided as-is