#!/bin/bash
function check_install {
    if [ -z "`which "$1" 2>/dev/null`" ]
    then
        executable=$1
        shift
        while [ -n "$1" ]
        do
            DEBIAN_FRONTEND=noninteractive apt-get -qq -y install "$1"
            print_info "$1 installed for $executable"
            shift
        done
    else
        print_warn "$2 already installed"
    fi
}

function check_remove {
    if [ -n "`which "$1" 2>/dev/null`" ]
    then
        DEBIAN_FRONTEND=noninteractive apt-get -qq -y remove --purge "$2"
        print_info "$2 removed"
    else
        print_warn "$2 is not installed"
    fi
}

function get_password() {
    # Check whether our local salt is present.
    SALT=/var/lib/random_salt
    if [ ! -f "$SALT" ]
    then
        head -c 512 /dev/urandom > "$SALT"
        chmod 400 "$SALT"
    fi
    password=`(cat "$SALT"; echo $1) | md5sum | base64`
    echo ${password:0:13}
}

function print_info {
    echo -n -e '\e[1;36m'
    echo -n $1
    echo -e '\e[0m'
}

function print_warn {
    echo -n -e '\e[1;33m'
    echo -n $1
    echo -e '\e[0m'
}

function check_sanity {
    # Do some sanity checking.
    if [ $(/usr/bin/id -u) != "0" ]
    then
        die 'Must be run by root user'
    fi

    if [ ! -f /etc/debian_version ]
    then
        die "Distribution is not supported"
    fi
}

function die {
    echo "ERROR: $1" > /dev/null 1>&2
    exit 1
}

function remove_unneeded {
    check_remove /sbin/portmap portmap
    check_remove /usr/sbin/apache2 'apache2*'
    check_remove /usr/sbin/named bind9
    check_remove /usr/sbin/smbd 'samba*'
    check_remove /usr/sbin/nscd nscd
    
    if [ -f /usr/lib/sm.bin/smtpd ]
    then
        service sendmail stop
        check_remove /usr/lib/sm.bin/smtpd 'sendmail*'
    fi
}

function change_ssh_port {
    sudo sed -ie 's/Port.*[0-9]$/Port '5022'/gI' /etc/ssh/sshd_config
}

function set_timezone {
     cat > /etc/timezone <<END
US/Pacific
END
     dpkg-reconfigure --frontend noninteractive tzdata
}

function update_upgrade {
    print_info "apt-get update and upgrade now running"
    sudo apt-get -qq -y update && sudo apt-get -qq -y upgrade
}

function install_common {
     print_info "Installing common software packages..."
     apt-get install -qq -y htop unzip zip curl python-software-properties software-properties-common nano p7zip-full s3cmd
}

function install_nginxphp {
     print_info "Starting Nginx/PHP5/PHP5 FPM Installation"
     apt-get install -qq nginx php5-fpm php5-mysql php5-curl php5-gd php5-idn php-pear php5-imagick php5-imap php5-mcrypt php5-memcache php5-ming php5-ps php5-pspell php5-recode php5-snmp php5-sqlite php5-tidy php5-xmlrpc php5-xsl php5-sqlite

     service php5-fpm stop && service nginx stop

cat > /etc/nginx/conf.d/lowendbox.conf <<END
server_names_hash_bucket_size 64;
END

cat > /etc/php5/fpm/pool.d/www.conf <<END
[www]
listen = 127.0.0.1:9000
user = www-data
group = www-data
pm = dynamic
pm.max_children = 10
pm.start_servers = 3
pm.min_spare_servers = 3
pm.max_spare_servers = 5
pm.max_requests = 500
pm.status_path = /status
ping.path = /ping
ping.response = pong
slowlog = /var/log/php-fpm.log.slow
chdir = /var/www
END
}


function install_mysqlserver {
    print_info "Installing MySQL Server"

  sudo apt-key adv --recv-keys --keyserver keyserver.ubuntu.com 0xcbcb082a1bb943db
	sudo add-apt-repository 'deb http://ftp.osuosl.org/pub/mariadb/repo/5.5/ubuntu quantal main'
	sudo apt-get update
	sudo apt-get install mariadb-server libmariadbclient18
	
    touch /var/log/mysql.slow-queries.log
	
	service mysql start

    # Generating a new password for the root user.
    passwd=`get_password root@mysql`
    mysqladmin password "$passwd"
    cat > ~/.my.cnf <<END
[client]
user = root
password = $passwd
END
    chmod 600 ~/.my.cnf
}
    
	
function make_directories {
     print_info "Creating web directories"
     mkdir -p /storage/web/vhosts/
     chown -R www-data:www-data /storage/web/
     mkdir -p /var/www
     chown -R www-data:www-data /var/www

}

function upgrade-os {
    sudo apt-get install update-manager-core
    sudo sed -ie 's/Prompt.*[a-z]$/Prompt='normal'/gI' /etc/update-manager/release-upgrades
    sed -i 's/mirror.rackspace.com/us.archive.ubuntu.com/' /etc/apt/sources.list
    do-release-upgrade -q

}

function web_ufw_enable {
    sudo ufw allow 80
    sudo ufw allow 443
    sudo ufw allow 5022
    sudo ufw default deny
    sudo ufw enable
}


function start_services {
     print_info "Starting Web Services"
     service php5-fpm start && service nginx start
}

########################################################################
# START OF PROGRAM
########################################################################
export PATH=/bin:/usr/bin:/sbin:/usr/sbin

check_sanity
case "$1" in
system)
     remove_unneeded
     update_upgrade
     install_syslogd
     install_common
     change_ssh_port
     set_timezone
     update_upgrade
    ;;
webserver)
     install_nginxphp
     update_upgrade
     make_directories
     start_services
     ;;
mysql-server)
     install_mysqlserver
     ;;
upgrade-os)
     upgrade-os
     ;;
web-ufw-rules)
     web_ufw_enable
     ;;
sql-ufw-rules)
     sql_ufw_enable
     ;;
disable-root-login)
    disable-root-login
    ;;
*)
    echo 'Usage:' `basename $0` '[option]'
    echo 'Available option:'
    for option in system webserver mysql-server mysql-client upgrade-os web_ufw_rules sql_ufw_rules disable-root-login
    do
        echo '  -' $option
    done
    ;;
esac
