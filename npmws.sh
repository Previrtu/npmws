#!/bin/bash
#######################################################
## NGINX + PHP + MariaDB Installer for Ubuntu/Debian ##
## By. ssut (ssut@ssut.me)                           ##
#######################################################
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root :(" 
    echo "Please try running this command again as root user"
    exit 1
fi

OS=$(awk '/DISTRIB_ID=/' /etc/*-release | sed 's/DISTRIB_ID=//' | tr '[:upper:]' '[:lower:]')
CODENAME=$(awk '/DISTRIB_CODENAME=/' /etc/*-release | sed 's/DISTRIB_CODENAME=//' | tr '[:upper:]' '[:lower:]')
PROCESS_COUNT=$(grep -c ^processor /proc/cpuinfo)
NGINX_PPA=0
MARIADB_VER="10.0"
PHP_VER="php5-oldstable"
#if [ "$OS" != "ubuntu" ] && [ "$OS" != "debian" ] && [ "$OS" != "mint" ]; then
if [ -f /usr/bin/apt-get ] && [ -f /usr/bin/aptitude ]; then
    echo "Detected $OS"
else
    echo "Warning: This script is made for Debian based Linux."
fi

function printMessage() {
    echo -e "\e[1;37m# $1\033[0m"
}

function apt_cache_update {
    printMessage "Updating APT(Advanced Packaging Tool) cache"
    apt-get update > /dev/null
}

function select_nginx {
        echo ""
        printMessage "Select NGINX PPA(Personal Package Archives)"
        echo "  1) Stable << Recommend"
        echo "  2) Development"
        echo -n "Enter: "
        read NGINX_PPA
        if [ "$NGINX_PPA" != 1 ] && [ "$NGINX_PPA" != 2 ]; then
            select_nginx
        fi
}

function select_mariadb {
    echo ""
    printMessage "Select MariaDB version"
    echo "  1) 10.0 Stable << Recommend"
    echo "  2) 10.1 Alpha"
    echo -n "Enter: "
    read MARIADB_SELECT
    if [ "$MARIADB_SELECT" != 1 ] && [ "$MARIADB_SELECT" != 2 ]; then
        select_mariadb
    elif [ "$MARIADB_SELECT" == 1 ]; then
        MARIADB_VER="10.0"
    elif [ "$MARIADB_SELECT" == 2 ]; then
        MARIADB_VER="10.1"
    fi
}

function select_php {
    echo ""
    printMessage "Select PHP version"
    echo "  1) 5.4"
    echo "  2) 5.5"
    echo "  3) 5.6"
    echo "  WARNING: Ubuntu 14.04 trusty does not support php-oldstable(5.4)"
    echo -n "Enter: "
    read PHP_SELECT
    if [ "$PHP_SELECT" != 1 ] && [ "$PHP_SELECT" != 2 ] && [ "$PHP_SELECT" != 3 ]; then
        select_php
    elif [ "$PHP_SELECT" == 1 ]; then
        PHP_VER="php5-oldstable"
    elif [ "$PHP_SELECT" == 2 ]; then
        PHP_VER="php5"
    elif [ "$PHP_SELECT" == 3 ]; then
        PHP_VER="php5-5.6"
    fi
}

function func_install {
    echo -en "\033[1mAre you sure want to continue? (y/n): \033[0m"
    read YN 
    YN=`echo $YN | tr "[:lower:]" "[:upper:]"`
    if [ "$YN" != "Y" ] && [ "$YN" != "N" ]; then
        func_install
    elif [ "$YN" == "N" ]; then
        exit
    fi
}

function check_py_apt {
    if [ -f /usr/bin/add-apt-repository ]; then
        echo "OK. Let's Go."
    else
        echo "- add-apt-repository does not exist"
        echo "# INSTALLING PYTHON-SOFTWARE-PROPERTIES"
        apt-get install software-properties-common python-software-properties -y
    fi
}

function install_nginx {
    printMessage "INSTALLING NGINX"
    
    [ "$NGINX_PPA" == 2 ] && NGINX_LW="development" || NGINX_LW="stable"
    
    add-apt-repository ppa:nginx/$NGINX_LW -y
    apt_cache_update
    apt-get install nginx -y
}

function install_php5 {
    printMessage "INSTALLING PHP5"
    
    add-apt-repository ppa:ondrej/$PHP_VER -y
    apt_cache_update
    apt-get install build-essential gcc g++ -y
    apt-get install libcurl3-openssl-dev -y
    apt-get install libpcre3 -y
    apt-get install libpcre3-dev -y 
    apt-get install sqlite sqlite3 -y
    apt-get install php5-common php5-cgi php5-cli php5-fpm php5-gd php5-cli php5-mcrypt php5-tidy php5-curl php5-xdebug php5-sqlite -y
    apt-get install php5-intl php5-dev -y
    apt-get install php-pear -y

    # Fix dependency
    apt-get purge apache2 libapache2-mod-php5 -y

    # Install php5-apcu
    apt-get install php5-apcu -y
    if [[ $? > 0 ]]; then
        apt-get install php-apc -y
    fi
}

function install_mariadb {
    printMessage "INSTALLING MariaDB"
    
    if [ "$MARIADB_VER" == "10.0" ]; then
        apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
        add-apt-repository "deb http://ftp.kaist.ac.kr/mariadb/repo/10.0/ubuntu ${CODENAME} main" -y
    elif [ "$MARIADB_VER" == "10.1" ]; then
        apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
        add-apt-repository "deb http://ftp.kaist.ac.kr/mariadb/repo/10.1/ubuntu ${CODENAME} main" -y
    fi
    
    apt_cache_update
    export DEBIAN_FRONTEND=noninteractive
    apt-get -o Dpkg::Options::="--force-confnew" -q -y install mariadb-server
    apt-get -o Dpkg::Options::="--force-confnew" -q -y install mariadb-client

    printMessage "INSTALLING PHP5-MySQL"
    apt-get install php5-mysql -y
}

function setting_nginx {
    printMessage "SETTING NGINX"
    
    cat <<nginx-config > /etc/nginx/php
location ~ \.php$ {
    fastcgi_pass unix:/var/run/php5-fpm.sock;
    fastcgi_index index.php;
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include /etc/nginx/fastcgi_params;
}
nginx-config
    
    rm -f /etc/nginx/sites-available/default
    rm -rf /etc/nginx/sites-available/
    rm -rf /etc/nginx/sites-enabled/

    cat <<nginx-config > /etc/nginx/conf.d/localhost
server {
    # Add the "ssl spdy" to turn on the SSL
    listen 80 default_server;
    
    # Root path
    root /usr/share/nginx/html;
    # Default index
    index index.php index.html index.htm;
    
    # Bind address
    server_name localhost 127.0.0.1;
    
    include php;
}
nginx-config

    mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.orig
    cat <<nginx-config > /etc/nginx/nginx.conf
user www-data;
worker_processes auto;
worker_rlimit_nofile 65000;
pid /run/nginx.pid;

events {
    worker_connections 2048;
    use epoll;
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on; # disable nagle algorithm
    
    keepalive_timeout 5;
    client_header_timeout 20;
    client_body_timeout 20;
    reset_timedout_connection on;
    send_timeout 20;
    
    types_hash_max_size 2048;
    server_tokens off;
    
    include /etc/nginx/mime.types;
    default_type text/html;
    charset UTF-8;
    
    # log file will be separated by ubuntu linux (.0, .1, .2 ...)
    access_log /var/log/nginx/access.log;
    error_log /var/log/nginx/error.log;
    
    # enable gzip compression for FEO
    gzip on;
    gzip_disable "msie6";
    gzip_buffers 16 8k;
    gzip_http_version 1.1;
    gzip_types text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript;
    
    open_file_cache max=65000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    include /etc/nginx/conf.d/*;
}
nginx-config
    
    chmod 755 /etc/nginx/nginx.conf

    chmod -R 777 /usr/share/nginx/html/*
    chmod 707 /usr/share/nginx/html
}

function install_phpmyadmin {
    printMessage "INSTALLING PHPMYADMIN"
    apt-get install unzip -y
    if [ -f /usr/bin/axel ]; then
        axel "http://sourceforge.net/projects/phpmyadmin/files/latest/download" -o /usr/share/nginx/html/pma.zip
    else
        wget "http://sourceforge.net/projects/phpmyadmin/files/latest/download" -O /usr/share/nginx/html/pma.zip
    fi
    unzip -o /usr/share/nginx/html/pma.zip -d /usr/share/nginx/html/
    mv /usr/share/nginx/html/phpMyAdmin-*/ /usr/share/nginx/html/phpmyadmin/
    chmod -R 755 /usr/share/nginx/html/phpmyadmin/
}

clear
echo "---------------------------------------------------------------"
echo -e "# Welcome to \033[1mNGINX+PHP+MariaDB\033[0m Installer for Ubuntu/Debian!"
echo "---------------------------------------------------------------"
select_nginx
select_mariadb
select_php

echo ""
echo "---------------------------------------------------------------"
echo "Here are install option you have selected:"
NGX_COMMENT="NGINX"
[ "$NGINX_PPA" == 1 ] && NGX_VER="Stable" || NGX_VER="Development"
echo "  $NGX_COMMENT $NGX_VER"
echo "  PHP stable (The latest version) + PHP Extensions"
echo "  MariaDB $MARIADB_VER"
echo "---------------------------------------------------------------"
echo ""
func_install
check_py_apt
install_nginx
install_php5
install_mariadb
install_phpmyadmin

printMessage "Stopping Nginx service"
service nginx stop

printMessage "Configuring nginx"
setting_nginx

printMessage "Starting nginx/php5-fpm/mariadb service"
service nginx start
service php5-fpm restart
service mysql restart

echo ""
clear
echo "---------------------------------------------------------------"
echo -e "\033[34m # Installed \033[1mNGINX+PHP+MariaDB\033[0m.\033[0m"
echo "---------------------------------------------------------------"
echo "* NGINX: service nginx {start|stop|restart|reload|status}"
echo "  /etc/nginx/"
echo "* PHP: service php5-fpm {start|stop|restart|status}"
echo "  /etc/php5/php5-fpm/"
echo "* MariaDB: service mysql {start|stop|restart|status}"
echo "  /etc/mysql/"
echo "---------------------------------------------------------------"
echo "* phpMyAdmin: http://localhost/phpmyadmin"
echo "---------------------------------------------------------------"
echo -e "\033[37m  NGINX+PHP+MariaDB by ssut(ssut@ssut.me)\033[0m"
echo "---------------------------------------------------------------"
