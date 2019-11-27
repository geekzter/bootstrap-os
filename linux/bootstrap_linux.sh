#!/usr/bin/env bash
# curl -sk https://raw.githubusercontent.com/geekzter/bootstrap-os/master/linux/bootstrap_linux.sh | bash

SCRIPTPATH=`dirname $0`

if test ! $(which git); then
    echo $'\nGit not found, exiting'
    exit 1
fi

# Test whether we are part of a cloned repository
descriptionFile=$(dirname $SCRIPTPATH)/../.git/description
if [ -f $descriptionFile ]; then
    if grep -q bootstrap-os "$descriptionFile"; then
        echo "Repository exists at $(cd $SCRIPTPATH/.. && pwd)"
        git -C .. pull

        # Done, spawn 2nd stage
        . ${SCRIPTPATH}/bootstrap_linux2.sh $0
        exit
    fi
fi

echo "Repository does not exist, creating at ~/src/bootstrap-os..."
if [ ! -d ~/src ]; then
    mkdir ~/src
fi
if [ ! -d ~/src/bootstrap-os ]; then
    git clone https://github.com/geekzter/bootstrap-os ~/src/bootstrap-os
else 
    git -C ~/src/bootstrap-os pull
fi

. ${SCRIPTPATH}/bootstrap_linux2.sh $0