#!/usr/bin/env bash

# Process arguments
INSTALL_PACKAGES='true'
while [ "$1" != "" ]; do
    case $1 in
        --skip-packages)                shift
                                        INSTALL_PACKAGES='false'
                                        COMMON_SETUP_ARGS="-NoPackages"
                                        ;;                                                                                                                
       * )                              echo "Invalid argument: $1"
                                        exit 1
    esac
    shift
done

SCRIPT_PATH=`dirname $0`

if [ "$EUID" = "0" ]; then
    CANELEVATE='true'
    SUDO=''
    SUDOEULA=''
elif test $(which sudo); then
    CANELEVATE='true'
    SUDO='sudo'
    SUDOEULA='sudo ACCEPT_EULA=Y'
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
    lsb_release -ar 2>/dev/null
fi

# Packages
if [ $INSTALL_PACKAGES = "false" ]; then
    echo $'\nSkipping packages'
else
    if [ $CANELEVATE = "false" ]; then
        echo $'\nsudo not found, skipping packages'
    else
        if test ! $(which apt-get); then
            echo $'\napt-get not found, skipping packages'
        else
            # pre-requisites
            $SUDO apt-get install -y apt-transport-https curl software-properties-common
            
            # Kubernetes requirement
            curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | $SUDO apt-key add -
            cat <<EOF | $SUDO tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
            # Installs Azure CLI including dependencies
            curl -sL https://aka.ms/InstallAzureCLIDeb | $SUDO bash 2>/dev/null

            # GitHub CLI pre-requisites
            # https://github.com/cli/cli/blob/trunk/docs/install_linux.md
            if [[ ! $(apt-key finger --fingerprint C99B11DEB97541F0 2>/dev/null) ]]; then
                $SUDO apt-key adv --keyserver keyserver.ubuntu.com --recv-key C99B11DEB97541F0
            fi
            $SUDO apt-add-repository https://cli.github.com/packages

            # Required for Midnight Commander
            $SUDO add-apt-repository universe

            # For Ubuntu, this PPA provides the latest stable upstream Git version
            $SUDO add-apt-repository ppa:git-core/ppa -y

            # Microsoft dependencies
            # Source: https://github.com/Azure/azure-functions-core-tools
            curl -s https://packages.microsoft.com/keys/microsoft.asc | $SUDO apt-key add -
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
                curl -s https://packages.microsoft.com/config/ubuntu/${DISTRIB_RELEASE}/prod.list | $SUDO tee /etc/apt/sources.list.d/microsoft-prod.list
                wget -q https://packages.microsoft.com/config/ubuntu/${DISTRIB_RELEASE}/packages-microsoft-prod.deb
                $SUDO dpkg -i packages-microsoft-prod.deb
            fi

            echo $'\nUpdating package list...'
            $SUDO apt-get update

            # FIX: Could not get lock /var/lib/dpkg/lock-frontend - open (11: Resource temporarily unavailable)
            # Upgrade packages only when not running from cloud-init
            if [[ $(pstree -pls $$) != *"cloud-init"* ]]; then
                echo $'\nUpgrading packages...'
                $SUDOEULA apt-get upgrade -y
            fi

            echo $'\nInstalling new packages...'
            INSTALLED_PACKAGES=$(mktemp)
            NEW_PACKAGES=$(mktemp)
            dpkg -l | grep ^ii | awk '{print $2}' >$INSTALLED_PACKAGES
            grep -Fvx -f $INSTALLED_PACKAGES ./apt-packages.txt >$NEW_PACKAGES
            while read package; do 
                $SUDOEULA apt-get install -y $package
            done < $NEW_PACKAGES
            rm $INSTALLED_PACKAGES $NEW_PACKAGES
        fi
    fi
fi

# PowerShell
if test ! $(which pwsh); then
    echo $'\nPowerShell Core (pwsh) not found, skipping setup'
else
    echo $'\nSetting up PowerShell Core...'
    pwsh -nop -file $SCRIPT_PATH/../common/common_setup.ps1 $COMMON_SETUP_ARGS
fi

# Set up terraform with tfenv
if test $(which unzip); then
    if [ ! -d $HOME/.tfenv ]; then
        echo $'\nInstalling tfenv...'
        git clone -q https://github.com/tfutils/tfenv.git $HOME/.tfenv
        echo 'export PATH="$HOME/.tfenv/bin:$PATH"' >> ~/.bash_profile
        sudo ln -s ~/.tfenv/bin/* /usr/local/bin
        echo 'trust-tfenv: yes' > ~/.tfenv/use-gpgv
    else
        echo $'\nUpdating tfenv...'
        git -C $HOME/.tfenv pull
    fi
    TFENV_CURL_OUTPUT=0
    $HOME/.tfenv/bin/tfenv install latest 2>&1
    $HOME/.tfenv/bin/tfenv use latest 2>&1
else
    echo $'\nunzip not found, skipping tfenv set up'
fi
