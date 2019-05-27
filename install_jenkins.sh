#!/bin/bash

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic test"
sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io
clear

# check if we've already got a jenkins container running
if ! sudo docker ps | grep -q 'jenkins-docker'; then
   curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
   sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu bionic test"
   sudo apt-get install -y default-jre
   sudo docker image build -f Dockerfile_jenkins -t jenkins-docker .
   sudo docker container run -d -p 443:8080 -v /var/run/docker.sock:/var/run/docker.sock jenkins-docker
   sleep 2
fi

# looks like you have to go to the web console in order for it to create the admin password file
JENKINS=$(curl --silent -H "Metadata-Flavor: Google" http://metadata/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip)
echo "http://$JENKINS:443"
read -p "Please head here in your web browser and login using the administrator password. Select to install 'Suggested Plugins' and once complete, press any key to continue..."
while true; do
   sudo docker exec -t  9bb1c832efaf cat /var/jenkins_home/secrets/initialAdminPassword
   if [ $? -eq 0 ]; then
      break
   fi
   sleep 5
done

wget localhost:443/jnlpJars/jenkins-cli.jar
java -jar jenkins-cli.jar -s http://localhost:443 -auth admin:admin install-plugin blueocean
java -jar jenkins-cli.jar -s http://localhost:443 -auth admin:admin install-plugin docker-plugin
java -jar jenkins-cli.jar -s http://localhost:443 -auth admin:admin install-plugin anchore-container-scanner
java -jar jenkins-cli.jar -s http://localhost:443 -auth admin:admin restart