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
fi
softwareupdate --all --install --force

# Homebrew package management
if test ! $(which brew); then
    echo "Installing homebrew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi
brew update
brew bundle
brew upgrade
brew cask upgrade

# .NET tools
dotnet tool update --global dotnet-ef

# Terraform
if test ! $(which tfenv); then
    brew link tfenv
fi
tfenv install latest

# Let PowerShell Core configure itself
if test ! $(which pwsh); then
    echo "PowerShell Core (pwsh) not found, skipping setup"
else
    echo $'\nSetting up PowerShell Core...'
    pwsh -nop -file ../common/common_setup.ps1
fi

popd