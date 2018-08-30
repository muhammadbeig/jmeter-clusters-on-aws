#!/bin/bash
function validate { #usage validate "command to run" "description of command"
    eval "$1"
    local status=$?
    if [ $status -ne 0 ]; then
        echo -e "\nFailure: $2 while $1"
        exit 1
    else
        echo "OK: $2" >&2
    fi
    return $status
}

USER=ec2-user
# NEW_USER=dev_mashdeploy
NEW_USER=jenkins-slave
JMETER_PORT=4001
REVERSE_PORT=7000
JMETER_VERSION=3.3
JMETER_HOME=/usr/local/apache-jmeter-${JMETER_VERSION}
PATH=${JMETER_HOME}/bin:${PATH}
JMETER_BINARIES_URL=https://archive.apache.org/dist/jmeter/binaries
PLUGINS_VERSION=1.3.0
role="$1"
logfile=/home/${USER}/setup/install.log
LOCATION="/home/${USER}/setup"

echo "Starting ${role} setup at `date`" >> ${logfile} 2>&1 

validate "sudo yum -y update" "Updating yum" >> ${logfile} 2>&1 

validate "wget ${JMETER_BINARIES_URL}/apache-jmeter-${JMETER_VERSION}.tgz && \
	sudo tar -xzf apache-jmeter-${JMETER_VERSION}.tgz -C /usr/local/" "Downloading and untarring jmeter binary files" >> ${logfile} 2>&1

validate "sudo chown -R ${USER} ${JMETER_HOME}" "Changing ownership of ${JMETER_HOME} to ${USER}" >> ${logfile} 2>&1

validate "wget http://jmeter-plugins.org/downloads/file/JMeterPlugins-Standard-${PLUGINS_VERSION}.zip \
	http://jmeter-plugins.org/downloads/file/JMeterPlugins-Extras-${PLUGINS_VERSION}.zip \
	http://jmeter-plugins.org/downloads/file/JMeterPlugins-ExtrasLibs-${PLUGINS_VERSION}.zip \
	https://jmeter-plugins.org/files/packages/jmeter.backendlistener.elasticsearch-2.4.1.zip && \
	unzip -o JMeterPlugins-Standard-${PLUGINS_VERSION}.zip -d ${JMETER_HOME} && \
	unzip -o JMeterPlugins-Extras-${PLUGINS_VERSION}.zip -d ${JMETER_HOME} && \
	unzip -o JMeterPlugins-ExtrasLibs-${PLUGINS_VERSION}.zip -d ${JMETER_HOME} && \
	unzip -o jmeter.backendlistener.elasticsearch-2.4.1.zip -d ${JMETER_HOME}" "Downloading and unzipping jmeter plugins" >> ${logfile} 2>&1



validate "rm -rf apache-jmeter-${JMETER_VERSION}.tgz \
        JMeterPlugins-Standard-${PLUGINS_VERSION}.zip \
        JMeterPlugins-Extras-${PLUGINS_VERSION}.zip \
        JMeterPlugins-ExtrasLibs-${PLUGINS_VERSION}.zip \
			${JMETER_HOME}/bin/examples \
			${JMETER_HOME}/bin/templates \
			${JMETER_HOME}/bin/*.cmd \
			${JMETER_HOME}/bin/*.bat \
			${JMETER_HOME}/docs \
			${JMETER_HOME}/printable_docs && \
	sudo yum -y autoremove && \
sudo rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*" "Removing un-needed files" >> ${logfile} 2>&1


if [[ -d ${LOCATION}/libextfiles ]]; then
	echo "About to copy library extension files to jmeter lib/ext folder" >> ${logfile} 2>&1
	for f in `ls ${LOCATION}/libextfiles`;
	do
		cp ${LOCATION}/libextfiles/$f ${JMETER_HOME}/lib/ext/
	done
fi

if [[ -d ${LOCATION}/libextzips ]]; then
	echo "About to extract library extension files to jmeter lib/ext folder" >> ${logfile} 2>&1
	for f in `ls ${LOCATION}/libextzips`;
	do
		unzip -o ${LOCATION}/libextzips/$f -d ${JMETER_HOME}/
	done
fi



echo -e "\n# Keystore Info" >> ${JMETER_HOME}/bin/system.properties
if [[ -d ${LOCATION}/keystore ]]; then
	echo "About to add keystore info in jmeter system.properties file" >> ${logfile} 2>&1

	keystore_password=`cat ${LOCATION}/keystore/.password`
	echo -e "javax.net.ssl.keyStorePassword=${keystore_password}" >> ${JMETER_HOME}/bin/system.properties
	keystore=${LOCATION}/keystore/.keystore
	echo -e "javax.net.ssl.keyStore=${keystore}" >> ${JMETER_HOME}/bin/system.properties
	rm -rf ${LOCATION}/keystore/.password

	# for f in `ls -a ${LOCATION}/keystore/`; 
	# do 
	# if [[ $f != "." && $f != ".." ]]; then  
	# 	# echo "file: -$f-"; 
	# 	if [[ $f == ".password" ]]; then
	# 		keystore_password=`cat ${LOCATION}/keystore/.password`
	# 		echo -e "javax.net.ssl.keyStorePassword=${keystore_password}" >> ${JMETER_HOME}/bin/system.properties
	# 	else
	# 		keystore=${LOCATION}/keystore/.keystore
	# 		echo -e "javax.net.ssl.keyStore=${keystore}" >> ${JMETER_HOME}/bin/system.properties
	# 	fi
	# fi
	# rm -rf ${LOCATION}/keystore/.password
	# done
	
fi


echo -e "\n# Truststore Info" >> ${JMETER_HOME}/bin/system.properties
if [[ -d ${LOCATION}/truststore ]]; then
	echo "About to add truststore info in jmeter system.properties file" >> ${logfile} 2>&1
	
	truststore=${LOCATION}/truststore/.truststore
	echo -e "javax.net.ssl.trustStore=${truststore}" >> ${JMETER_HOME}/bin/system.properties
	truststore_password=`cat ${LOCATION}/truststore/.password`
	# echo "Password: ${truststore_password}"
	echo -e "javax.net.ssl.trustStorePassword=${truststore_password}" >> ${JMETER_HOME}/bin/system.properties
	rm -rf ${LOCATION}/truststore/.password

	# for f in `ls -a ${LOCATION}/truststore/`; 
	# do 
	# if [[ $f != "." && $f != ".." ]]; then  
	# 	# echo "file: -$f-"; 
	# 	if [[ $f == ".password" ]]; then
	# 		truststore_password=`cat ${LOCATION}/truststore/.password`
	# 		echo -e "javax.net.ssl.trustStorePassword=${truststore_password}" >> ${JMETER_HOME}/bin/system.properties
	# 	else
	# 		truststore=${LOCATION}/truststore/$f
	# 		echo -e "javax.net.ssl.trustStore=${truststore}" >> ${JMETER_HOME}/bin/system.properties
	# 	fi
	# fi
	# rm -rf ${LOCATION}/truststore/.password
	# done
	
fi


if [[ "${role}" == "server" ]]; then
	ec2name=`curl -s http://169.254.169.254/latest/meta-data/public-hostname`
	#validate "screen -L -S \"server\" -d -m -X bash ${JMETER_HOME}/bin/jmeter -s -Jserver.rmi.localport="${JMETER_PORT}" -Djava.rmi.server.hostname=`curl -s http://169.254.169.254/latest/meta-data/public-hostname` " "Starting jmeter server" >> ${logfile} 2>&1	
	if [[ ! -z ${ec2name} ]]; 
	then 
		#screen -L -S "server" -d -m 
		bash "${JMETER_HOME}"/bin/jmeter.sh -s -Jserver.rmi.localport="${JMETER_PORT}" -Djava.rmi.server.hostname="${ec2name}" #>> ${logfile} 2>&1
		echo "Started jmeter server process" >> ${logfile} 2>&1
	else
		echo "Invalid ec2 name (${ec2name})" >> ${logfile} 2>&1
	fi
else
	echo "About to installing python packages" >> ${logfile} 2>&1
	validate "sudo pip install pytz" "Installing pytz module for python"
	validate "sudo pip install requests" "Installing pytz module for python"
	validate "sudo yum install -y gcc" "Installing gcc required for numpy"
	validate "sudo pip install numpy" "Installing numpy module for python"
fi

sed -i 's/^#client.rmi.localport=0/client.rmi.localport='"${REVERSE_PORT}"'/' ${JMETER_HOME}/bin/jmeter.properties

# Adding for the ${NEW_USER} setup
validate "sudo adduser ${NEW_USER} && sudo passwd -d ${NEW_USER}" "Creating user ${NEW_USER}"
if [[ -a ~/.ssh/authorized_keys ]]; then 
	validate "sudo mkdir /home/${NEW_USER}/.ssh && sudo cp ~/.ssh/authorized_keys /home/${NEW_USER}/.ssh/" "Copying authorized keys to ${NEW_USER}/.ssh/ folder"
	validate "sudo cp -r setup/ /home/${NEW_USER}/" "Copying this setup file to ${NEW_USER}'s home folder"
	validate "sudo chown -R ${NEW_USER}:${NEW_USER} /home/${NEW_USER}" "Changing ${NEW_USER} home folder permissions"
	validate "sudo su - ${NEW_USER}" "Switching to ${NEW_USER} user"
	validate "chmod 700 .ssh/ && chmod 600 .ssh/authorized_keys" "Correcting .ssh folder & authorized_keys permissions"
else
	echo "The file authorized_keys doesn't exist, quitting" >> ${logfile} 2>&1 
	exit 1
fi


echo "Setup completed at `date`" >> ${logfile} 2>&1
