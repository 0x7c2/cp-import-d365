#!/bin/bash -f
source /opt/CPshrd-R80.40/tmp/.CPprofile.sh
#
# Copyright 2021 by by 0x7c2, Simon Brecht.
# All rights reserved.
# This file is used to automaticly import cognos d365 ip addresses,
# and is released under the "Apache License 2.0". Please see the LICENSE
# file that should have been included as part of this package.
#
#
# Script settings
script_path=/tmp
script_name="Cognos Importer"
script_tmp="$script_path/dig.tmp"
#
#------------------------------------------------------------------------------------
#
# Policy and Target configuration
fw_policy=Standard
fw_target=MyFirewallObj
#
#------------------------------------------------------------------------------------
#
# Object settings
obj_group=d365-cognos
obj_prefix=d365-cognos-host-
obj_comment="[$script_name] Do NOT use this object. Automatically created and deleted!"
obj_color=red
#
#------------------------------------------------------------------------------------
#
# API Credentials
api_user=apiuser-cognos
api_pass=password
#
#------------------------------------------------------------------------------------
#
#Time
time=$(date "+%Y.%m.%d-%H.%M.%S")
#
#------------------------------------------------------------------------------------
api_changed=no
#------------------------------------------------------------------------------------
#
function logme ( ) {
    time=$(date "+%Y.%m.%d-%H.%M.%S")
    echo "$time - $script_name - $1"
}
#
#------------------------------------------------------------------------------------
echo
echo "################## $script_name starts : $time ##################"
#------------------------------------------------------------------------------------
#
# Download of Feed
#
logme "Downloading Feed/Resolving DNS Names..."
for h in d365sqlcognos.database.windows.net cognossql.database.windows.net; do
    rm -rf $script_tmp
    dig +short "$h" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' >> $script_tmp
done
#------------------------------------------------------------------------------------
#
# Login to Management Server
#
logme "Login to Management Server..."
mgmt_cli login --user $api_user --password $api_pass --format json > id.txt
#------------------------------------------------------------------------------------
#
# Check if $obj_group exists
#
if mgmt_cli show group name "$obj_group" --format json -s id.txt | grep -q 'generic_err_object_not_found'; then
    logme "Group $obj_group does not exist. Creating ..."
    mgmt_cli add group name "$obj_group" color "$obj_color" comments "$obj_comment" -s id.txt
    api_changed=yes
else
    logme "group $obj_group already exists"
fi
#------------------------------------------------------------------------------------
#
# Check for cleanup old objects in database
#
logme "Checking for cleanup old objects in database"
mgmt_cli show group name "$obj_group" --format json -s id.txt | grep $obj_prefix | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | while read line; do
    if [ "`grep -c "$line" $script_tmp`" == "0" ]; then
        # old stuff, remove it
        logme "--> Removing $obj_prefix$line from database..."
        mgmt_cli -s id.txt delete host name "$obj_prefix$line" ignore-warnings "true"
        api_changed=yes
    else
        # existing stuff, remove from creating process
        logme "--> Object $obj_prefix$line already in database, skipping..."
        sed -i -n "/$line/!p" $script_tmp
    fi
done
#------------------------------------------------------------------------------------
#
# Create new objects and add them to group
#
logme "Creating new objects and add them to group"
cat $script_tmp | sort | uniq | while read line; do
    logme "--> Adding $obj_prefix$line ($line) as object"
    mgmt_cli -s id.txt add host name "$obj_prefix$line" color "$obj_color" groups.1 "$obj_group" comments "$obj_comment" ipv4-address "$line"
done
if [ "`cat $script_tmp | wc -l`" != "0" ]; then
    api_changed=yes
fi
#------------------------------------------------------------------------------------
#
if [ "$api_changed" == "yes" ]; then
    logme "Objects changed, publishing session!"
    mgmt_cli publish -s id.txt
    logme "Policy Installation needed; installing on $fw_target ..."
    mgmt_cli install-policy policy-package "$fw_policy" access true threat-prevention false targets.1 "$fw_target" -s id.txt
else
    logme "No changes, discarding session!"
    mgmt_cli discard -s id.txt
fi
#------------------------------------------------------------------------------------
logme "Performing session logout..."
mgmt_cli logout -s id.txt
logme "Cleanup temp files..."
rm id.txt
rm $script_tmp
#
echo "################## $script_name ends : $time ##################"
echo
