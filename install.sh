#!/bin/bash

launchagent_flag=$1
interval=$2
script_dir="$HOME/Library/Application Scripts/com.apple.mail"
rules_file="spamfilter-rules.json"
launchagent_file="com.github.chsturm.spamfilter.plist"
launchagent_path="$HOME/Library/LaunchAgents/$launchagent_file"
ctl_file="spamfilterctl.sh"

# copy spamfilter script
cp spamfilter.scpt $script_dir

# copy filter rules file
if [ -e "$script_dir/$rules_file" ]
then
    echo "Overwrite existing $rules_file? (y/n)"
    read user_input
    if [ $user_input == "y" ]
    then
        echo "Yes"
        cp $rules_file $script_dir
    fi
else
    cp $rules_file $script_dir
fi


# create launch agent
if [ $# -gt 0 ] && [ "$launchagent_flag" == "-launchagent" ]
then
    echo "Setting up launch agent"
    cp $launchagent_file "$HOME/Library/LaunchAgents"
    sed -i "" "s+HOME_DIR+$HOME+g" $launchagent_path
    
    # configure launch interval in seconds
    itvl=900
    if [ $# -eq 2 ] && [ $interval -gt 0 ]
    then
        echo "Use custom launch interval"
        itvl=$interval
    fi
    sed -i "" "s+LAUNCH_INTERVAL+$itvl+g" $launchagent_path
    
    launchctl load -w $launchagent_path
fi


# install spamfilterctl.sh as shortcut for CLI mode
echo "Copy $ctl_file to /usr/local/bin as CLI mode shortcut? (y/n)"
read user_input
if [ $user_input == "y" ]
then
    echo "Root privileges required"
    sudo cp $ctl_file /usr/local/bin && sudo chmod a+x "/usr/local/bin/$ctl_file"
fi
