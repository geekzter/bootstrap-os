#!/usr/bin/env bash

# Installs in $HOME/src/bootstrap-os
# curl -sk https://raw.githubusercontent.com/geekzter/bootstrap-os/master/linux/bootstrap_linux.sh | bash

SCRIPT_PATH=`dirname $0`

if [ "$EUID" = "0" ]; then
    CANELEVATE='true'
    SUDO=''
elif test $(which sudo); then
    CANELEVATE='true'
    SUDO='sudo'
else
    CANELEVATE='false'
fi

if [ "$CANELEVATE" = "true" ]; then
    if test ! $(which git); then
        if test $(which apt-get); then
            $SUDO apt-get install git -y
        elif test $(which yum); then
            $SUDO yum install git -y
        elif test $(which zypper); then
            $SUDO zypper install git -y
        else
            echo $'\nGit not found, exiting'
            exit 1
        fi
    fi
fi

echo $'\nLooking for repository...'
if [ -t 0 ]; then
    # Not invoked using cat/curl/wget
    # Test whether we are part of a repository
    if [ -d $SCRIPT_PATH/../.git ]; then
        echo "We're in repository at $(cd $SCRIPT_PATH/.. && pwd), updating..."
        git -C $SCRIPT_PATH/.. pull

        # Done, spawn 2nd stage
        pushd ${SCRIPT_PATH} >/dev/null
        . ${SCRIPT_PATH}/bootstrap_linux2.sh "$@"
        popd >/dev/null
        exit
    fi
fi

if [ ! -d $HOME/src ]; then
    mkdir $HOME/src
fi
if [ ! -d $HOME/src/bootstrap-os ]; then
    echo "Repository does not exist, creating at $HOME/src/bootstrap-os..."
    git clone https://github.com/geekzter/bootstrap-os $HOME/src/bootstrap-os
else 
    echo "Repository found at $(cd $HOME/src/bootstrap-os && pwd), updating..."
    git -C $HOME/src/bootstrap-os pull
fi
pushd $HOME/src/bootstrap-os/linux >/dev/null
. $HOME/src/bootstrap-os/linux/bootstrap_linux2.sh "$@"
popd >/dev/null