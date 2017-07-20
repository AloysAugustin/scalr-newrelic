#!/bin/bash

mkdir -p /opt/newrelic

cd /opt/newrelic

wget https://download.newrelic.com/newrelic/java-agent/newrelic-agent/current/newrelic.yml
wget https://download.newrelic.com/newrelic/java-agent/newrelic-agent/current/newrelic.jar

sed -i.bak "s/<%= license_key %>/$NEWRELIC_LICENSE_KEY/" newrelic.yml
sed -i "s/app_name: My Application\(.*\)/app_name: \"$SCALR_FARM_NAME\1\"/g" newrelic.yml

echo "JAVA_OPTS=\"${JAVA_OPTS} -javaagent:/opt/newrelic/newrelic.jar\"" >> /etc/default/tomcat7

cd /var/lib/tomcat7/webapps

wget https://tomcat.apache.org/tomcat-6.0-doc/appdev/sample/sample.war

systemctl restart tomcat7
