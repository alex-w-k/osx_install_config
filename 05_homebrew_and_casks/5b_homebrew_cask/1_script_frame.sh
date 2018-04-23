#!/bin/bash

###
### asking password upfront
###

if [[ "$SUDOPASSWORD" != "" ]]
then
    #USE_PASSWORD='builtin printf '"$SUDOPASSWORD\n"''
    :
elif [[ -e /tmp/run_from_backup_script3 ]] && [[ $(cat /tmp/run_from_backup_script3) == 1 ]]
then
    function delete_tmp_backup_script_fifo3() {
        if [ -e "/tmp/tmp_backup_script_fifo3" ]
        then
            rm "/tmp/tmp_backup_script_fifo3"
        else
            :
        fi
        if [ -e "/tmp/run_from_backup_script3" ]
        then
            rm "/tmp/run_from_backup_script3"
        else
            :
        fi
    }
    unset SUDOPASSWORD
    SUDOPASSWORD=$(cat "/tmp/tmp_backup_script_fifo3" | head -n 1)
    USE_PASSWORD='builtin printf '"$SUDOPASSWORD\n"''
    delete_tmp_backup_script_fifo3
    #set +a
else
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
    
fi

# setting up trap to ensure the SUDOPASSWORD is unset if the script is terminated while it is set
trap 'unset SUDOPASSWORD' EXIT

# replacing sudo command with a function, so all sudo commands of the script do not have to be changed
sudo()
{
    ${USE_PASSWORD} | builtin command sudo -p '' -k -S "$@"
    #${USE_PASSWORD} | builtin command -p sudo -p '' -k -S "$@"
    #${USE_PASSWORD} | builtin exec sudo -p '' -k -S "$@"
}

# redefining sudo so it is possible to run homebrew install without entering the password again
sudo()
{
    ${USE_PASSWORD} | builtin command sudo -p '' -S "$@"
}

# trapping script to kill subprocesses when script is stopped
# kill -9 can only be silenced with >/dev/null 2>&1 when wrappt into function
function kill_subprocesses() 
{
    # kills subprocesses only
    pkill -9 -P $$
}

function kill_main_process() 
{
    # kills subprocesses and process itself
    exec pkill -9 -P $$
}

function unset_variables() {
    unset SUDOPASSWORD
    unset SUDO_PID
    unset CHECK_IF_CASKS_INSTALLED
    unset CHECK_IF_FORMULAE_INSTALLED
    unset INSTALLATION_METHOD
    unset KEEPINGYOUAWAKE
}

function start_sudo() {
    ${USE_PASSWORD} | builtin command sudo -p '' -S -v
    ( while true; do ${USE_PASSWORD} | builtin command sudo -p '' -S -v; sleep 60; done; ) &
    SUDO_PID="$!"
}

function stop_sudo() {
    if [[ $(echo $SUDO_PID) == "" ]]
    then
        :
    else
        if ps -p $SUDO_PID > /dev/null
        then
            sudo kill -9 $SUDO_PID &> /dev/null
            wait $SUDO_PID 2>/dev/null
        else
            :
        fi
    fi
    unset SUDO_PID
    sudo -k
}

function activating_keepingyouawake() {
if [ -e /Applications/KeepingYouAwake.app ]
then
    #echo ''
	echo "activating keepingyouawake..."
    KEEPINGYOUAWAKE="active"
	open -g /Applications/KeepingYouAwake.app
    open -g keepingyouawake:///activate
else
        :
fi
}

function deactivating_keepingyouawake() {
if [ -e /Applications/KeepingYouAwake.app ]
then
    echo "deactivating keepingyouawake..."
    KEEPINGYOUAWAKE=""
    open -g /Applications/KeepingYouAwake.app
    open -g keepingyouawake:///deactivate
else
    :
fi
}

#SCRIPT_DIR=$(echo "$( cd "${BASH_SOURCE[0]%/*}" && pwd)")


### trapping
#trap "unset SUDOPASSWORD; printf '\n'; echo 'killing subprocesses...'; kill_subprocesses >/dev/null 2>&1; deactivating_keepingyouawake >/dev/null 2>&1; echo 'done'; echo 'killing main process...'; kill_main_process" SIGHUP SIGINT SIGTERM
trap "stop_sudo; unset_variables; printf '\n'; stty sane; pkill ruby; kill_subprocesses >/dev/null 2>&1; kill_main_process" SIGHUP SIGINT SIGTERM
# kill main process only if it hangs on regular exit
trap "stop_sudo; unset_variables; stty sane; kill_subprocesses >/dev/null 2>&1; deactivating_keepingyouawake >/dev/null 2>&1; exit; kill_main_process" EXIT
#set -e



### checking if online
echo ''
echo "checking internet connection..."
ping -c 3 google.com > /dev/null 2>&1
if [ $? -eq 0 ]
then
    echo "we are online, running script..."
    #echo ''   
else
    echo "not online, exiting..."
    echo ''
    exit
fi


### more variables
# keeping hombrew from updating each time brew install is used
HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_AUTO_UPDATE
# number of max parallel processes
NUMBER_OF_CORES=$(sysctl hw.ncpu | awk '{print $NF}')
NUMBER_OF_MAX_JOBS=$(echo "$NUMBER_OF_CORES * 1.0" | bc -l)
#echo $NUMBER_OF_MAX_JOBS
#NUMBER_OF_MAX_JOBS_ROUNDED=$(awk 'BEGIN { printf("%.0f\n", '"$NUMBER_OF_MAX_JOBS"'); }')
# due to connection issues with too many downloads at the same time limiting the maximum number of jobs for now
NUMBER_OF_MAX_JOBS_ROUNDED=4
#echo $NUMBER_OF_MAX_JOBS_ROUNDED


### checking if command line tools are installed
function checking_command_line_tools() {
    if xcode-select -print-path >/dev/null 2>&1 && [[ -e "$(xcode-select -print-path)" ]] && [[ -nz "$(ls -A "$(xcode-select -print-path)")" ]]
    then
      	#echo command line tools are installed...
      	:
    else
    	#echo command line tools are not installed, installing...
    	# prompting the softwareupdate utility to list the command line tools
        if [[ -e "$SCRIPT_DIR"/2_command_line_tools.sh ]]
        then
            . "$SCRIPT_DIR"/2_command_line_tools.sh
        else
            echo ''
            echo "command line tools and install script are missing, exiting..."
            echo ''
            exit
        fi
    fi
}
# done in scripts
#checking_command_line_tools


### checking if parallel is installed
function checking_parallel() {
    if [[ "$(which parallel)" == "" ]]
    then
        # parallel is not installed
        INSTALLATION_METHOD="sequential"
    else
        # parallel is installed
        INSTALLATION_METHOD="parallel"
    fi
    #echo ''
    echo INSTALLATION_METHOD is "$INSTALLATION_METHOD"...
    echo ''
}
# done in scripts
#checking_parallel


### checking if homebrew is installed
function checking_homebrew() {
    if [[ $(which brew) == "" ]]
    then        
        if [[ -e "$SCRIPT_DIR"/3_homebrew_caskbrew.sh ]]
        then
            . "$SCRIPT_DIR"/3_homebrew_caskbrew.sh
        else
            echo ''
            echo "homebrew and install script are missing, exiting..."
            echo ''
            exit
        fi
    else
        #echo "homebrew is installed..."
        :
    fi
}
# done in scripts
#checking_homebrew