#!/usr/bin/env bash

if [ "$(uname)" != "Darwin" ]; then
    echo "This only runs on macOS"
    exit
fi

pushd `dirname $0`

# Homebrew package management
if test ! $(which brew); then
    echo "Installing homebrew..."
    ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
fi
brew update
brew bundle
brew upgrade
brew cask upgrade

dotnet tool install --global dotnet-ef
if test ! $(which tfenv); then
    brew link tfenv
fi
tfenv install latest

# Git
if [ -f ../common/settings.json ]; then
    git config --global user.email $(cat ../common/settings.json | jq '.GitEmail')
    git config --global user.name "$(cat ../common/settings.json | jq '.GitName')"
else
    echo "Settings file ../common/settings.json not found, skipping personalization"
fi
if [ ! -f ~/.gitignore ]; then
    echo .DS_Store > ~/.gitignore
fi
git config --global core.excludesfile ~/.gitignore

# Let PowerShell Core configure itself
if test ! $(which pwsh); then
    echo "PowerShell Core (pwsh) not found, skipping setup"
else
    pwsh -nop -file ../common/bootstrap_pwsh.ps1
fi

popd