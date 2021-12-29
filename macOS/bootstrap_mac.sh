#!/usr/bin/env bash

if [ "$(uname)" != "Darwin" ]; then
    echo "This only runs on macOS"
    exit
fi

pushd `dirname $0`

# Get latest
if [ -d ../.git ]; then
    echo "We're in repository at $(cd .. && pwd), updating..."
    git -C .. pull
fi

if [ ! -d "$(xcode-select -p)" ]; then 
    xcode-select --install
    sudo xcodebuild -license accept
fi
sudo softwareupdate --install-rosetta --agree-to-license
sudo softwareupdate --all --install --force

# Homebrew package management
if test ! $(which brew); then
    echo "Installing homebrew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> /Users/eric/.profile
    eval "$(/opt/homebrew/bin/brew shellenv)"
fi
brew update
brew bundle
brew upgrade

# .NET tools
dotnet tool update --global dotnet-ef

# Terraform
if test ! $(which tfenv); then
    brew link tfenv
fi
tfenv install latest

# PATH
echo "Updating /etc/paths.d..."
if [ ! -f /etc/paths.d/localbin ]; then
    sudo mkdir -p /etc/paths.d
    # This should include brew packages in the PATH for all shells
    echo /usr/local/bin | sudo tee /etc/paths.d/localbin
fi
if [[ ! "$(launchctl getenv PATH)" == *"/usr/local/bin"* ]]; then
    echo "Launch Control PATH does not contain /usr/local/bin, updating..."
    sudo launchctl config user path "/usr/local/bin:$(launchctl getenv PATH)"
fi

# Let PowerShell Core configure itself
if test ! $(which pwsh); then
    echo "PowerShell Core (pwsh) not found, skipping setup"
else
    echo $'\nSetting up PowerShell Core...'
    pwsh -nop -file ../common/common_setup.ps1
fi

popd
