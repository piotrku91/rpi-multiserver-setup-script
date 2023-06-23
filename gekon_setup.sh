#!/bin/bash

USERNAME=${1}
########################################################################### FUNCTIONS ####################################################################
##########################################################################################################################################################
function handle_error()
{
    # Colors table
    RED='\033[1;31m'
    DARKBLUE='\033[0;94m'
    NOCOLOR='\033[0m'

    FUNC_ARG=$1
    echo -e "${RED}Error: ${DARKBLUE}$FUNC_ARG.${RED} Script stopped.${NOCOLOR}"
    exit 1
}

function verify_root_permissions () {
    USER_ID=$(id -u)
    if [[ USER_ID -ne 0 ]]; then
        handle_error "Script should be executed with root permissions"
fi
}

function get_username () {
if [[ $USERNAME == "" ]]; then
    read -p 'Username: ' USERNAME
fi

echo "Choosen username: $USERNAME"

USEREXISTS=$(grep $USERNAME /etc/passwd | wc -l)
if [ "$USEREXISTS" -eq 0 ]; then
    read -p 'User not exists. Do you want to create this user? ' OK

        if [ $OK == "y" ]; then
            echo "Hello ${USERNAME}. Now, We create new account..."
            useradd -m -r ${USERNAME}
            passwd ${USERNAME}
            usermod -aG sudo ${USERNAME}
        else
            handle_error "Unknown user..."
        fi
fi
echo "Ok user $USERNAME exists..."
}

function update_upgrade_install_tools () {
    echo "Update & upgrade..."
    apt update
    apt full-upgrade

    TOOLS="vim git ufw bindfs"

    echo "Install editors and tools..."
    apt-get install -y ${TOOLS} | handle_error "Some packages are not installed correctly..."
}

function enable_firewall_setup () {
    read -p 'Do you want enable firewall? ' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "Enabling firewall..."

        # Firewall preconfig
        ufw allow 22/tcp | handle_error "Some error. Check if ufw is installed..."
        ufw enable 
    fi
}

function ftp_server_setup () {
    read -p 'Do you want install FTP server and configure it? ' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "Setup ftp server..."

        apt-get install -y vsftpd | handle_error "vsftpd are not installed correctly..."
        chown root:root /home/${USERNAME}
        mkdir -p /home/${USERNAME}/FTP/files
        chmod a-w /home/${USERNAME}/FTP
        chown ${USERNAME}:${USERNAME} /home/${USERNAME}/FTP/files

        # Reconfiguration
        cp configs/ftp/certs/vsftpd.crt /etc/ssl/certs/vsftpd.crt | handle_error "Missing prepared cert files... Generate keys first and copy to configs/ftp/certs/ directory"
        cp configs/ftp/certs/private/vsftpd.key /etc/ssl/private/vsftpd.key | handle_error "Missing prepared cert files... Generate keys first and copy to configs/ftp/certs/ directory"

        cp /etc/vsftpd.conf /etc/vsftpd.conf.back # Create backup
        cp configs/ftp/vsftpd.conf /etc/vsftpd.conf # Replace by pre-configured file
        echo "${USERNAME}" | sudo tee -a /etc/vsftpd.userlist

        ufw allow 20:21/tcp # Open port in firewall
        ufw allow 990/tcp
        ufw allow 35000:40000/tcp
        sudo service vsftpd restart # Restart server
    fi
}

function usb_folder_binding_setup () {
    read -p 'Do you want bind usb device to FTP folder ?' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "Usb device access..."
        
        read -p "Connect USB device and type any key..."
        blkid # Listing block devices
        read -p 'UUID for USB device: ' DEV_UUID
        read -p 'Filestystem for USB device: ' DEV_FILESYSTEM
        read -p 'Mountpoint for USB device: ' DEV_MOUNTPOINT
        read -p 'Chmod for ftp files folder: (default: 0750): ' DEV_CHMOD
        if [[ $HTML_CHMOD = "" ]]; then
            echo "Using default chmod..."
            HTML_MOUNTPOINT="0750"
        fi

        mkdir -p ${DEV_MOUNTPOINT}

        LINE_TO_ADD1="UUID=${DEV_UUID} ${DEV_MOUNTPOINT} ${DEV_FILESYSTEM} defaults,auto,users,rw,nofail,umask=000 0 0"
        LINE_TO_ADD2="${DEV_MOUNTPOINT} /home/${USERNAME}/FTP/files fuse.bindfs force-user=${USERNAME},force-group=${USERNAME},perms=${DEV_CHMOD} 0 0"

        cp /etc/fstab /etc/fstab.back # Create backup

        echo "${LINE_TO_ADD1}" >> /etc/fstab
        echo "${LINE_TO_ADD2}" >> /etc/fstab
        
        cat /etc/fstab

        read -p 'Is it OK? Make sure! ' OK

        if [ $OK == "n" ]; then
            cp /etc/fstab.back /etc/fstab # Create backup
            echo "/etc/fstab backuped!"
        else
        echo "/etc/fstab ~- line added!"
        fi
    fi
}

function apache_install_and_bind_setup () {
    read -p 'Do you want to install apache and bind folders ?' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "Apache installation..."

        apt-get install apache2 -y | handle_error "apache2 are not installed correctly..."
        rm -rf /var/www/html/*

        usermod -a -G www-data ${USERNAME}

        chown -R www-data:www-data /var/www
        chmod go+x /var/www
        chmod -R go-rwx /var/www
        chmod -R g+rx /var/www
        chmod -R g+rwx /var/www

        read -p 'Mountpoint for HTML folder device (default: /mnt/usb0/www_files): ' HTML_MOUNTPOINT
        if [[ $HTML_MOUNTPOINT = "" ]]; then
            echo "Using default..."
            HTML_MOUNTPOINT="/mnt/usb0/www_files"
        fi

        read -p 'Chmod for html folder: (default: 0750): ' HTML_CHMOD
        if [[ $HTML_CHMOD = "" ]]; then
            echo "Using default chmod..."
            HTML_CHMOD="0750"
        fi

        LINE_TO_ADD1="${HTML_MOUNTPOINT} /var/www/html fuse.bindfs force-user=www-data,force-group=www-data, perms=${HTML_CHMOD} 0 0"
        cp /etc/fstab /etc/fstab.back # Create backup

        echo "${LINE_TO_ADD1}" >> /etc/fstab
        cat /etc/fstab

        read -p 'Is it OK? Make sure! ' OK
        if [ $OK == "n" ]; then
            cp /etc/fstab.back /etc/fstab # Create backup
            echo "/etc/fstab backuped!"
        else
            echo "/etc/fstab ~- line added!"
            ufw allow 80
        fi
    fi
}

function php_setup () {
    read -p 'Do you want to install php ?' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "PHP installation..."
        apt-get install php7.4 libapache2-mod-php7.4 php7.4-mbstring php7.4-mysql php7.4-curl php7.4-gd php7.4-zip -y | handle_error "Some packages are not installed correctly..."

        echo "<?php echo \"Today's date is \".date('Y-m-d H:i:s');?>" >> /var/www/html/php_test.php
    fi
}

function show_menu ()
{
    #clear
    echo "****************************************************************************************"
    echo "*                     RPI MULTISERVER SETUP SCRIPT BY PIOTRQ                           *"
    echo "****************************************************************************************"
    echo "Current user: ${USERNAME}"
    echo "****************************************************************************************"
    echo "0 - Update / Upgrade / Install tools"
    echo "1 - Enable firewall"
    echo "2 - Install FTP Server (use once)"
    echo "3 - Install USB device and bind to FTP user folder"
    echo "4 - Install Apache and bind to FTP user folder (use once)"
    echo "5 - Install PHP"
    echo "exit - Exit script"
    echo ""

}

########################################################################### MAIN RUNTIME #################################################################
##########################################################################################################################################################

echo "This is multiserver rpi setup script by PiotrQ"
echo "Tested on RPI 2 / Linux kernel 6.1.21-v7+ / Raspbian GNU/Linux 11"

verify_root_permissions
get_username

while [[ True ]]; do
    show_menu
    read INPUT

    case $INPUT in
        0)
            update_upgrade_install_tools
            ;;
        1)
            enable_firewall_setup
            ;;
        2)
            ftp_server_setup
            ;;
        3)
            usb_folder_binding_setup
            ;;
        4)
            apache_install_and_bind_setup
            ;;
        5)
            php_setup
            ;;
        exit)
            break
            ;;

        *)
        echo "Incorrect command."
        ;;
  
    esac
read -p "Type any key to continue..."
done
