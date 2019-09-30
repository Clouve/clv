#!/usr/bin/env bash
rm -rf ~/.clv
if grep -q "#ADDED BY CLV INSTALLER#" ~/.bash_profile; then
    sed -i.bak '/#ADDED BY CLV INSTALLER#/d' ~/.bash_profile
else
    echo "WARNING: Couldn't remove some lines added by clv installer."
fi

echo "clv has been uninstalled successfully!"