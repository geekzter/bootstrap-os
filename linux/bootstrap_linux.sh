#!/usr/bin/env bash

# Installs in ~/src/bootstrap-os
# curl -sk https://raw.githubusercontent.com/geekzter/bootstrap-os/master/linux/bootstrap_linux.sh | bash

SCRIPT_PATH=`dirname $0`

if test ! $(which git); then
    if test $(which apt-get); then
        sudo apt-get install git -y
    elif test $(which yum); then
        sudo yum install git -y
    elif test $(which zypper); then
        sudo zypper install git -y
    else
        echo $'\nGit not found, exiting'
        exit 1
    fi
fi
echo $'\nLooking for repository...'

if [ -t 0 ]; then
    # Not invoked using cat/curl/wget
    # Test whether we are part of a cloned repository
    descriptionFile=$SCRIPT_PATH/../.git/description
    if [ -f $descriptionFile ]; then
        if grep -q bootstrap-os "$descriptionFile"; then
            echo "Repository exists at $(cd $SCRIPT_PATH/.. && pwd), updating..."
            git -C $SCRIPT_PATH/.. pull

            # Done, spawn 2nd stage
            . ${SCRIPT_PATH}/bootstrap_linux2.sh "$@"
            exit
        fi
    fi
fi

if [ ! -d ~/src ]; then
    mkdir ~/src
fi
if [ ! -d ~/src/bootstrap-os ]; then
    echo "Repository does not exist, creating at ~/src/bootstrap-os..."
    git clone https://github.com/geekzter/bootstrap-os ~/src/bootstrap-os
else 
    echo "Repository exists at $(cd ~/src/bootstrap-os && pwd), updating..."
    git -C ~/src/bootstrap-os pull
fi
pushd ~/src/bootstrap-os/linux
. ./bootstrap_linux2.sh "$@"
popd