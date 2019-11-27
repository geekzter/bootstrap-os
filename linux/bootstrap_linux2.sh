#!/usr/bin/env bash

SCRIPTPATH=`dirname $0`

# Packages
if test ! $(which apt-get); then
    echo $'\napt-get not found, skipping packages'
else
    if test ! $(which sudo); then
        echo $'\nsudo not found, skipping packages'
    else
        echo $'\nInstalling/updating packages...'
        xargs -a ${SCRIPTPATH}/apt-packages.txt sudo apt-get install -y
    fi
fi

# PowerShell
if test ! $(which git); then
    echo $'\nPowerShell Core (pwsh) not found, skipping setup'
else
    echo $'\nSetting up PowerShell Core..'
    pwsh -nop -file $SCRIPTPATH/../common/bootstrap_pwsh.ps1
fi

# Set up terraform with tfenv
### Check if a directory does not exist ###
if [ ! -d ~/.tfenv ]; then
    echo $'\nInstalling tfenv...'
    git clone https://github.com/tfutils/tfenv.git ~/.tfenv
else
    echo $'\nUpdating tfenv...'
    git -C ~/.tfenv pull
fi
~/.tfenv/bin/tfenv install latest

# Git settings
if [ -f ../common/settings.json ]; then
    git config --global user.email $(cat ../common/settings.json | jq '.GitEmail')
    git config --global user.name "$(cat ../common/settings.json | jq '.GitName')"
else
    echo $'\n'
    echo "Settings file $(cd $SCRIPTPATH/../common/ && pwd)/settings.json not found, skipping personalization"
fi
