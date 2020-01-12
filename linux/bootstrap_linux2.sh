#!/usr/bin/env bash

SCRIPTPATH=`dirname $0`

# Packages
if test ! $(which sudo); then
    echo $'\nsudo not found, skipping packages'
else
    if test ! $(which apt-get); then
        echo $'\napt-get not found, skipping packages'
    else
        # Kubernetes requirement
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF

        # Microsoft package repo
        curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
        if [ "$DISTRIB_ID" == "Ubuntu" ]; then
            sudo apt-add-repository https://packages.microsoft.com/ubuntu/${DISTRIB_RELEASE}/prod
            sudo apt-add-repository ppa:cpick/hub 
            sudo add-apt-repository ppa:git-core/ppa 
        fi

        echo $'\nUpdating package list...'
        sudo apt-get update
        echo $'\nInstalling packages...'
        xargs -a ${SCRIPTPATH}/apt-packages.txt sudo apt-get install -y
        echo $'\nUpgrading packages...'
        sudo apt-get upgrade -y
    fi
fi

# PowerShell
if test ! $(which git); then
    echo $'\nPowerShell Core (pwsh) not found, skipping setup'
else
    echo $'\nSetting up PowerShell Core...'
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
