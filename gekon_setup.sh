#!/bin/bash
 echo "This is multiserver rpi setup script by PiotrQ"
 echo "Tested on RPI 2 / Linux kernel 6.1.21-v7+ / Raspbian GNU/Linux 11"

########################################################################### FUNCTIONS ####################################################################
##########################################################################################################################################################

function update_upgrade_install_tools() {
    echo "Update & upgrade..."
    apt update
    apt full-upgrade

    TOOLS="vim git ufw bindfs"

    echo "Install editors and tools..."
    apt-get install -y ${TOOLS}
}

##### ENABLE FIREWALL
function enable_firewall_setup () {
    read -p 'Do you want enable firewall? ' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "Enabling firewall..."

        # Firewall preconfig
        ufw allow 22/tcp
        ufw enable 
    fi
}

##### FTP SERVER SECTION
function ftp_server_setup () {
    read -p 'Do you want install FTP server and configure it? ' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "Setup ftp server..."

        apt-get install -y vsftpd 
        chown root:root /home/${NEWUSERNAME}
        mkdir -p /home/${NEWUSERNAME}/FTP/files
        chmod a-w /home/${NEWUSERNAME}/FTP
        chown ${NEWUSERNAME}:${NEWUSERNAME} /home/${NEWUSERNAME}/FTP/files

        # Reconfiguration
        cp configs/ftp/certs/vsftpd.crt /etc/ssl/certs/vsftpd.crt
        cp configs/ftp/certs/private/vsftpd.key /etc/ssl/private/vsftpd.key
        cp /etc/vsftpd.conf /etc/vsftpd.conf.back # Create backup
        cp configs/ftp/vsftpd.conf /etc/vsftpd.conf # Replace by pre-configured file
        echo "${NEWUSERNAME}" | sudo tee -a /etc/vsftpd.userlist

        ufw allow 20:21/tcp # Open port in firewall
        ufw allow 990/tcp
        ufw allow 35000:40000/tcp
        sudo service vsftpd restart # Restart server
    fi
}

##### USB FOLDER BINDING
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
        LINE_TO_ADD2="${DEV_MOUNTPOINT} /home/${NEWUSERNAME}/FTP/files fuse.bindfs force-user=${NEWUSERNAME},force-group=${NEWUSERNAME},perms=${DEV_CHMOD} 0 0"

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

##### APACHE / INSTALL AND BIND
function apache_install_and_bind_setup () {
    read -p 'Do you want to install apache and bind folders ?' RUN_PROMPT
    if [ $RUN_PROMPT == "y" ]; then
        echo "Apache installation..."

        apt-get install apache2 -y
        rm -rf /var/www/html/*

        usermod -a -G www-data ${NEWUSERNAME}

        chown -R www-data:www-data /var/www
        chmod go-rwx /var/www
        chmod go+x /var/www
        chgrp -R www-data /var/www
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
        apt-get install php7.4 libapache2-mod-php7.4 php7.4-mbstring php7.4-mysql php7.4-curl php7.4-gd php7.4-zip -y

        echo "<?php echo \"Today's date is \".date('Y-m-d H:i:s');?>" >> /var/www/html/php_test.php
    fi
}

function show_menu ()
{
    clear
    echo "****************************************************************************************"
    echo "*                     RPI MULTISERVER SETUP SCRIPT BY PIOTRQ                           *"
    echo "****************************************************************************************"
    echo "****************************************************************************************"
    echo "0 - Update / Upgrade / Install tools"
    echo "1 - Enable firewall"
    echo "2 - Install FTP Server (use once)"
    echo "3 - Install USB device and bind to FTP user folder"
    echo "4 - Install Apache and bind to FTP user folder (use once)"
    echo "5 - Install PHP"
    echo "5 - Install MySQL (mariadb)" #TODO
    echo "6 - Install Dynamic dns" #TODO
    echo "7 - Install VPN server" #TODO
    echo "8 - Install Grafana with InfluxDB" #TODO
    echo "exit - Exit script"
    echo ""

}

########################################################################### MAIN RUNTIME #################################################################
##########################################################################################################################################################

##### USER CREATION SECTION
read -p 'Username: ' NEWUSERNAME
USEREXISTS=$(grep $NEWUSERNAME /etc/passwd | wc -l)
if [ "$USEREXISTS" -eq 0 ]; then
    echo "Hello $NEWUSERNAME. Now, We create new account..."
    useradd -m -r ${NEWUSERNAME}
    passwd ${NEWUSERNAME}
    usermod -aG sudo ${NEWUSERNAME}
fi
echo "Ok user $NEWUSERNAME exists..."

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
        6)
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
