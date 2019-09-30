#!/usr/bin/env bash
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

#uninstall existing clv if any
if [[ -e ~/.bash_profile ]] && grep -q "#ADDED BY CLV INSTALLER#" ~/.bash_profile; then
    ./uninstall.sh
fi

#install clv
mkdir ~/.clv
cp -r "$SCRIPTPATH/commands/" ~/.clv
touch ~/.bash_profile
echo "export PATH=\"~/.clv:$PATH\" #ADDED BY CLV INSTALLER#" > ~/.bash_profile

echo "clv has been installed successfully!"