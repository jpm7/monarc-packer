#! /usr/bin/env bash

# Variables
MonarcAppFO_Git_Repo='https://github.com/monarc-project/MonarcAppFO.git'
BRANCH='master'
#BRANCH='v0.1'
#TAG='v0.1'
TAG=''

PATH_TO_MONARC='/var/lib/monarc/fo'

APPENV='local'
ENVIRONMENT='PRODUCTION'

DBHOST='localhost'
DBNAME_COMMON='monarc_common'
DBNAME_CLI='monarc_cli'
DBUSER_ADMIN='root'
DBPASSWORD_ADMIN="$(openssl rand -hex 32)"
DBUSER_MONARC='sqlmonarcuser'
DBPASSWORD_MONARC="$(openssl rand -hex 32)"

upload_max_filesize=200M
post_max_size=50M
max_execution_time=100
max_input_time=223
memory_limit=512M
PHP_INI=/etc/php/7.1/apache2/php.ini

export DEBIAN_FRONTEND=noninteractive
export LANGUAGE=en_US.UTF-8
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
locale-gen en_US.UTF-8
dpkg-reconfigure locales

echo "--- Installing MONARC FO… ---"

echo "--- Updating packages list… ---"
sudo apt-get update

echo "--- Install base packages… ---"
sudo apt-get -y install vim zip unzip git gettext curl net-tools gsfonts  > /dev/null

echo "--- Install MariaDB specific packages and settings… ---"
echo "mysql-server mysql-server/root_password password $DBPASSWORD_ADMIN" | sudo debconf-set-selections
echo "mysql-server mysql-server/root_password_again password $DBPASSWORD_ADMIN" | sudo debconf-set-selections
sudo apt-get -y install mariadb-server mariadb-client > /dev/null

echo "--- Installing PHP-specific packages… ---"
sudo apt-get -y install php apache2 libapache2-mod-php php-curl php-gd php-mcrypt php-mysql php-pear php-apcu php-xml php-mbstring php-intl php-imagick php-zip > /dev/null
sleep 5 # give some time to the DB to launch...
sudo systemctl restart mariadb.service

echo "--- Configuring PHP ---"
for key in upload_max_filesize post_max_size max_execution_time max_input_time memory_limit
do
 sudo sed -i "s/^\($key\).*/\1 = $(eval echo \${$key})/" $PHP_INI
done

echo "--- Enabling mod-rewrite and ssl… ---"
sudo a2enmod rewrite > /dev/null
sudo a2enmod ssl > /dev/null

echo "--- Allowing Apache override to all ---"
sudo sed -i "s/AllowOverride None/AllowOverride All/g" /etc/apache2/apache2.conf

#echo "--- We want to see the PHP errors, turning them on ---"
#sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php/7.0/apache2/php.ini
#sed -i "s/display_errors = .*/display_errors = On/" /etc/php/7.0/apache2/php.ini

echo "--- Setting up our MySQL user for MONARC… ---"
sudo mysql -u root -p$DBPASSWORD_ADMIN -e "CREATE USER '$DBUSER_MONARC'@'localhost' IDENTIFIED BY '$DBPASSWORD_MONARC';"
sudo mysql -u root -p$DBPASSWORD_ADMIN -e "GRANT ALL PRIVILEGES ON * . * TO '$DBUSER_MONARC'@'localhost';"
sudo mysql -u root -p$DBPASSWORD_ADMIN -e "FLUSH PRIVILEGES;"

echo "--- Retrieving MONARC… ---"
sudo mkdir -p $PATH_TO_MONARC
sudo chown monarc:monarc $PATH_TO_MONARC
sudo -u monarc git clone --config core.filemode=false -b $BRANCH $MonarcAppFO_Git_Repo $PATH_TO_MONARC
if [ $? -ne 0 ]; then
    echo "ERROR: unable to clone the MOMARC repository"
    exit 1;
fi
cd $PATH_TO_MONARC
if [ "$TAG" != '' ]; then
    # Checkout the latest tag
    cd $PATH_TO_MONARC
    #latestTag=$(git describe --tags `git rev-list --tags --max-count=1`)
    git checkout $TAG
    cd ..
fi

echo "--- Installing composer… ---"
curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer > /dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: unable to install composer"
    exit 1;
fi
sudo composer self-update
sudo -u monarc composer config github-oauth.github.com $GITHUB_AUTH_TOKEN
sudo -u monarc composer install -o

echo "--- Retrieving MONARC libraries… ---"
# Modules
sudo -u monarc mkdir module
cd module
sudo -u monarc ln -s ./../vendor/monarc/core MonarcCore
sudo -u monarc ln -s ./../vendor/monarc/frontoffice MonarcFO
cd ..

# Interfaces
sudo -u monarc mkdir node_modules
cd node_modules
sudo -u monarc git clone --config core.filemode=false https://github.com/monarc-project/ng-client.git ng_client > /dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: unable to clone the ng-client repository"
    exit 1;
fi
sudo -u monarc git clone --config core.filemode=false https://github.com/monarc-project/ng-anr.git ng_anr > /dev/null
if [ $? -ne 0 ]; then
    echo "ERROR: unable to clone the ng-anr repository"
    exit 1;
fi
cd ..


echo "--- Add a VirtualHost for MONARC… ---"
sudo bash -c "cat > /etc/apache2/sites-enabled/000-default.conf <<EOF
<VirtualHost *:80>
    ServerName localhost
    DocumentRoot $PATH_TO_MONARC/public

    <Directory $PATH_TO_MONARC/public>
        DirectoryIndex index.php
        AllowOverride All
        Require all granted
    </Directory>

    SetEnv APPLICATION_ENV $ENVIRONMENT
</VirtualHost>
EOF"
echo "--- Restarting Apache… ---"
sudo systemctl restart apache2.service > /dev/null


echo "--- Configuration of MONARC data base connection… ---"
sudo -u monarc cat > config/autoload/local.php <<EOF
<?php
\$appdir = getenv('APP_DIR') ? getenv('APP_DIR') : '$PATH_TO_MONARC';
\$string = file_get_contents(\$appdir.'/package.json');
if(\$string === FALSE) {
    \$string = file_get_contents('./package.json');
}
\$package_json = json_decode(\$string, true);

return array(
    'doctrine' => array(
        'connection' => array(
            'orm_default' => array(
                'params' => array(
                    'host' => '$DBHOST',
                    'user' => '$DBUSER_MONARC',
                    'password' => '$DBPASSWORD_MONARC',
                    'dbname' => '$DBNAME_COMMON',
                ),
            ),
            'orm_cli' => array(
                'params' => array(
                    'host' => '$DBHOST',
                    'user' => '$DBUSER_MONARC',
                    'password' => '$DBPASSWORD_MONARC',
                    'dbname' => '$DBNAME_CLI',
                    ),
                ),
            ),
        ),

    /* Link with (ModuleCore)
    config['languages'] = [
        'fr' => array(
            'index' => 1,
            'label' => 'Français'
        ),
        'en' => array(
            'index' => 2,
            'label' => 'English'
        ),
        'de' => array(
            'index' => 3,
            'label' => 'Deutsch'
        ),
    ]
    */
    'activeLanguages' => array('fr','en','de','ne',),

    'appVersion' => \$package_json['version'],

    'email' => [
            'name' => 'MONARC',
            'from' => 'info@monarc.lu',
    ],

    'monarc' => array(
        'ttl' => 60, // timeout
        'salt' => '', // salt privé pour chiffrement pwd
    ),
);
EOF


sudo chown -R www-data $PATH_TO_MONARC/data


echo "--- Creation of the data bases… ---"
mysql -u $DBUSER_MONARC -p$DBPASSWORD_MONARC -e "CREATE DATABASE monarc_cli DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;" > /dev/null
mysql -u $DBUSER_MONARC -p$DBPASSWORD_MONARC -e "CREATE DATABASE monarc_common DEFAULT CHARACTER SET utf8 DEFAULT COLLATE utf8_general_ci;" > /dev/null
echo "--- Populating MONARC DB… ---"
sudo -u monarc mysql -u $DBUSER_MONARC -p$DBPASSWORD_MONARC monarc_common < db-bootstrap/monarc_structure.sql > /dev/null
sudo -u monarc mysql -u $DBUSER_MONARC -p$DBPASSWORD_MONARC monarc_common < db-bootstrap/monarc_data.sql > /dev/null


echo "--- Installation of Grunt… ---"
sudo apt-get -y install nodejs > /dev/null
sudo apt-get -y install npm > /dev/null
sudo npm install -g grunt-cli > /dev/null


echo "--- Update the project… ---"
sudo -u monarc ./scripts/update-all.sh

sudo -u monarc composer config github-oauth.github.com ''

echo "--- Create initial user and client ---"
sudo -u www-data php ./vendor/robmorgan/phinx/bin/phinx seed:run -c ./module/MonarcFO/migrations/phinx.php


echo "--- Restarting Apache… ---"
sudo systemctl restart apache2.service > /dev/null


echo "--- MONARC is ready! ---"
echo "Login and passwords for the MONARC image are the following:"
echo "MONARC application: admin@admin.test:admin"
echo "SSH login: monarc:password"
echo "Mysql root login: $DBUSER_ADMIN:$DBPASSWORD_ADMIN"
echo "Mysql MONARC login: $DBUSER_MONARC:$DBPASSWORD_MONARC"
