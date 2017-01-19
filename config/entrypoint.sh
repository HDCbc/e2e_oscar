#!/bin/bash
#
# Halt on error and unset variables
#
set -eu


# Nothing to do without SQL files to process
#
if [ ! -s /import/*.sql ]
then
    echo "$(date +%Y-%m-%d-%T) No SQL files found to process.  Exiting."
    exit
fi


# Set variables
#
DEL_DUMPS=${DEL_DUMPS:-"no"}
E2E_DIFF=${E2E_DIFF:-"off"}
E2E_DIFF_DAYS=${E2E_DIFF_DAYS:-"14"}
TARGET=${TARGET:-"gateway"}


# Random SQL password
#
SQL_PW=$( cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1 )


# Configure oscar12.properties
#
sed -i \
  -e "s/^#*E2E_DIFF *=.*/E2E_DIFF = ${E2E_DIFF}/" \
  -e "s/^#*E2E_DIFF_DAYS *=.*/E2E_DIFF_DAYS = ${E2E_DIFF_DAYS}/" \
  -e "s/^#*E2E_URL *=.*/E2E_URL = http:\/\/${TARGET}:3001\/records\/create/" \
  -e "s/^#*db_password *=.*/db_password = ${SQL_PW}/" \
/usr/share/tomcat6/oscar12.properties


# Start MySQL, set temp password and set up OSCAR database
#
cd /oscar_db/
service mysql start
mysql --user=root --password=superInsecure -e "use mysql; update user set password=PASSWORD('${SQL_PW}') where User='root'; flush privileges;"


# Extract and .XZ files
#
echo "Check for .XZ files to extract"
find /import/ -name "*.xz" | \
  while read IN
  do
    echo 'Extracting:' "${IN}"
    unxz "${IN}"
  done


# Import SQL, export E2E and delete/rename SQL (see $DEL_DUMPS=yes/no)
#
mkdir -p /tmp/tomcat6-tmp/
echo "Start data import"
find /import/ -name "*.sql" | \
  while read IN
  do
    # Import SQL and log
    #
    echo 'Processing:' "${IN}"
    echo "$(date +%Y-%m-%d-%T) ${IN} import started" | sudo tee -a /import/import.log
    mysql --user=root --password="${SQL_PW}" oscar_12_1 < "${IN}"
    echo "$(date +%Y-%m-%d-%T) ${IN} import finished" | sudo tee -a /import/import.log


    # Export E2E and log
    #
    echo "$(date +%Y-%m-%d-%T) ${IN} export started" | sudo tee -a /import/import.log
    /sbin/setuser tomcat6 /usr/lib/jvm/java-6-oracle/bin/java \
        -Djava.util.logging.config.file=/var/lib/tomcat6/conf/logging.properties \
        -Djava.util.logging.manager=org.apache.juli.ClassLoaderLogManager \
        -Djava.awt.headless=true -Xmx1024m -Xms1024m -XX:MaxPermSize=512m -server \
        -Djava.endorsed.dirs=/usr/share/tomcat6/endorsed -classpath /usr/share/tomcat6/bin/bootstrap.jar \
        -Dcatalina.base=/var/lib/tomcat6 -Dcatalina.home=/usr/share/tomcat6 \
        -Djava.io.tmpdir=/tmp/tomcat6-tmp org.apache.catalina.startup.Bootstrap start
    echo "$(date +%Y-%m-%d-%T) ${IN} export finished" | sudo tee -a /import/import.log


    # Rename or delete imported SQL
    #
    if [ "${DEL_DUMPS}" = "yes" ]
    then
        rm "${IN}"
        echo "$(date +%Y-%m-%d-%T) ${IN} removed" | sudo tee -a /import/import.log
    else
        mv "${IN}" "${IN}"-imported$(date +%Y-%m-%d-%T)
        echo "$(date +%Y-%m-%d-%T) ${IN} renamed" | sudo tee -a /import/import.log
    fi
  done


# Drop database, log and shut down
#
mysql --user=root --password="${SQL_PW}" -e 'drop database oscar_12_1;'
echo "$(date +%Y-%m-%d-%T) OSCAR database dropped" | sudo tee -a /import/import.log
service mysql stop
