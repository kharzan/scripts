#!/bin/bash
###################### Introduction a l installation ######################################
echo ''
echo ''
echo '---------------------------------------------------------------------'
echo '---------------------Installation Observium--------------------------'
echo '---------------------------------------------------------------------'
echo ''
echo ''
choix=0
while ! [ "$choix" == 1 -o "$choix" == 2 -o "$choix" == 3 -o "$choix" == 4 -o "$choix" == 5 ]; do
	echo " Que souhaitez vous faire ?"
	echo " 1 - Installer Observium coter serveur"
	echo " 2 - Installer l'agent sur une target"
	echo " 3 - Ajouter un utilisateur"
	echo " 4 - Ajouter un device"
	echo " 5 - Importer un fichier de configuration"
	echo " 6 - Quitter"
	read choix
done

if [ "$choix" == 6 ]; then 
echo "Aurevoir"
exit 
fi

if [ "$choix" = 1 ]; then
##################### Preparation et installation du dossier observium ###################
cd /opt/
### test de connection avant téléchargement
ping http://www.observium.org/observium-community-latest.tar.gz
if ! [ "$?" == 0 ];then
	echo "Problème de connection, le fichier d'installation d'observium est introuvable."
	exit
fi
wget http://www.observium.org/observium-community-latest.tar.gz
tar zxvf observium-community-latest.tar.gz
rm -f /opt/observium-community-latest.tar.gz

##################### Telechargement des dependances ######################################
apt-get update
apt-get install -y libapache2-mod-php5 php5-cli php5-mysql php5-gd php5-mcrypt libvirt-bin
apt-get install -y php5-json php-pear snmp fping mysql-server mysql-client python-mysqldb
apt-get install -y rrdtool subversion whois mtr-tiny ipmitool graphviz mtr-tiny imagemagick
# Possibiliter de creer un compte pour 180 dollars / an et lier le compte via :
#svn co http://svn.observium.org/svn/observium/trunk observium

#################### Preparation de la database observium ################################
read -s -p "Entrer le mot de passe root de mysql : " mdp
test=1

#### test du mdp mysql
while [ "$test" == 1 ];do
	mysql -u root -p$mdp -e exit
	test=$?
	if [ "$test" == 1 ];then 
		echo ''
		read -s -p "Connexion impossible, recommencez : " mdp
	fi
done

#### creation proprietaire database observium
observium=0
observium2=0
echo ''
while [ "$observium" == 0 ];do
	echo "Mot de passe souhaitez pour l'utilisateur observium : "
	read -s observium
	echo ''
	echo "Confirmer : " 
	read -s observium2
 	if ! [ "$observium" == "$observium2" ];then
		observium=0
		observium2=0
		echo ''
		echo "Erreur, recommencer"
	fi
done

mysql -u root -p$mdp << EOF
CREATE DATABASE observium DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;
GRANT ALL PRIVILEGES ON observium.* TO 'observium'@'localhost' IDENTIFIED BY '$observium';
EOF

################# Installation d observium ##############################################
cd /opt/observium
mkdir logs
mkdir rrd
chown www-data:www-data rrd
cp config.php.default config.php
echo Adaptation des données dans le fichier de configuration par rapport à votre db
sed -i 's/USERNAME/observium/g' /opt/observium/config.php
sed -i 's/PASSWORD/'$observium'/g' /opt/observium/config.php 


################# Changement port d ecoute ##############################################
echo "Sur qu'elle port souhaitez vous écouter ?"
read listen
choix=0

if [ "$listen" == 80 -o "$listen" == 443 ];then
	echo 'Attention /!\'
	echo 'Si un autre service web apache tourne sur ce port, il sera supprimer.'
	echo 'PS : le port 443 necessite d apporter des modifications aux fichiers de configuration'
	echo 'Souhaitez vous changer le port ? (o/n) '
	read choix
	while ! [ "$choix" == "o" -o "$choix" == "O" -o "$choix" == "n" -o "$choix" == "N" ]; do
		echo "Mauvaise entrer, souhaitez vous changer le port ? (o/n) "
		read choix
	done
	if [ "$choix" == "o" -o "$choix" == "O" ];then
		echo "Sur qu'elle port souhaitez vous ecouter ?"
		read listen
	fi
fi

chemin=/etc/apache2/sites-available/observium.conf
if [ "$listen" == 80 -o "$listen" == 443 ];then
	chemin=/etc/apache2/sites-available/000-default.conf
	cp /etc/apache2/sites-available/000-default.conf /etc/apache2/sites-available/000-default.conf.old
	echo '' > /etc/apache2/sites-available/000-default.conf
fi

echo '<VirtualHost *:'$listen'>' >> $chemin
echo '' >> $chemin
echo '	ServerAdmin webmaster@localhost' >> $chemin
echo '	DocumentRoot /opt/observium/html' >> $chemin
echo '' >> $chemin
echo '	<FilesMatch \.php$>' >> $chemin
echo '		SetHandler application/x-httpd-php' >> $chemin
echo '	</FilesMatch>' >> $chemin
echo '' >> $chemin
echo '	<Directory />' >> $chemin
echo '		Options FollowSymLinks' >> $chemin
echo '		AllowOverride None' >> $chemin
echo '	</Directory>' >> $chemin
echo '' >> $chemin
echo '	<Directory /opt/observium/html/>' >> $chemin
echo '		DirectoryIndex index.php' >> $chemin
echo '		Options Indexes FollowSymLinks MultiViews' >> $chemin
echo '		AllowOverride All' >> $chemin
echo '		Order Allow,Deny' >> $chemin
echo '		Require all granted' >> $chemin
echo '		Allow from all' >> $chemin
echo '	</Directory>' >> $chemin
echo '' >> $chemin
echo '	ErrorLog ${APACHE_LOG_DIR}/error.log' >> $chemin
echo '	LogLevel warn' >> $chemin
echo '	CustomLog ${APACHE_LOG_DIR}/access.log combined' >> $chemin
echo '	ServerSignature On' >> $chemin
echo '' >> $chemin
echo '</VirtualHost>' >> $chemin

################# Activation des modes apache ###########################################
php5enmod mcrypt
a2dismod mpm_event
a2enmod mpm_prefork
a2enmod rewrite
/etc/init.d/apache2 restart
./discovery.php -u
./poller.php -h all

#### decouverte automatique avec crontab 
touch /opt/observium/decouverte_auto.sh
chmod 722 /opt/observium/decouverte_auto.sh
## ici toute les 2 minutes à x2hxx, tout les jours, toute les semaines, tout les mois##
echo "#!/bin/bash" >> /opt/observium/decouverte_auto.sh
echo "/opt/observium/discovery.php -h new" >> /opt/observium/decouverte_auto.sh
echo "/opt/observium/discovery.php -h all" >> /opt/observium/decouverte_auto.sh
echo "/opt/observium/poller-wrapper.py 2" >> /opt/observium/decouverte_auto.sh
touch /root/temp
echo "*/2 * * * * /opt/observium/decouverte_auto.sh" >> /root/temp
crontab /root/temp
rm /root/temp

################# Pannel admin ##########################################################
echo "Choisissez votre identifiant administrateur :"
echo "Username : " 
read username

password=0
password2=0
##### confirmer mdp
while [ "$password" == 0 ];do
	echo "Mot de passe : "	
	read -s password
	echo ''
	echo "Confirmer : "
	read -s password2
	if ! [ "$password" == "$password2" ];then
		password=0
		password2=0
		echo ''
		echo "Erreur, recommencer"
	fi
done

./adduser.php $username $password 10
if ! [ "$listen" == 80 -o "$listen" == 443 ];then
	echo "Listen "$listen"" >> /etc/apache2/ports.conf
fi

if [ -e /etc/apache2/sites-available/observium.conf ];then
	a2ensite observium.conf
else
	a2ensite 000-default.conf
fi

/etc/init.d/apache2 restart

################# Resumer du script #####################################################
echo ''
echo 'Resumer des taches accompli par le script :'
echo ' 1 - telechargement du programme et installation des dependances'
echo ' 2 - creation utilisateur (user: observium) et de la database dans mysql'
echo ' 3 - modification des identifiants dans le fichier de configuration /opt/observium/config.php'
echo ' 4 - Selection du port d ecoute et creation du virtualhost apache'
echo ' 5 - Activation de la decouverte automatique et ajout dans le crontab la decouverte'
echo ' 6 - Creation de l administrateur de l interface web'
exit
fi


if [ "$choix" = 2 ]; then
echo 'Deploiement du script d installation coter client'
apt-get update
apt-get -y install snmpd snmpd xinetd telnet
echo "$config['poller_modules']['unix-agent']	=1;" >> /opt/observium/config.php
# voir si il existe sinon créer la ligne

echo 'Qui voulez-vous superviser ? (FQDN : nom sur le dns) '
read target

scp /opt/observium/scripts/observium_agent_xinetd "$target":/etc/xinetd.d/observium_agent_xinetd
scp /opt/observium/scripts/observium_agent "$target":/usr/bin/observium_agent
## demander d'entrer la geoposition du serveur !!!!### /!\ !!!! ###
touch /root/agent_observium_target
chmod 722 /root/agent_observium_target
chemin=/root/agent_observium_target
echo "#!/bin/bash" >> $chemin
echo "/etc/init.d/xinetd restart" >> $chemin
echo "mkdir /usr/lib/observium_agent" >> $chemin
echo "mkdir /usr/lib/observium_agent/local" >> $chemin
echo "apt-get install -y snmp snmpd" >> $chemin
echo "cp /etc/snmp/snmpd.conf /etc/snmp/snmpd.conf.old" >> $chemin
echo "echo "" > /etc/snmp/snmpd.conf" >> $chemin
echo "echo "rocommunity public" >> /etc/snmp/snmpd.conf" >> $chemin
echo "echo 'syslocation "Europe/France/Paris"' >> /etc/snmp/snmpd.conf" >> $chemin
echo "echo "syscontact admin@localhost" >> /etc/snmp/snmpd.conf" >> $chemin
echo "#echo "SNMPDOPTS='-LS6d -Lf /dev/null -u snmp -g snmp -I -smux,mteTrigger,mteTriggerConf -p /run/snmpd.pid'" >> /etc/default/snmpd" >> $chemin
echo "/etc/init.d/snmpd restart" >> $chemin
scp /root/agent_observium_target "$target":/root/
rm /root/agent_observium_target
exit
fi

if [ "$choix" == 3 ]; then
echo "Choisissez votre identifiant :"
read username

password=0
password2=0
##### confirmer mdp
while [ "$password" == 0 ]; do
	echo "Mot de passe : "
	read -s password
	echo "Confirmer : "
	read -s password2
	if ! [ "$password" == "$password2" ];then
		password=0
		password2=0
		echo ''
		echo "Erreur, recommencer"
	fi
done

choix=42
echo "Qu'elle niveau de privileges souhaitez vous attribuer a l utilisateur ?"
echo ""
echo "0 : utilisateur bloquer mais présent dans la database."
echo "1 : Lecture seule en fonction de ces permissions"
echo "5 : Lecture seule sur tout les devices (quelques configurations masquées)"
echo "7 : Lecture seule sur tout les devices"
echo "8 : Administrateur des équipements mais ne peut supprimer les utilisateurs"
echo "10 : Administrateur absolu"
echo ""
echo "Choix :"
read choix

while ! [ "$choix" == 0 -o "$choix" == 1 -o "$choix" == 5 -o "$choix" == 7 -o "$choix" == 8 -o "$choix" == 10 ];do
	echo "Erreur, recommencer "
	read choix
done

/opt/observium/adduser.php $username $password $choix
choix=0
exit
fi

if [ "$choix" == 4 ]; then
echo "Qu'elle device souhaitez vous ajouter ? (nom dns ou FQDN)"
read target
/opt/observium/add_device.php $target
exit
fi

if [ "$choix" == 5 ]; then
echo "Sélectionnez le fichier à importer : (chemin absolu)"
read file
## verification ?
cp /opt/observium/config.php /opt/observium/config.php.old
cp $file /opt/observium/config.php
fi
