#!/bin/bash

# Provide the following variables below to customize to your installation
SITE_DEMO_URL="https://YOUR-HOST-HERE.com/wordpress-demo-file.tgz"
TGZ_FILE_NAME="wordpress-demo-file.tgz"
MYSQL_FILE_NAME="wordpress-database.sql"
WP_ADMIN_EMAIL="testing@testing.com"

# Create the development directory inside of ~/public_html
get_dev_dir() {
    DIRNAME="dev"
    DIRNUMBER=0
    until mkdir "$HOME/public_html/$DIRNAME$DIRNUMBER" 2>/dev/null
    do
        ((DIRNUMBER++))
    done
    echo "$HOME/public_html/$DIRNAME$DIRNUMBER/"
}

# Download the .tgz Wordpress package and extract it
get_demo_package() {
    echo "Getting package..."
    wget ${SITE_DEMO_URL} -P "$DESTINATION" 2>/dev/null
    tar -xzf "${DESTINATION}${TGZ_FILE_NAME}" -C $DESTINATION
    rm -f "${DESTINATION}${TGZ_FILE_NAME}"
    echo "Package extracted..."
}

# Reset file and directory permissions
reset_file_perms() {
    find $DESTINATION -type f -exec chmod 644 {} \; &
    find $DESTINATION -type d -exec chmod 755 {} \; &
}

# Create new database name, database user & password. 
# Create a new wp-config.php with new creds and import the .sql
import_db() {
     cpuser="$(stat -c %U .)"
     pass="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 12 | head -n 1)"
     prefix="$(wp config get table_prefix --path=${DESTINATION})"
     dbstuff="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 7 | head -n 1)"
     name="${cpuser:0:8}_${dbstuff}"
     uapi Mysql create_database name=$name 1>/dev/null
     uapi Mysql create_user name=$name password=$pass 1>/dev/null
     uapi Mysql set_privileges_on_database user=$name database=$name privileges=ALL%20PRIVILEGES 1>/dev/null
     echo "name ${name} password ${pass} user ${name}"

     if [ -f ${DESTINATION}wp-config.php ]; then
          mv ${DESTINATION}wp-config.php ${DESTINATION}.old-wp-config.php
          mysql_host="$(uapi Mysql locate_server remote_host 2>/dev/null | grep -oP '(?<=host: ).+')"
          wp config create --dbname=$name --dbuser=$name --dbpass=$pass --dbprefix=$prefix --dbhost=$mysql_host --force --path=$DESTINATION
          wp config set WP_DEBUG false --type=variable --path=$DESTINATION
          mysql --user=$name -f --password=$pass -h $mysql_host $name <$1
     fi
     if [ "$#" -eq 1 ]; then
          mysql --user=$name -f --password=$pass -h $mysql_host $name <$1
     fi
     echo "define('WP_MEMORY_LIMIT', '516M');" >> ${DESTINATION}wp-config.php
}

# Replace the .htaccess with normalized .htaccess
replace_htaccess() {
    rm -f ${DESTINATION}.htaccess
    touch ${DESTINATION}.htaccess
    echo "AddHandler application/x-httpd-ea-php73 .php .php7 .phtml" >> ${DESTINATION}.htaccess
    echo "# BEGIN WordPress" >> ${DESTINATION}.htaccess
    echo "RewriteEngine On" >> ${DESTINATION}.htaccess
    echo "RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]" >> ${DESTINATION}.htaccess
    echo "RewriteBase /" >> ${DESTINATION}.htaccess
    echo "RewriteRule ^index\.php$ - [L]" >> ${DESTINATION}.htaccess
    echo "RewriteCond %{REQUEST_FILENAME} !-f" >> ${DESTINATION}.htaccess
    echo "RewriteCond %{REQUEST_FILENAME} !-d" >> ${DESTINATION}.htaccess
    echo "RewriteRule . /index.php [L]" >> ${DESTINATION}.htaccess
    echo "# END WordPress" >> ${DESTINATION}.htaccess
}

# Create a new user
create_user() {
    randnum=$(tr </dev/urandom -dc 0-9 | head -c3)
    user="supportadmin_${randnum}"
    pass=$(tr </dev/urandom -dc _A-Z-a-z-0-9 | head -c12)
    wp user create $user $WP_ADMIN_EMAIL --role=administrator --user_pass=$pass --path=$DESTINATION
    wp user delete delete-me --path=$DESTINATION --yes
    echo "Username: ${user}"
    echo "Password: ${pass}"
}

# Run all of the above functions to generate a new Wordpress demo installation
DESTINATION=$(get_dev_dir)
get_demo_package
reset_file_perms
replace_htaccess
import_db ${DESTINATION}${MYSQL_FILE_NAME}
create_user
echo "Destination directory created: $DESTINATION"