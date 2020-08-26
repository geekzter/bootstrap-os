#!/usr/bin/env bash

if [ "$EUID" = "0" ]; then
    CANELEVATE='true'
    SUDO=''
elif test $(which sudo); then
    CANELEVATE='true'
    SUDO='sudo'
else
    CANELEVATE='false'
fi

# Detect Linux distribution
if [[ "$CANELEVATE" = "true" ]]; then
    if test ! $(which lsb_release); then
        if test $(which apt-get); then
            # Debian/Ubuntu
            $SUDO apt-get install lsb-release -y
        elif test $(which yum); then
            # CentOS/Red Hat
            $SUDO yum install redhat-lsb-core -y
        elif test $(which zypper); then
            # (Open)SUSE
            $SUDO zypper install lsb-release -y
        else
            echo $'\nlsb_release not found, not able to detect distribution'
            exit 1
        fi
    fi
fi
if test $(which lsb_release); then
    DISTRIB_ID=$(lsb_release -i -s)
    DISTRIB_RELEASE=$(lsb_release -r -s)
    DISTRIB_RELEASE_MAJOR=$(lsb_release -s -r | cut -d '.' -f 1)
    lsb_release -a
fi

# Packages
if [ $CANELEVATE = "false" ]; then
    echo $'\nsudo not found, skipping packages'
else
    if test ! $(which apt-get); then
        echo $'\napt-get not found, skipping packages'
    else
        # pre-requisites
        $SUDO apt-get install -y apt-transport-https curl
        
        # Kubernetes requirement
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | $SUDO apt-key add -
        cat <<EOF | $SUDO tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
        # Installs Azure CLI including dependencies
        curl -sL https://aka.ms/InstallAzureCLIDeb | $SUDO bash

        # Microsoft dependencies
        # Source: https://github.com/Azure/azure-functions-core-tools
        curl https://packages.microsoft.com/keys/microsoft.asc | $SUDO apt-key add -
        if [ "$DISTRIB_ID" == "Debian" ]; then
            # Microsoft dependencies
            # Source: https://github.com/Azure/azure-functions-core-tools
            wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > microsoft.asc.gpg
            $SUDO mv microsoft.asc.gpg /etc/apt/trusted.gpg.d/
            wget -q https://packages.microsoft.com/config/debian/${DISTRIB_RELEASE_MAJOR}/prod.list
            $SUDO mv prod.list /etc/apt/sources.list.d/microsoft-prod.list
            $SUDO chown root:root /etc/apt/trusted.gpg.d/microsoft.asc.gpg
            $SUDO chown root:root /etc/apt/sources.list.d/microsoft-prod.list
        fi
        if [ "$DISTRIB_ID" == "Ubuntu" ]; then
            # Microsoft dependencies
            # Source: https://github.com/Azure/azure-functions-core-tools
            curl https://packages.microsoft.com/config/ubuntu/${DISTRIB_RELEASE}/prod.list | $SUDO tee /etc/apt/sources.list.d/msprod.list
            $SUDO dpkg -i packages-microsoft-prod.deb

            # Required for Midnight Commander
            $SUDO add-apt-repository universe

            # For Ubuntu, this PPA provides the latest stable upstream Git version
            $SUDO add-apt-repository ppa:git-core/ppa
        fi

        echo $'\nUpdating package list...'
        $SUDO apt-get update

        echo $'\nUpgrading packages...'
        $SUDO ACCEPT_EULA=Y apt-get upgrade -y

        echo $'\nInstalling new packages...'
        INSTALLED_PACKAGES=$(mktemp)
        NEW_PACKAGES=$(mktemp)
        dpkg -l | grep ^ii | awk '{print $2}' >$INSTALLED_PACKAGES
        grep -Fvx -f $INSTALLED_PACKAGES ./apt-packages.txt >$NEW_PACKAGES
        while read package; do 
            $SUDO ACCEPT_EULA=Y apt-get install -y $package
        done < $NEW_PACKAGES
        rm $INSTALLED_PACKAGES $NEW_PACKAGES
    fi
fi

# PowerShell
if test ! $(which pwsh); then
    echo $'\nPowerShell Core (pwsh) not found, skipping setup'
else
    echo $'\nSetting up PowerShell Core...'
    pwsh -nop -file ../common/common_setup.ps1
fi

# Set up terraform with tfenv
if test $(which unzip); then
    if [ ! -d $HOME/.tfenv ]; then
        echo $'\nInstalling tfenv...'
        git clone https://github.com/tfutils/tfenv.git $HOME/.tfenv
    else
        echo $'\nUpdating tfenv...'
        git -C $HOME/.tfenv pull
    fi
    $HOME/.tfenv/bin/tfenv install latest
else
    echo $'\nunzip not found, skipping tfenv set up'
fi

# Git settings
if test $(which jq); then
    if [ -f ../common/settings.json ]; then
        git config --global user.email $(cat ../common/settings.json | jq '.GitEmail')
        git config --global user.name "$(cat ../common/settings.json | jq '.GitName')"
    else
        echo $'\n'
        echo "Settings file $(cd ../common/ && pwd)/settings.json not found, skipping personalization"
    fi
else
    echo $'\njq not found, skipping personalization'
fi
