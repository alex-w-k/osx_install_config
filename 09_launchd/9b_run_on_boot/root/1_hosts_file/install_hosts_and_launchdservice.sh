#!/bin/bash

###
### asking password upfront
###

# function for reading secret string (POSIX compliant)
enter_password_secret()
{
    # read -s is not POSIX compliant
    #read -s -p "Password: " SUDOPASSWORD
    #echo ''
    
    # this is POSIX compliant
    # disabling echo, this will prevent showing output
    stty -echo
    # setting up trap to ensure echo is enabled before exiting if the script is terminated while echo is disabled
    trap 'stty echo' EXIT
    # asking for password
    printf "Password: "
    # reading secret
    read -r "$@" SUDOPASSWORD
    # reanabling echo
    stty echo
    trap - EXIT
    # print a newline because the newline entered by the user after entering the passcode is not echoed. This ensures that the next line of output begins at a new line.
    printf "\n"
    # making sure builtin bash commands are used for using the SUDOPASSWORD, this will prevent showing it in ps output
    # has to be part of the function or it wouldn`t be updated during the maximum three tries
    #USE_PASSWORD='builtin echo '"$SUDOPASSWORD"''
    USE_PASSWORD='builtin printf '"$SUDOPASSWORD\n"''
}

# unset the password if the variable was already set
unset SUDOPASSWORD

# making sure no variables are exported
set +a

# asking for the SUDOPASSWORD upfront
# typing and reading SUDOPASSWORD from command line without displaying it and
# checking if entered password is the sudo password with a set maximum of tries
NUMBER_OF_TRIES=0
MAX_TRIES=3
while [ "$NUMBER_OF_TRIES" -le "$MAX_TRIES" ]
do
    NUMBER_OF_TRIES=$((NUMBER_OF_TRIES+1))
    #echo "$NUMBER_OF_TRIES"
    if [ "$NUMBER_OF_TRIES" -le "$MAX_TRIES" ]
    then
        enter_password_secret
        ${USE_PASSWORD} | sudo -k -S echo "" > /dev/null 2>&1
        if [ $? -eq 0 ]
        then 
            break
        else
            echo "Sorry, try again."
        fi
    else
        echo ""$MAX_TRIES" incorrect password attempts"
        exit
    fi
done

# setting up trap to ensure the SUDOPASSWORD is unset if the script is terminated while it is set
trap 'unset SUDOPASSWORD' EXIT

# replacing sudo command with a function, so all sudo commands of the script do not have to be changed
sudo()
{
    ${USE_PASSWORD} | builtin command sudo -p '' -k -S "$@"
    #${USE_PASSWORD} | builtin command -p sudo -p '' -k -S "$@"
    #${USE_PASSWORD} | builtin exec sudo -p '' -k -S "$@"
}



###
### installing and running hostsfile updater
### 

# script directory
SCRIPT_DIR=$(echo "$(cd "${BASH_SOURCE[0]%/*}" && pwd)")
#echo $SCRIPT_DIR

# uninstalling possible old files
echo "uninstalling possible old files..."
. "$SCRIPT_DIR"/launchd_and_script/uninstall_hosts_and_launchdservice.sh
wait

# hosts install / update file
echo "installing hosts update script..."
sudo mkdir -p /Library/Scripts/custom/
sudo cp "$SCRIPT_DIR"/launchd_and_script/hosts_file_generator.sh /Library/Scripts/custom/hosts_file_generator.sh
sudo chown -R root:wheel /Library/Scripts/custom/
sudo chmod -R 755 /Library/Scripts/custom/

# launchd service file
echo "installing launchd service..."
sudo cp "$SCRIPT_DIR"/launchd_and_script/com.hostsfile.install_update.plist /Library/LaunchDaemons/com.hostsfile.install_update.plist
sudo chown root:wheel /Library/LaunchDaemons/com.hostsfile.install_update.plist
sudo chmod 644 /Library/LaunchDaemons/com.hostsfile.install_update.plist

# forcing update on next run by setting last modification time of /etc/hosts earlier
sudo touch -mt 201512010000 /etc/hosts

# run installation
echo "installing and running hosts file generator..."

# has to be run as root because sudo cannot write to logfile with root priviliges for the function with sudo tee
# otherwise the privileges of the logfile would have to be changed before running inside the script
# sudo privileges inside the called script will not timeout
# script will run as root later anyway
echo ''
sudo bash -c "/Library/Scripts/custom/hosts_file_generator.sh" &
wait < <(jobs -p)

# launchd service
echo ""
echo "enabling launchd service..."
if [[ $(sudo launchctl list | grep hostsfile.install_update) != "" ]];
then
    sudo launchctl unload /Library/LaunchDaemons/com.hostsfile.install_update.plist
    sudo launchctl disable system/com.hostsfile.install_update
else
    :
fi
sudo launchctl enable system/com.hostsfile.install_update
sudo launchctl load /Library/LaunchDaemons/com.hostsfile.install_update.plist
echo "checking if launchd service is enabled..."
sudo launchctl list | grep hostsfile.install_update
#echo ""
#echo "waiting 60s for updating in background..."
#sleep 60
#ls -la /etc/hosts

# hosts filesize
#du -h /etc/hosts

echo "opening /etc/hosts and logfile..."
#nano /etc/hosts
open /etc/hosts
#nano /var/log/hosts_file_update.log
open /var/log/hosts_file_update.log

# syncing to install latest version when using backup script
echo ''
echo "copying script to backup script dir..."
SCRIPTS_FINAL_DIR=$(echo "$(cd "${BASH_SOURCE[0]%/*}" && cd .. && cd .. && cd .. && cd .. && pwd)")
if [[ -e "$SCRIPTS_FINAL_DIR"/07_backup_and_restore_script ]]
then
    mkdir -p "$SCRIPTS_FINAL_DIR"/07_backup_and_restore_script/update_hosts
    cp "$SCRIPT_DIR"/launchd_and_script/hosts_file_generator.sh "$SCRIPTS_FINAL_DIR"/07_backup_and_restore_script/update_hosts/hosts_file_generator.sh
else
	echo ""$SCRIPTS_FINAL_DIR"/07_backup_and_restore_script not found, skipping copying file to backup script directory..."
fi


echo ''
echo 'done ;)'
echo ''

###
### unsetting password
###

unset SUDOPASSWORD

