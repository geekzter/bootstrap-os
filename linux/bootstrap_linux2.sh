#!/usr/bin/env bash

SCRIPT_PATH=`dirname $0`

# Detect Linux distribution
if test ! $(which lsb_release); then
    if test $(which apt-get); then
        # Debian/Ubuntu
        sudo apt-get install lsb-release -y
    elif test $(which yum); then
        # CentOS/Red Hat
        sudo yum install redhat-lsb-core -y
    elif test $(which zypper); then
        # (Open)SUSE
        sudo zypper install lsb-release -y
    else
        echo $'\nlsb_release not found, not able to detect distribution'
        exit 1
    fi
fi
if test $(which lsb_release); then
    DISTRIB_ID=$(lsb_release -i -s)
    DISTRIB_RELEASE=$(lsb_release -r -s)
    DISTRIB_RELEASE_MAJOR=$(lsb_release -s -r | cut -d '.' -f 1)
    lsb_release -a
fi

# Packages
if test ! $(which sudo); then
    echo $'\nsudo not found, skipping packages'
else
    if test ! $(which apt-get); then
        echo $'\napt-get not found, skipping packages'
    else
        # pre-requisites
        sudo apt-get install -y apt-transport-https curl

        # Required for Midnight Commander
        sudo add-apt-repository universe
        
        # Kubernetes requirement
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
        cat <<EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
        # Installs Azure CLI including dependencies
        curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

        # Microsoft dependencies
        # Source: https://github.com/Azure/azure-functions-core-tools
        curl https://packages.microsoft.com/keys/microsoft.asc | sudo apt-key add -
        if [ "$DISTRIB_ID" == "Debian" ]; then
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.asc.gpg
            sudo mv microsoft.asc.gpg /etc/apt/trusted.gpg.d/
            wget -q https://packages.microsoft.com/config/debian/${DISTRIB_RELEASE_MAJOR}/prod.list
            sudo mv prod.list /etc/apt/sources.list.d/microsoft-prod.list
            sudo chown root:root /etc/apt/trusted.gpg.d/microsoft.asc.gpg
            sudo chown root:root /etc/apt/sources.list.d/microsoft-prod.list
        fi
        if [ "$DISTRIB_ID" == "Ubuntu" ]; then
            curl https://packages.microsoft.com/config/ubuntu/${DISTRIB_RELEASE}/prod.list | sudo tee /etc/apt/sources.list.d/msprod.list
            sudo dpkg -i packages-microsoft-prod.deb
        fi

        echo $'\nUpdating package list...'
        sudo apt-get update

        echo $'\nUpgrading packages...'
        sudo ACCEPT_EULA=Y apt-get upgrade -y

        echo $'\nInstalling new packages...'
        INSTALLED_PACKAGES=$(mktemp)
        NEW_PACKAGES=$(mktemp)
        dpkg -l | grep ^ii | awk '{print $2}' >$INSTALLED_PACKAGES
        grep -Fvx -f $INSTALLED_PACKAGES ${SCRIPT_PATH}/apt-packages.txt >$NEW_PACKAGES
        while read package; do 
            sudo ACCEPT_EULA=Y apt-get install -y $package
        done < $NEW_PACKAGES
        rm $INSTALLED_PACKAGES $NEW_PACKAGES
    fi
fi

# PowerShell
if test ! $(which pwsh); then
    echo $'\nPowerShell Core (pwsh) not found, skipping setup'
else
    echo $'\nSetting up PowerShell Core...'
    pwsh -nop -file ${SCRIPT_PATH}/../common/bootstrap_pwsh.ps1
fi

# Set up terraform with tfenv
if [ ! -d $HOME/.tfenv ]; then
    echo $'\nInstalling tfenv...'
    git clone https://github.com/tfutils/tfenv.git $HOME/.tfenv
else
    echo $'\nUpdating tfenv...'
    git -C $HOME/.tfenv pull
fi
$HOME/.tfenv/bin/tfenv install latest

# Git settings
if [ -f ../common/settings.json ]; then
    git config --global user.email $(cat ../common/settings.json | jq '.GitEmail')
    git config --global user.name "$(cat ../common/settings.json | jq '.GitName')"
else
    echo $'\n'
    echo "Settings file $(cd $SCRIPT_PATH/../common/ && pwd)/settings.json not found, skipping personalization"
fi
