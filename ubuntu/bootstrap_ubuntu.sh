#!/usr/bin/env bash

if [ "$(uname)" != "Linux" ]; then
    echo "This only runs on Linux"
    exit
fi

# Source Ubuntu configuration
. /etc/lsb-release

if [ "$DISTRIB_ID" != "Ubuntu" ]; then
    echo "This only runs on Ubuntu"
    exit
fi
if [ "$DISTRIB_RELEASE" != "18.04" ]; then
    echo "This only runs on Ubuntu 18.04"
    exit
fi

# APT package management
if test ! $(which apt-get); then
    echo "apt-get not found"
    exit 1
fi

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
pushd /tmp
#sudo apt-get update
# Get install time packages
sudo apt-get install ca-certificates curl apt-transport-https lsb-release gnupg apt-transport-https
# Download and install the Microsoft Azure CLI signing key
curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | \
    sudo tee /etc/apt/trusted.gpg.d/microsoft.asc.gpg > /dev/null
# Add the Azure CLI software repository
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | \
    sudo tee /etc/apt/sources.list.d/azure-cli.list
# Download the Microsoft powershell repository GPG keys
wget -q https://packages.microsoft.com/config/ubuntu/${DISTRIB_RELEASE}/packages-microsoft-prod.deb
# Register the Microsoft powershell repository GPG keys
sudo dpkg -i packages-microsoft-prod.deb
sudo apt-get update
# Enable the "universe" repositories
sudo add-apt-repository universe

# Required workaround for Powershell
LIBICU=libicu55_55.1-7ubuntu0.4_amd64.deb
if [ ! -f "./$LIBICU" ]; then
    wget http://security.ubuntu.com/ubuntu/pool/main/i/icu/$LIBICU
fi
sudo apt install ./$LIBICU$DISTRIB_RELEASE
# Install packages
xargs -a ${SCRIPT_DIR}/apt-packages.txt sudo apt-get install -y

# Terraform
TF_VER=$(curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r -M '.current_version')
TF_RELEASE=terraform_${TF_VER}_linux_amd64.zip
if [ ! -f "./$TF_RELEASE" ]; then
    echo "New version (${TF_VER}) of Terraform available, updating..."
    wget https://releases.hashicorp.com/terraform/${TF_VER}/${TF_RELEASE}
fi
unzip ./$TF_RELEASE
sudo mv terraform /usr/local/bin/
sudo chmod +x /usr/local/bin/terraform
terraform --version 

popd

# Let PowerShell Core configure itself
if test ! $(which pwsh); then
    echo "PowerShell Core (pwsh) not found, skipping setup"
else
    pwsh -nop -file ../common/bootstrap_pwsh.ps1
fi

# Git
if [ -f ../common/settings.json ]; then
    git config --global user.email $(cat ../common/settings.json | jq '.GitEmail')
    git config --global user.name "$(cat ../common/settings.json | jq '.GitName')"
else
    echo "Settings file ../common/settings.json not found, skipping personalization"
fi
