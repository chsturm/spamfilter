#!/bin/bash

launchagent_flag=$1
interval=$2
script_dir="$HOME/Library/Application Scripts/com.apple.mail"
rules_file="spamfilter-rules.json"
launchagent_file="com.github.chsturm.spamfilter.plist"
launchagent_path="$HOME/Library/LaunchAgents/$launchagent_file"

# copy spamfilter script
cp spamfilter.scpt $script_dir

# copy filter rules file
if [ -e "$script_dir/$rules_file" ]
then
    echo "Overwrite existing $rules_file? (y/n)"
    read user_input
    if [ $user_input == "y" ]
    then
        cp $rules_file $script_dir
    fi
else
    cp $rules_file $script_dir
fi


# create launch agent
if [ $# -gt 0 ] && [ $launchagent_flag == "-launchagent" ]
then
    echo "Setting up launch agent"
    cp $launchagent_file "$HOME/Library/LaunchAgents"
    sed -i "" "s+HOME_DIR+$HOME+g" $launchagent_path
    
    # configure launch interval in seconds
    itvl=900
    if [ $# -eq 2 ] && [ $interval -gt 0 ]
    then
        itvl=$interval
    fi
    sed -i "" "s+LAUNCH_INTERVAL+$itvl+g" $launchagent_path
    
    launchctl load -w $launchagent_path
fi