#!/usr/bin/env bash
SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"

# --- uninstall existing clv if any --- #
if [[ -e ~/.bash_profile ]] && grep -q "#ADDED BY CLV INSTALLER#" ~/.bash_profile; then
    ./uninstall.sh
fi

# --- install clv --- #
mkdir ~/.clv
mkdir ~/.clv/bin
cp -r "$SCRIPTPATH/bin/" ~/.clv/bin
touch ~/.bash_profile
echo "export PATH=\"~/.clv/bin:\$PATH\" #ADDED BY CLV INSTALLER#" > ~/.bash_profile

# --- install clv commands --- #

for cmd in "$SCRIPTPATH/bin"/*
do
  "$cmd" CLV_ENV_SETUP
done

echo "clv has been installed successfully!"