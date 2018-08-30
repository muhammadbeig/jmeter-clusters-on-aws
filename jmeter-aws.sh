#!/bin/bash
default_aws_region="us-east-1"
acceptable_aws_regions="us-east-1,us-east-2,us-west-1,us-west-2,ap-northeast-2,cn-north-1,cn-northwest-1,ap-southeast-1"
aws_region=""
AWS_AVAILABILITY_ZONE=""
AWS_AMI=""
INSTANCE_TYPE="t2.micro"
# INSTANCE_TYPE="t2.large"
# INSTANCE_TYPE="m5.xlarge"

# US East 1 (N Virginia): ami-6ed28611  aws-elasticbeanstalk-amzn-2018.03.0.x86_64-java8-hvm-201806211158
# US East 2 (Ohio): ami-ffc1ff9a
# US West 1 (N California): ami-b956b2da aws-elasticbeanstalk-amzn-2018.03.0.x86_64-java8-hvm-201806160002
# Asia Pac (Soeul): ami-9043e9fe aws-elasticbeanstalk-amzn-2018.03.0.x86_64-java8-hvm-201806160002

# AMI search criteria
# Name: aws-elasticbeanstalk-amzn-2018.03.0.x86_64-java8-hvm

NAMING_SUFFIX="jmeter"

assetsFolder=".assets"
logfile="awsjmeter.log"


USER="ec2-user"
LOCATION="/home/${USER}/setup"
PWD="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

JMETER_PORT=4001
#JMETER_VERSION=2.13
JMETER_VERSION=3.3
JMETER_HOME=/usr/local/apache-jmeter-${JMETER_VERSION}
deletion_in_progress_file=".deletion-in-progress"


timeout=150 # wait time for how long to wait for an ec2 instances to start running
function validate { #usage validate "command to run" "description of command"
    #echo "1: $1, 2: $2"
    eval "$1"
    local status=$?
    if [ $status -ne 0 ]; then
        echo -e "\nFailure: $2 while $1"
        exit 1
    else
    	# if [[ $DEBUG == "YES" ]]; then
        echo "OK: $2" >&2
    	# fi
    fi
    return $status
}

#at startup make sure there is something in the default region
if [[ -a .default_region ]];
then
    aws_region=`cat .default_region`
    AWS_AVAILABILITY_ZONE="${aws_region}a"
    if [[ $aws_region == *'us-west-1'* ]]; then AWS_AVAILABILITY_ZONE="${aws_region}b"; fi
else 
    echo "${default_aws_region}" > .default_region    
    aws_region="${default_aws_region}"
    AWS_AVAILABILITY_ZONE="${aws_region}a"
    if [[ $aws_region == *'us-west-1'* ]]; then AWS_AVAILABILITY_ZONE="${aws_region}b"; fi
fi

case ${aws_region} in
    *"us-east-1"*  ) AWS_AMI=${AWS_AMI:-"ami-6ed28611"};;    
    *"us-east-2"*  ) AWS_AMI=${AWS_AMI:-"ami-ffc1ff9a"};;
    *"us-west-1"*  ) AWS_AMI=${AWS_AMI:-"ami-b956b2da"};;
    *"us-west-2"*  ) AWS_AMI=${AWS_AMI:-"ami-0b6ac1028d83cd125"};;
    *"ap-northeast"*  ) AWS_AMI=${AWS_AMI:-"ami-b956b2da"};;
    *"cn-north-1"*  ) AWS_AMI=${AWS_AMI:-"ami-0302675d86ed36513"};;
    *"cn-northwest-1"*  ) AWS_AMI=${AWS_AMI:-"ami-1a6b7c78"};;
    *"ap-southeast-1"*  ) AWS_AMI=${AWS_AMI:-"ami-01e1c3fd510c4ad17"};;    
    * ) echo -e "\tSorry, currently only supported aws regions are:\n\t ${acceptable_aws_regions}"; exit 1;;            
esac   
aws configure set default.region ${aws_region}
default_cluster_name="default_${AWS_AVAILABILITY_ZONE//-/}"
VPC_NAMING="jmeter_VPC_${AWS_AVAILABILITY_ZONE//-/}"
KEYNAME="${NAMING_SUFFIX}-${AWS_AVAILABILITY_ZONE//-/}-key"

generated_keypair_location="${HOME}/.ssh"

set_aws_region () {
    region="$1"
    if [[ ! -z ${region} && "${acceptable_aws_regions//,/ }" == *"${region}"* ]];
    then
        # echo "Setting AWS region to: ${region}"
        echo "${region}" | tee .default_region
    else 
        echo "Invalid or unacceptable region ${region}, region did not set."
        echo -e "\tSorry, currently only supported aws regions are:\n\t ${acceptable_aws_regions}"
        exit 1
    fi
}

get_default_aws_region () {
    if [[ -a .default_region ]]; 
    then
        echo `cat .default_region`
    else
        echo ${default_aws_region} | tee .default_region
    fi
}


# Instead/in addition to creating a key use the following command to use the existing public key of the 
# machine you're running this one and copying it to the newly created instance
#
# cat ~/.ssh/id_rsa.pub | ssh user@123.45.56.78 "mkdir -p ~/.ssh && cat >>  ~/.ssh/authorized_keys"

add_pub_key_to_instance () {
    instance_dns="$1"
    if [[ -z ${instance_dns} ]]; then echo "No dns provided for the instance to be added public key to.."; exit 1; fi
    if [[ ! -a "${generated_keypair_location}/${KEYNAME}" ]]; then echo -e "Looking for: ${generated_keypair_location}/${KEYNAME}\n\tKey doesn't exist, quitting.."; exit 1; fi

    validate "cat ${generated_keypair_location}/${KEYNAME}.pub | ssh ${USER}@${instance_dns} \"mkdir -p ~/.ssh && chmod 700 .ssh && cat >>  ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys\"" "Copying public key to ${instance_dns}" >> ${logfile} 2>&1 
}

generate_key_name_for_file () {
    key_file=$1
    if [[ -z ${key_file} ]]; then echo "No key file provided to generate a keyname for.."; exit 1; fi

    if [[ `uname` == "Linux" ]]; then 
        # echo "its linux";
        export something_to_use_as_keyname=jmeter_`cat "${provided_key_file}" | md5sum`
    elif [[ `uname` == "Darwin" ]]; then 
        # echo "its a mac"; 
        export something_to_use_as_keyname=jmeter_`cat "${provided_key_file}" | md5`
    else
        echo -n "This script is only expected to work on Darwin or Linux distributions, using $something_to_use_as_keyname as the keyname" 
        export something_to_use_as_keyname="jmeter_provided_key"
    fi

}

delete_keypair_if_exists () {
    name_of_key_pair=$1
    if [[ -z ${name_of_key_pair} ]]; then echo "No keypair provided to delete, continuing";  fi

    existing=$(aws ec2 describe-key-pairs | grep -i ${name_of_key_pair} | cut -d":" -f 2 | cut -d"\"" -f 2)
    if [[ "${existing}" == "${name_of_key_pair}" ]]; then
        validate "aws ec2 delete-key-pair --key-name ${name_of_key_pair}" "Deleting ssh key pair ${name_of_key_pair} (region: ${aws_region})" >> ${logfile} 2>&1
    fi

}

generate_key_pair_if_not_there() {
    # echo "Test: ${generated_keypair_location}/${KEYNAME} there?"    
    if [[ ! -z ${provided_key_file} ]]; then
        # if [[ ${something_to_use_as_keyname} == "jmeter_provided_key" ]]; then             
        #     # existing=$(aws ec2 describe-key-pairs | grep -i ${something_to_use_as_keyname} | cut -d":" -f 2 | cut -d"\"" -f 2)
        #     # if [[ "${existing}" == "${something_to_use_as_keyname}" ]]; then
        #     #     validate "aws ec2 delete-key-pair --key-name ${something_to_use_as_keyname}" "Deleting ssh key ${something_to_use_as_keyname} (region: ${aws_region})" >> ${logfile} 2>&1
        #     # fi
        #     delete_keypair_if_exists ${something_to_use_as_keyname}
        # fi

        # generate_key_name_for_file ${provided_key_file}
        something_to_use_as_keyname=`basename "${provided_key_file}" | cut -d. -f1`

        existingKey=$(aws ec2 describe-key-pairs | grep -i ${something_to_use_as_keyname} | cut -d":" -f 2 | cut -d"\"" -f 2)
        if [[ "${existingKey}" == "${something_to_use_as_keyname}" ]]; then
            echo "${something_to_use_as_keyname} key already exists, reusing.."
        else
            validate "aws ec2 import-key-pair --key-name ${something_to_use_as_keyname} --public-key-material \"`cat ${provided_key_file}`\"" "Importing key pair to aws" >> ${logfile} 2>&1
        fi

    else        
        existingKeypair=$(aws ec2 describe-key-pairs | grep -i ${KEYNAME} | cut -d":" -f 2 | cut -d"\"" -f 2)
        if [[ -a "${generated_keypair_location}/${KEYNAME}" && "${existingKeypair}" == "${KEYNAME}" ]]; then
            echo "${generated_keypair_location}/${KEYNAME} exists, reuse.." >> ${logfile} 2>&1
        else 
            echo "${generated_keypair_location}/${KEYNAME} isn't there or isn't in aws" >> ${logfile} 2>&1
            if [[ -a "${generated_keypair_location}/${KEYNAME}" ]]; then rm -rf "${generated_keypair_location}/${KEYNAME}" && rm -rf "${generated_keypair_location}/${KEYNAME}".pub; fi
            
            ## think: what if it exists because of the first instance and now this is the second instance calling for it (doesn't apply anymore because this is being called from create_vpc)
            validate "ssh-keygen -b 2048 -t rsa -f ${generated_keypair_location}/${KEYNAME} -P \"\"" "Generating ssh key ${generated_keypair_location}/${KEYNAME}" >> ${logfile} 2>&1
            validate "aws ec2 import-key-pair --key-name ${KEYNAME} --public-key-material \"`cat ${generated_keypair_location}/${KEYNAME}.pub`\"" "Importing key pair to aws" >> ${logfile} 2>&1
            #eval "$(ssh-agent)"
            # validate "ssh-add ${generated_keypair_location}/${KEYNAME}" "Adding ssh key identity: ${generated_keypair_location}/${KEYNAME}"
        fi
    fi
}

remove_key_pair () {
    validate "aws ec2 delete-key-pair --key-name ${KEYNAME}" "Deleting ssh key ${KEYNAME} (region: ${aws_region})" >> ${logfile} 2>&1
    #eval "$(ssh-agent)"
    # ssh-add -d ${generated_keypair_location}/${KEYNAME} >> ${logfile} 2>&1
    if [ $? -ne 0 ]; then validate "ssh-add -D" "Removing all identities since was unable to remove individual identity"; fi
    rm -rf ${generated_keypair_location}/${KEYNAME} && rm -rf ${generated_keypair_location}/${KEYNAME}.pub  #"Deleting key pair (${KEYNAME}) locally from ${generated_keypair_location}" >> ${logfile} 2>&1
    # try to remove this identity using ssh-add -d if individually can be removed
}



##### Depricated
create_key_pair () {
    keypair_location=${assetsFolder}/vpc/${AWS_AVAILABILITY_ZONE}
    if [[ ! -d "${keypair_location}" ]]; then echo "${keypair_location} doesn't exist, quitting"; exit 1; fi
    
    existingKeypair=$(aws ec2 describe-key-pairs | grep -i ${KEYNAME} | cut -d":" -f 2 | cut -d"\"" -f 2)

    # only create a key pair if the same one doesnt exist already
    if [[ "${existingKeypair}" == "${KEYNAME}" && -a "${keypair_location}/${existingKeypair}".pem ]]; then
    # if [[ "${existingKeypair}" == "${KEYNAME}" && -a "${existingKeypair}".pem ]]; then
        echo "Keypair ${keypair_location}/${KEYNAME}.pem already exists, reusing.."
    else
        delete_key_pair ${KEYNAME}
        validate "aws ec2 create-key-pair --key-name ${KEYNAME} --query 'KeyMaterial' --output text > ${keypair_location}/${KEYNAME}.pem && chmod 400 ${keypair_location}/${KEYNAME}.pem" "Creating ssh key ${KEYNAME} and saving it under ${keypair_location}" >> ${logfile} 2>&1
        # validating "ssh-add ${keypair_location}/${KEYNAME}.pem" "Adding ssh key" >> ${logfile} 2>&1
        # echo "${aws_region},${AWS_AVAILABILITY_ZONE}" > ${keypair_location}/region.info
    fi
    
}
##### Depricated
delete_key_pair() {
    keypair_location=${assetsFolder}/vpc/${AWS_AVAILABILITY_ZONE}
    if [[ ! -a "${keypair_location}/region.info" ]];then  echo "region info doesn't exist in ${keypair_location}"; return; fi

    original_default_region=${aws_region}
    current_region=`cat ${keypair_location}/region.info 2> /dev/null | cut -d"," -f1`

    if [[ $current_region != $original_default_region && ! -z ${current_region} ]];
    then
        aws configure set default.region ${current_region} >> ${logfile} 2>&1
        region_changed="true"
        availability-zone="${current_region}a"
        KEYNAME="${NAMING_SUFFIX}-${availability-zone//-/}-key"
    fi

    validate "aws ec2 delete-key-pair --key-name ${KEYNAME} && rm -rf ${keypair_location}/${KEYNAME}.pem" "Deleting ssh key ${KEYNAME}" >> ${logfile} 2>&1

    if [[ $region_changed == "true" ]];
    then
        aws configure set default.region ${original_default_region} >> ${logfile} 2>&1
        region_changed=""
    fi
}

create_aws_instance() {
    if [[ -z ${AWS_AVAILABILITY_ZONE} ]]; then echo "AWS Availability Zone not set, quitting.."; exit 1; fi

    role=$1
    index=$2
    folderName=${assetsFolder}/clusters/${clusterName}/${role}
    if [[ ! -d ${folderName} ]]; then mkdir -p ${folderName}; fi
    if [[ ! -a ${assetsFolder}/clusters/${clusterName}/region.info ]]; 
    then
        echo "${aws_region},${AWS_AVAILABILITY_ZONE}" > ${assetsFolder}/clusters/${clusterName}/region.info    
    fi

    echo -e "\nCreating $role (${index}) instance.." >> ${logfile} 2>&1
    
    if [[ role == "client" ]]; then SECURITY_GROUP=${clientSG}; else SECURITY_GROUP=${serverSG}; fi    
    
    export pubdns=
    if [[ ! -z ${provided_key_file} ]]; then
        KEYNAME=${something_to_use_as_keyname}
    fi

    # echo "aws ec2 run-instances --image-id ${AWS_AMI} --count 1 --instance-type ${INSTANCE_TYPE} --key-name ${KEYNAME} --security-group-ids ${SECURITY_GROUP} --subnet-id $pubsubnet --associate-public-ip-address"
    validate "aws ec2 run-instances --image-id ${AWS_AMI} --count 1 --instance-type ${INSTANCE_TYPE} --key-name ${KEYNAME} --security-group-ids ${SECURITY_GROUP} --subnet-id $pubsubnet --associate-public-ip-address > ${folderName}/newinstance_${index}" "${role} ${index}: Creating aws Instance" >> ${logfile} 2>&1
    instanceid=$(cat "${folderName}/newinstance_${index}" | grep InstanceId |cut -d "\"" -f4)
    
    echo $instanceid >> ${folderName}/instanceids #add to existing instances
    # instanceIndex=$(cat "${folderName}"/instanceids | wc -l)
    # instanceIndex=${instanceIndex// /} #cleaning whitespace
    label=${clusterName}_${role}_${index}
    
    # adding name tag failed once with an error saying instance id not found, so adding some sleep
    sleep 20

    validate "aws ec2 create-tags --resources $instanceid --tags Key=Name,Value=${label} >> ${logfile} 2>&1" "${role} ${index}: Applying Name tag to the instance" >> ${logfile} 2>&1
    if [[ ! -z ${clusterName} ]]; then
        validate "aws ec2 create-tags --resources $instanceid --tags Key=Cluster,Value=${clusterName} >> ${logfile} 2>&1" "${role} ${index}: Applying Cluster tag to the instance" >> ${logfile} 2>&1
    fi
    if [[ ! -z ${role} ]]; then
        validate "aws ec2 create-tags --resources $instanceid --tags Key=Role,Value=${role} >> ${logfile} 2>&1" "${role} ${index}: Applying Role tag to the instance" >> ${logfile} 2>&1    
    fi

    # echo "Waiting for ${label} instance (${instanceid}) to get an ip address..."
    validate "aws ec2 describe-instances --instance-ids  $instanceid > ${folderName}/ec2desc_${index}" "${role} ${index}: Getting instance info" >> ${logfile} 2>&1
    pubdns=$(cat "${folderName}"/ec2desc_${index} | grep PublicDnsName |cut -d "\"" -f4) && pubdns=$(echo $pubdns | cut -d " " -f1 )
    state=$(cat "${folderName}"/ec2desc_${index} | grep "\"Name\"" | grep -v "Key" | cut -d "\"" -f4)

    if [[ -z $pubdns ]] || [[ $state -eq "pending" ]];
    then
        echo -e -n "${role} ${index}: Waiting for instance to become available.." >> ${logfile} 2>&1
        counter=0
        while [[ $counter -lt $timeout ]]; 
        do
            # echo -e "${pubdns} is ${state}.."
            let counter=$counter+10; 
            sleep 10;
            validate "aws ec2 describe-instances --instance-ids  $instanceid > ${folderName}/ec2desc_${index} " "${role} ${index}: Validating instance state" >> ${logfile} 2>&1
            pubdns=$(cat ${folderName}/ec2desc_${index} | grep PublicDnsName |cut -d "\"" -f4) && pubdns=$(echo $pubdns | cut -d " " -f1 )
            state=$(cat ${folderName}/ec2desc_${index} | grep "\"Name\"" | grep -v "Key" | cut -d "\"" -f4)
            if [[ ! "${state}" = "pending" ]]; then echo -e "${role}(${index}) is now up (at `date`):${pubdns} (${state} state)">> ${logfile} 2>&1; break; fi
        done
    fi

    if [[ ! $counter -lt $timeout ]] && [[ ! ${state} = "running" ]]; then
        echo -e "${role} ${index}: Still not in running state, timed out after ${timeout} seconds, exiting" && exit 1
    fi
    
    # sleep 20 # sleeping a little more, sometimes even in running state the ec2 instance is unreachable for a little bit
    
    

    IP_ADDRESS=$(cat ${folderName}/ec2desc_${index} | grep PublicIpAddress | cut -d":" -f2 | cut -d"\"" -f2)
    echo -e "\t${label} (${pubdns}) should now be up.. \n\tInstance set up will be executed in background (takes about 2-3 minutes)" >> ${logfile} 2>&1
    echo ${instanceid},${label},${pubdns},${IP_ADDRESS} >> ${folderName}/instances 

    
    scp_setup_script $role

}

scp_setup_script() {
    # keypair_location=${assetsFolder}/vpc/${AWS_AVAILABILITY_ZONE}
    keypair_location=${generated_keypair_location}
    key_file_with_path=${keypair_location}/${KEYNAME}

    if [[ ! -z ${provided_key_file} ]]; then
        key_file_with_path="`dirname ${provided_key_file}`/`basename ${provided_key_file} | cut -d"." -f1`"
    fi

    sleep 90
    role=$1
    echo "About to copy setup script to ${pubdns}:${LOCATION}" >> ${logfile} 2>&1
    ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} "mkdir ${LOCATION}" >> ${logfile} 2>&1
    if [[ "$?" != "0" ]]; # if above ssh fails
    then 
        echo -e "${role} ${index}: Failure creating a folder (${LOCATION}) on ${pubdns}, \n\tWaiting a bit and retrying"; >> ${logfile} 2>&1
        sleep 30
        validate "ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} \"mkdir -p ${LOCATION}\"" "${role} ${index}: Creating ${LOCATION} directory on ${pubdns}" >> ${logfile} 2>&1
        add_pub_key_to_instance ${pubdns}
    else
        # validate "scp -o StrictHostKeyChecking=no -i ${keypair_location}/${KEYNAME} base-setup.sh ${USER}@${pubdns}:${LOCATION}/ " "${role} ${index}: Scp setup script to ${pubdns}" >> ${logfile} 2>&1        
        # validate "ssh -i ${keypair_location}/${KEYNAME} ${USER}@${pubdns} \"screen -S server -d -m bash ${LOCATION}/base-setup.sh ${role} \""  "${role} ${index}: Kicking off the base setup script remotely.." >> ${logfile} 2>&1
        
        if [[ ! -z ${jmeter_lib_ext_files} ]]; then
            validate "ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} \"mkdir -p ${LOCATION}/libextfiles \"" "${role} ${index}: Creating ${LOCATION}\libextfiles directory on ${pubdns}" >> ${logfile} 2>&1
            for f in $(echo $jmeter_lib_ext_files | sed "s/,/ /g")
            do
                validate "scp -o StrictHostKeyChecking=no -i ${key_file_with_path} ${f} ${USER}@${pubdns}:${LOCATION}/libextfiles/ " "${role} ${index}: Scp jmeter lib ext file(s) to ${pubdns}" >> ${logfile} 2>&1
            done
        fi
        if [[ ! -z ${jmeter_lib_ext_archive} ]]; then
            validate "ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} \"mkdir -p ${LOCATION}/libextzips \"" "${role} ${index}: Creating ${LOCATION}\libextzips directory on ${pubdns}" >> ${logfile} 2>&1
            for f in $(echo $jmeter_lib_ext_archive | sed "s/,/ /g")
            do
                validate "scp -o StrictHostKeyChecking=no -i ${key_file_with_path} ${f} ${USER}@${pubdns}:${LOCATION}/libextzips/ " "${role} ${index}: Scp jmeter lib ext zip file(s) to ${pubdns}" >> ${logfile} 2>&1
            done
        fi

        if [[ ! -z ${keystore_location} ]]; then
            validate "ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} \"mkdir -p ${LOCATION}/keystore \"" "${role} ${index}: Creating ${LOCATION}\stores directory on ${pubdns}" >> ${logfile} 2>&1
            validate "scp -o StrictHostKeyChecking=no -i ${key_file_with_path} ${keystore_location} ${USER}@${pubdns}:${LOCATION}/keystore/ " "${role} ${index}: Scp keystore file to ${pubdns}" >> ${logfile} 2>&1
            validate "echo ${keystore_password} | ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} \"touch ${LOCATION}/keystore/.password && cat >> ${LOCATION}/keystore/.password \"" "Adding ks password file"
            
        fi

        if [[ ! -z ${truststore_location} ]]; then
            validate "ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} \"mkdir -p ${LOCATION}/truststore \"" "${role} ${index}: Creating ${LOCATION}\stores directory on ${pubdns}" >> ${logfile} 2>&1
            validate "scp -o StrictHostKeyChecking=no -i ${key_file_with_path} ${truststore_location} ${USER}@${pubdns}:${LOCATION}/truststore/ " "${role} ${index}: Scp truststore file to ${pubdns}" >> ${logfile} 2>&1
            validate "echo ${truststore_password} | ssh -o StrictHostKeyChecking=no -i ${key_file_with_path} ${USER}@${pubdns} \"touch ${LOCATION}/truststore/.password && cat >> ${LOCATION}/truststore/.password \"" "Adding ts password file"
        fi

        #removing key, shouldn't require key after public key has been added
        validate "scp -o StrictHostKeyChecking=no -i ${key_file_with_path} ${PWD}/base-setup.sh ${USER}@${pubdns}:${LOCATION}/ " "${role} ${index}: Scp setup script to ${pubdns}" >> ${logfile} 2>&1    
        validate "ssh -i ${key_file_with_path} ${USER}@${pubdns} \"screen -S server -d -m bash ${LOCATION}/base-setup.sh ${role} \""  "${role} ${index}: Kicking off the base setup script remotely.." >> ${logfile} 2>&1
    fi

}   

does_cluster_already_exist() {
    clusterName="$1"
    answer="No"
    if [[ -z ${vpcid} ]];
    then        
        vpcid=`get_vpc_id`
        if [[ -z ${vpcid} ]];
        then
            echo "Can't retreive Id for ${VPC_NAMING}, it probably doesn't exist" >> ${logfile} 2>&1
            echo ${answer}
            return
        fi
    fi
    
    
    if [[ ! -z ${clusterName} ]];
    then
        existingClusters=`aws ec2 describe-tags --filters "Name=resource-id,Values=${vpcid}" "Name=key,Values=Clusters" | grep "\"Value\"" | cut -d":" -f2 | cut -d"\"" -f2`
        if [[ ${existingClusters} == *"${clusterName}"* ]];
        then
            
            for cluster in ${existingClusters//,/ };
            do
                cluster_=`echo "${cluster}" | tr '[:upper:]' '[:lower:]'`
                clusterName_=`echo "${clusterName}" | tr '[:upper:]' '[:lower:]'`

                
                if [[ ${cluster_} == ${clusterName_} ]];
                then
                    answer="Yes"
                    break
                fi
            done
        fi
    fi

    echo ${answer}

}

add_cluster_to_vpc_tag () {
    clusterName="$1"
    if [[ ! -z ${clusterName} && ! -z ${vpcid} ]];
    then
        existingClusters=`aws ec2 describe-tags --filters "Name=resource-id,Values=${vpcid}" "Name=key,Values=Clusters" | grep "\"Value\"" | cut -d":" -f2 | cut -d"\"" -f2`
        if [[ ! -z ${existingClusters} ]];
        then
            validate "aws ec2 create-tags --resources ${vpcid} --tags \"Key=Clusters,Value='\"${existingClusters},${clusterName}\"'\" >> ${logfile} 2>&1" "Adding ${clusterName} to vpc's Clusters tag"
        else
            validate "aws ec2 create-tags --resources ${vpcid} --tags \"Key=Clusters,Value=${clusterName}\" >> ${logfile} 2>&1" "Adding ${clusterName} to vpc's Clusters tag"
        fi
    else
        echo "Invalid cluster Name or vpc Id (while trying to add cluster to the vpc's Clusters tag)"
    fi
}

get_vpc_id () {
    echo "Retreiving VPC Id " >> ${logfile} 2>&1
    if [[ ! -z ${reuseVpcId} ]]; then 
        vpcid=${reuseVpcId}
    else
        vpcid=$(aws ec2 describe-vpcs --filter Name=tag:Name,Values="${VPC_NAMING}" | grep "VpcId"| cut -d":" -f2 | cut -d"\"" -f2)
    fi
    echo $vpcid
    
}

remove_cluster_from_vpc_tag () {
    clusterName="$1"
    if [[ -z ${vpcid} ]];
    then        
        vpcid=`get_vpc_id`
        if [[ -z ${vpcid} ]];
        then
            echo "Unable to retreive VPC Id for ${VPC_NAMING}, it's possible that it doesn't exist" >> ${logfile} 2>&1
            return
        fi
    fi

    if [[ ! -z ${clusterName} ]];
    then
        existingClusters=`aws ec2 describe-tags --filters "Name=resource-id,Values=${vpcid}" "Name=key,Values=Clusters" | grep "\"Value\"" | cut -d":" -f2 | cut -d"\"" -f2`
        if [[ ${existingClusters} == *"${clusterName}"* ]];
        then
            for cluster in ${existingClusters//,/ };
            do
                if [[ ${cluster} != ${clusterName} ]];
                then
                    if [[ -z ${clustersLeft} ]];
                    then
                        clustersLeft="${cluster}"
                    else
                        clustersLeft="${clustersLeft},${cluster}"
                    fi
                fi
            done
            validate "aws ec2 create-tags --resources ${vpcid} --tags \"Key=Clusters,Value='\"${clustersLeft}\"'\" >> ${logfile} 2>&1" "Removing ${clusterName} from vpc's Clusters tag"
        else
            echo "${clusterName} not found in the vpc's Clusters tag" >> ${logfile} 2>&1
        fi
    fi
}

create_vpc () {
    if [[ -z ${AWS_AVAILABILITY_ZONE} ]]; then echo "AWS Availability Zone not set, quitting.."; fi
    if [[ -a "${deletion_in_progress_file}" ]]; then echo -e "\n\tPlease wait 1-2 minutes while existing VPCs are being deleted and retry"; exit 1; fi

    folderName=${assetsFolder}/vpc/${AWS_AVAILABILITY_ZONE}
    if [[ ! -d ${folderName} ]]; then mkdir -p ${folderName}; fi
    
    # existingVpc=$(aws ec2 describe-vpcs | grep -i "${VPC_NAMING}" | cut -d":" -f 2 | cut -d"\"" -f 2)
    existingVpc=$(aws ec2 describe-vpcs --filter Name=tag:Name,Values="${VPC_NAMING}" | tee /tmp/vpc-details 2>&1 | grep "${VPC_NAMING}" | cut -d":" -f 2 | cut -d"\"" -f 2)
    
    # only create vpc if it doesn't already exist
    if [[ "${existingVpc}" != "${VPC_NAMING}"  ]]; then
        #delete existing asset files, since recreating a new vpc
        rm -rf ${folderName}/*.*
        echo "${aws_region},${AWS_AVAILABILITY_ZONE}" > ${folderName}/region.info
        
        generate_key_pair_if_not_there
        #2>&1 > ${logfile}
        validate "aws ec2 create-vpc --cidr-block 192.168.0.0/20 |tee ${folderName}/vpc >> ${logfile} 2>&1" "Creating VPC in ${aws_region}" 
        vpcid=`cat ${folderName}/vpc|grep VpcId |cut -d "\"" -f4`
        validate "aws ec2 modify-vpc-attribute --vpc-id $vpcid --enable-dns-hostnames '{\"Value\":true}' >> ${logfile} 2>&1" "Enabling dns hostnames"  

        validate "aws ec2 create-tags --resources $vpcid --tags \"Key=Name,Value=${VPC_NAMING}\" >> ${logfile} 2>&1" "Applying tag to the vpc ($vpcid)"

        # echo "aws ec2 create-subnet --vpc-id $vpcid --cidr-block 192.168.0.0/24 --availability-zone $AWS_AVAILABILITY_ZONE|tee ${folderName}/subnet"
        validate "aws ec2 create-subnet --vpc-id $vpcid --cidr-block 192.168.0.0/24 --availability-zone $AWS_AVAILABILITY_ZONE|tee ${folderName}/subnet >> ${logfile} 2>&1" "Creating subnet"
        pubsubnet=`cat ${folderName}/subnet|grep SubnetId |cut -d "\"" -f4`
        validate "aws ec2 create-tags --resources $pubsubnet --tags \"Key=Name,Value=${NAMING_SUFFIX}_Subnet\" >> ${logfile} 2>&1" "Applying tag to the subnet ($pubsubnet)"

        validate "aws ec2 create-internet-gateway |tee ${folderName}/igateway >> ${logfile} 2>&1" "Creating internet gateway"
        igateway=`cat ${folderName}/igateway|grep InternetGatewayId|cut -d "\"" -f4`
        validate "aws ec2 create-tags --resources $igateway --tags \"Key=Name,Value=${NAMING_SUFFIX}_iGateway\" >> ${logfile} 2>&1" "Applying tag to the internet gateway ($igateway)"

        validate "aws ec2 attach-internet-gateway --internet-gateway-id $igateway --vpc-id $vpcid >> ${logfile} 2>&1" "Attaching internet gateway to the vpc"

        validate "aws ec2 create-route-table --vpc-id $vpcid|tee ${folderName}/routetable >> ${logfile} 2>&1" "Creating route table"
        pubroute=`cat ${folderName}/routetable|grep RouteTableId|cut -d "\"" -f4`
        validate "aws ec2 create-tags --resources $pubroute --tags \"Key=Name,Value=${NAMING_SUFFIX}_RouteTable\" >> ${logfile} 2>&1" "Applying tag to the route table ($pubroute)"
        validate "aws ec2 associate-route-table --route-table-id $pubroute --subnet-id $pubsubnet >> ${logfile} 2>&1" "Associating route table to the subnet"
        validate "aws ec2 create-route --route-table-id $pubroute --destination-cidr-block 0.0.0.0/0 --gateway-id $igateway >> ${logfile} 2>&1" "Creating route between the route table and the internet gateway"



        # setup_security_groups
        clientSG=`create_security_group $vpcid ${folderName} "client"`
        serverSG=`create_security_group $vpcid ${folderName} "server"`

        # create_security_groups ${vpcid} ${folderName}
        # validate "aws ec2 create-security-group --group-name ${NAMING_SUFFIX}_Client_SG --description \"${NAMING_SUFFIX}_Client_SG\" --vpc-id $vpcid  |tee ${folderName}/clientsg >> ${logfile} 2>&1" "Creating security group for client instances"
        # export clientSG=`cat ${folderName}/clientsg|grep GroupId|cut -d "\"" -f4`
        # validate "aws ec2 create-tags --resources $clientSG --tags \"Key=Name,Value=${NAMING_SUFFIX}_Client_SG\" >> ${logfile} 2>&1" "Applying tag to the client security group ($clientSG)"
        
        # validate "aws ec2 create-security-group --group-name ${NAMING_SUFFIX}_Server_SG --description \"${NAMING_SUFFIX}_Server_SG\" --vpc-id $vpcid  |tee ${folderName}/serversg >> ${logfile} 2>&1" "Creating security group for server instances"
        # export serverSG=`cat ${folderName}/serversg|grep GroupId|cut -d "\"" -f4`
        # validate "aws ec2 create-tags --resources $serverSG --tags \"Key=Name,Value=${NAMING_SUFFIX}_Server_SG\" >> ${logfile} 2>&1" "Applying tag to the server security group ($serverSG)"
        
        ## Add all ids to vpc as tags (so its easy to delete them)
        validate "aws ec2 create-tags --resources $vpcid --tags \"Key=RouteTableId,Value=${pubroute}\"  \"Key=SubnetId,Value=${pubsubnet}\" \
        \"Key=InternetGatewayId,Value=${igateway}\" \"Key=ClientSGId,Value=${clientSG}\" \"Key=ServerSGId,Value=${serverSG}\"  \
        >> ${logfile} 2>&1" "Applying tag to the vpc ($vpcid)"

        
    else 
        # retreive ids for existing assets for reuse
        # adding code to make this independent of keeping local cache (.asset folder)
        export vpcid=`cat /tmp/vpc-details | grep "VpcId"| cut -d":" -f2 | cut -d"\"" -f2`        
        export pubsubnet=`aws ec2 describe-subnets --filter Name=tag:Name,Values="${NAMING_SUFFIX}_Subnet"  | grep "SubnetId"| cut -d":" -f2 | cut -d"\"" -f2`
        export clientSG=`aws ec2 describe-security-groups --filter Name=tag:Name,Values="${NAMING_SUFFIX}_client_SG"  | grep "GroupId"| cut -d":" -f2 | cut -d"\"" -f2`
        export serverSG=`aws ec2 describe-security-groups --filter Name=tag:Name,Values="${NAMING_SUFFIX}_server_SG"  | grep "GroupId"| cut -d":" -f2 | cut -d"\"" -f2`
        if [[ -z $vpcid || -z ${pubsubnet} || -z ${clientSG} || -z ${serverSG} ]]; 
        then 
            echo "Couldn't retreive one or more of the (vpc:${vpcid}, subnet:${pubsubnet} or security group:${clientSG},${serverSG} ) id of the already existing vpc, quitting "; 
            exit 1; 
        fi

        generate_key_pair_if_not_there

    fi
}


create_security_group () {
    vpcid=$1
    folderName=$2
    sg_instance_type=$3

    if [[ -z ${vpcid} || -z ${folderName} ]]; then echo -e "Please provide a vpc id and a folderName to use for security group creation, quitting.."; exit 1; fi
    if [[ ${sg_instance_type} != "client" && ${sg_instance_type} != "server" ]]; then echo -e "Please specify what instance type is this security group for, client or server? quitting.."; exit 1; fi

    validate "aws ec2 create-security-group --group-name ${NAMING_SUFFIX}_${sg_instance_type}_SG --description \"${NAMING_SUFFIX}_${sg_instance_type}_SG\" --vpc-id $vpcid  |tee ${folderName}/${sg_instance_type}sg >> ${logfile} 2>&1" "Creating security group for ${sg_instance_type} instances"
    export sgId=`cat ${folderName}/${sg_instance_type}sg|grep GroupId|cut -d "\"" -f4`
    validate "aws ec2 create-tags --resources $sgId --tags \"Key=Name,Value=${NAMING_SUFFIX}_${sg_instance_type}_SG\" >> ${logfile} 2>&1" "Applying tag to the ${sg_instance_type} security group ($sgId)"

    validate "aws ec2 create-tags --resources $vpcid --tags \"Key=jmeter_${sg_instance_type}_SG,Value=$sgId\" >> ${logfile} 2>&1" "Applying jmeter ${sg_instance_type} sg tag to the vpc ($vpcid)"
    setup_security_group ${sgId}
    echo $sgId
}


reuse_vpc () {
    reuseSubnet=$2
    reuseVpcId=$1
    if [[ -z ${reuseVpcId} || -z ${reuseSubnet} ]]; then echo -e "Please provide a vpc id and a subnet id to be re used, quitting.."; exit 1; fi

    if [[ ! -d ${assetsFolder}/vpc ]]; then mkdir ${assetsFolder}/vpc; fi
    folderName=${assetsFolder}/vpc/${AWS_AVAILABILITY_ZONE}
    
    export vpcid=${reuseVpcId}
    export pubsubnet=${reuseSubnet}

    generate_key_pair_if_not_there
 
    existingClientSG=`aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpcid}" "Name=group-name,Values=jmeter_client_SG" | grep "\"GroupName\": \"jmeter_client_SG\"" | wc -l`
    existingServerSG=`aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpcid}" "Name=group-name,Values=jmeter_server_SG" | grep "\"GroupName\": \"jmeter_server_SG\"" | wc -l`
    
    existingClientSG=${existingClientSG// /}
    existingServerSG=${existingServerSG// /}


    if [[ ${existingServerSG} == 0 ]]; then
        export serverSG=`create_security_group ${vpcid} "${folderName}" "server"`
    fi
    if [[ ${existingClientSG} == 0 ]]; then
        export clientSG=`create_security_group ${vpcid}  "${folderName}" "client"`
    fi

}

## Deprecated: Uses local persistance
delete_all_vpcs () {
    now="$1"
    if [[ ${now} != "now" ]]; 
    then
        sleep 60
    fi

    original_default_region=${aws_region}
    for aws_zone in `ls -d ${assetsFolder}/vpc/*/ | cut -f3 -d'/'`; # filter for only directories in vpc folder
    do
        current_region=`cat ${assetsFolder}/vpc/${aws_zone}/region.info 2> /dev/null | cut -d"," -f1`
        if [[ $current_region != $original_default_region && ! -z ${current_region} ]];
        then
            aws configure set default.region ${current_region}
            region_changed="true"
        fi
        
        echo "About to delete vpc in region: ${aws_zone}" >> ${logfile}
        delete_vpc ${aws_zone}

        if [[ $region_changed == "true" ]];
        then
            aws configure set default.region ${original_default_region}
            region_changed=""
        fi
    done

    rm -rf "${deletion_in_progress_file}"

}

## Deprecated: Uses local persistance
eventually_delete_all_vpcs () {
    now="$1"
    when="in a couple of minutes"
    if [[ "${now}" == "now" ]]; then
        when="${now}"
    fi
    echo "All VPCs will be deleted ${when}."
    touch "${deletion_in_progress_file}"
    delete_all_vpcs "${now}" &
}



eventually_delete_vpc_aws () {
    now="$1"
    vpcid="$2"
    if [[ -z ${vpcid} ]]; then
        vpcid_numberOfClusters=`get_number_of_clusters_aws` 
        vpcid=`echo $vpcid_numberOfClusters | cut -d"," -f1`
    fi

    when="in a couple of minutes"
    if [[ "${now}" == "now" ]]; then
        when="${now}"
    fi
    echo "VPC will be deleted ${when}."
    touch "${deletion_in_progress_file}"
    delete_vpc_aws "${now}" "${vpcid}"&
}

delete_vpc_aws () {
    now="$1"
    vpcid="$2"

    tags=`aws ec2 describe-tags --filters "Name=resource-id,Values=$vpcid"`
    keys=`echo "$tags" | grep  "\"Key\":" | cut -d":" -f 2`
    values=`echo "$tags" | grep  "\"Value\":" | cut -d":" -f 2`

    length=`echo "$keys" | wc -l`
    for i in `seq 1 $length`; do 
        key=`echo ${keys//\"/} | cut -d" " -f$i`;
        if [[ $key != "Name" && $key != "Clusters" ]]; then 
            value=`echo ${values//\"/} | cut -d"," -f$i`;
            value=${value// /}
            echo "Deleting entity with $key=$value"
            case $key in #*"us-east"* 
                *"ClientSG"* ) clientSG=$value; continue;;
                *"ServerSG"* ) serverSG=$value; continue;;
                *"InternetGateway"* ) igateway=$value; continue;;
                *"RouteTable"* ) pubroute=$value; continue;;
                *"Subnet"* ) pubsubnet=$value; continue;;
            esac
            # validate_ignore_notfound "aws ec2 delete-security-group --group-id ${clientSG}" "Deleting client security group (${clientSG})" >> ${logfile} 2>&1
        fi; 
    done
    
    if [[ -z ${clientSG} || -z ${serverSG} || -z ${igateway} || -z ${pubroute} || -z ${pubsubnet} ]]; then
        echo "One or more of the IDs are missing (SG:${clientSG},${serverSG} , IGateway:${igateway}, Subnet:${pubsubnet} or RouteTable:${pubroute})"
        return
    fi

    if [[ ${now} != "now" ]]; 
    then
        sleep 60
    fi

    if [[ ! -z $vpcid ]]; 
    then 
        echo -e "\nStarting deletion of VPC in ${aws_region}" >> ${logfile}
        # delete_key_pair
        remove_key_pair 
        if [[ -z $clientSG ]]; 
        then 
            echo "No clientSG id found: ${clientSG}";
        else
            validate_ignore_notfound "aws ec2 delete-security-group --group-id ${clientSG}" "Deleting client security group (${clientSG})" >> ${logfile} 2>&1
        fi

        if [[ -z $serverSG ]]; 
        then 
            echo "No serverSG id found: ${serverSG}";        
        else
            validate_ignore_notfound "aws ec2 delete-security-group --group-id ${serverSG}" "Deleting server security group (${serverSG})" >> ${logfile} 2>&1
        fi
        
        if [[ -z $igateway ]]; 
        then 
            echo "No igateway id found: ${igateway}";
        else
            validate_ignore_notfound "aws ec2 detach-internet-gateway --internet-gateway-id ${igateway} --vpc-id $vpcid" "Detaching iGateway from VPC" >> ${logfile} 2>&1
            validate_ignore_notfound "aws ec2 delete-internet-gateway --internet-gateway-id ${igateway}" "Deleting IGateway (${igateway})" >> ${logfile} 2>&1
        fi
        
        
        if [[ -z $pubsubnet ]]; 
        then 
            echo "No pubsubnet id found: ${pubsubnet}";
        else
            validate_ignore_notfound "aws ec2 delete-subnet --subnet-id ${pubsubnet}" "Deleting Subnet (${pubsubnet})" >> ${logfile} 2>&1
        fi
        
        if [[ -z $pubroute ]]; 
        then 
            echo "No pubroute id found: ${pubroute}";
        else    
            validate_ignore_notfound "aws ec2 delete-route-table --route-table-id ${pubroute}" "Deleting Route Table (${pubroute})" >> ${logfile} 2>&1
        fi

        validate_ignore_notfound "aws ec2 delete-vpc --vpc-id ${vpcid}" "Deleting VPC (${vpcid})" >> ${logfile} 2>&1
    else
        echo "No vpcid id provided to delete_vpc_aws: >${vpcid}<";
    fi
    
    rm -rf "${deletion_in_progress_file}"
}

## Deprecated: Uses local persistance
delete_vpc() {
    aws_zone="$1"
    if [[ -z ${aws_zone} ]]; then echo "Availability zone not provided, quitting.."; fi
    if [[ ! -a ${assetsFolder}/vpc/${aws_zone}/vpc ]]; then echo "No VPCs exists"; exit 0; fi

    vpcid=`cat ${assetsFolder}/vpc/${aws_zone}/vpc|grep VpcId |cut -d "\"" -f4`
    pubsubnet=`cat ${assetsFolder}/vpc/${aws_zone}/subnet|grep SubnetId |cut -d "\"" -f4`
    igateway=`cat ${assetsFolder}/vpc/${aws_zone}/igateway|grep InternetGatewayId|cut -d "\"" -f4`
    pubroute=`cat ${assetsFolder}/vpc/${aws_zone}/routetable|grep RouteTableId|cut -d "\"" -f4`
    clientSG=`cat ${assetsFolder}/vpc/${aws_zone}/clientsg|grep GroupId|cut -d "\"" -f4`
    serverSG=`cat ${assetsFolder}/vpc/${aws_zone}/serversg|grep GroupId|cut -d "\"" -f4`
    
    
    
    if [[ ! -z $vpcid ]]; 
    then 
        echo -e "\nStarting deletion of VPC in ${aws_zone}" >> ${logfile}
        delete_key_pair 
        if [[ -z $clientSG ]]; 
        then 
            echo "No clientSG id found: ${clientSG}";
        else
            validate_ignore_notfound "aws ec2 delete-security-group --group-id ${clientSG}" "Deleting client security group (${clientSG})" >> ${logfile} 2>&1
        fi

        if [[ -z $serverSG ]]; 
        then 
            echo "No serverSG id found: ${serverSG}";        
        else
            validate_ignore_notfound "aws ec2 delete-security-group --group-id ${serverSG}" "Deleting server security group (${serverSG})" >> ${logfile} 2>&1
        fi
        
        if [[ -z $igateway ]]; 
        then 
            echo "No igateway id found: ${igateway}";
        else
            validate_ignore_notfound "aws ec2 detach-internet-gateway --internet-gateway-id ${igateway} --vpc-id $vpcid" "Detaching iGateway from VPC" >> ${logfile} 2>&1
            validate_ignore_notfound "aws ec2 delete-internet-gateway --internet-gateway-id ${igateway}" "Deleting IGateway (${igateway})" >> ${logfile} 2>&1
        fi
        
        
        if [[ -z $pubsubnet ]]; 
        then 
            echo "No pubsubnet id found: ${pubsubnet}";
        else
            validate_ignore_notfound "aws ec2 delete-subnet --subnet-id ${pubsubnet}" "Deleting Subnet (${pubsubnet})" >> ${logfile} 2>&1
        fi
        
        if [[ -z $pubroute ]]; 
        then 
            echo "No pubroute id found: ${pubroute}";
        else    
            validate_ignore_notfound "aws ec2 delete-route-table --route-table-id ${pubroute}" "Deleting Route Table (${pubroute})" >> ${logfile} 2>&1
        fi

        validate_ignore_notfound "aws ec2 delete-vpc --vpc-id ${vpcid}" "Deleting VPC (${vpcid})" >> ${logfile} 2>&1
    else
        echo "No vpcid id found: ${vpcid}, deleting everything else..";
    fi

    validate "rm -rf ${assetsFolder}/vpc/${aws_zone}" "Removing the VPC folder for ${aws_zone} " >> ${logfile} 2>&1 
    
    remaningVpcs=`ls -d ${assetsFolder}/vpc/*/ 2> /dev/null| wc -l`
    remaningVpcs=${remaningVpcs// /}
    
    
    if [[ $remaningVpcs == 0 ]];
    then
        validate "rm -rf ${assetsFolder}/vpc" "Removing the VPC folder since no more vpcs are left.." >> ${logfile} 2>&1   
    fi

    
}

setup_security_group () 
{
    sgid="$1"
    if [[ -z ${sgid} ]]; then echo "Please provide a security group id to set up.. "; exit 1; fi

    validate "aws ec2 authorize-security-group-ingress --group-id $sgid --protocol tcp --port 80 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 80)" 
    validate "aws ec2 authorize-security-group-ingress --group-id $sgid --protocol tcp --port 22 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 22)"
    validate "aws ec2 authorize-security-group-ingress --group-id $sgid --protocol tcp --port 1099 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 1099)"
    validate "aws ec2 authorize-security-group-ingress --group-id $sgid --protocol tcp --port 4001 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 4001)"
    validate "aws ec2 authorize-security-group-ingress --group-id $sgid --protocol tcp --port 7000 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 7000)"
}

setup_security_groups () 
{
    validate "aws ec2 authorize-security-group-ingress --group-id $clientSG --protocol tcp --port 80 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 80)" 
    validate "aws ec2 authorize-security-group-ingress --group-id $clientSG --protocol tcp --port 22 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 22)"
    validate "aws ec2 authorize-security-group-ingress --group-id $clientSG --protocol tcp --port 1099 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 1099)"
    validate "aws ec2 authorize-security-group-ingress --group-id $clientSG --protocol tcp --port 4001 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 4001)"
    validate "aws ec2 authorize-security-group-ingress --group-id $clientSG --protocol tcp --port 7000 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for client (Port 7000)"

    validate "aws ec2 authorize-security-group-ingress --group-id $serverSG --protocol tcp --port 80 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for server (Port 80)"
    validate "aws ec2 authorize-security-group-ingress --group-id $serverSG --protocol tcp --port 22 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for server (Port 22)"
    validate "aws ec2 authorize-security-group-ingress --group-id $serverSG --protocol tcp --port 1099 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for server (Port 1099)"
    validate "aws ec2 authorize-security-group-ingress --group-id $serverSG --protocol tcp --port 4001 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for server (Port 4001)"
    validate "aws ec2 authorize-security-group-ingress --group-id $serverSG --protocol tcp --port 7000 --cidr 0.0.0.0/0 >> ${logfile} 2>&1" "Setting up security groups for server (Port 7000)"
    
    
}


function validate_ignore_notfound { #usage validate "command to run" "description of command"
    #echo "1: $1, 2: $2"
    result=$(eval "$1 2>&1" )
    local status=$?
    # echo "Result: $result"
    if [[ $result == *".NotFound"* ]];
    then
        result=`echo $result | cut -d":" -f2` 
        echo "$result. ignoring this error"
        return 0
    fi
    
    if [ $status -ne 0 ]; then
        echo -e "\nFailure: $2 while $1"
        exit 1
    else
        echo "OK: $2" >&2
    fi
    return $status
}

get_number_of_clusters() {
    if [[ ! -d ${assetsFolder}/clusters ]]; 
    then 
        numberOfClusters=0
    else
        numberOfClusters=$(ls ${assetsFolder}/clusters/ 2>/dev/null | wc -l)
        numberOfClusters=${numberOfClusters// /}
    fi
    echo ${numberOfClusters}
}

get_number_of_clusters_aws() {
    numberOfClusters=0
    if [[ -z $vpcid ]]; then
        vpcid=`get_vpc_id`
    fi
    if [[ ! -z $vpcid ]]; then
        existingClusters=`aws ec2 describe-tags --filters "Name=resource-id,Values=${vpcid}" "Name=key,Values=Clusters" | grep "\"Value\"" | cut -d":" -f2 | cut -d"\"" -f2`
        if [[ ! -z ${existingClusters} ]]; then
            numberOfClusters=`echo $existingClusters | tr , '\n' | wc -l`
            numberOfClusters=${numberOfClusters// /} #removing whitespace
        fi
    fi
    
    echo ${vpcid},${numberOfClusters}
    
}
 


error_if_no_clusters_exist () {
    noClustersExist="No clusters exist.. \n\tUse \"-cdc | ccc <cluster-name>\" to create one"
    if [[ `get_number_of_clusters` == "0" ]]; then echo -e ${noClustersExist}; exit 0; fi
}

status_aws_old () {
    echo "Selected AWS Region: ${aws_region} (change this by --set-aws-region <region>)"
    vpcid_numberOfClusters=`get_number_of_clusters_aws` 
    vpcid=`echo $vpcid_numberOfClusters | cut -d"," -f1`
    numberOfClusters=`echo $vpcid_numberOfClusters | cut -d"," -f2`
    # echo "vpcid_numberOfClusters: $vpcid_numberOfClusters"
    if [[ ! -z $vpcid ]]; then
        # echo "Unable to get info about vpc ($vpcid)"; 
        # echo "No VPC exist in ${aws_region}"
        #exit 1; 
    # else
        echo "VPC ($vpcid) exists in ${aws_region}"
    fi

    if [[ -z $numberOfClusters ]]; then echo "Unable to get info about number of clusters from vpc's tag"; exit 1; fi

    

    if [[ $numberOfClusters == 0 ]];then
        echo -e "No clusters exist.. \n\tUse \"-cdc | ccc <cluster-name>\" to create one"
    fi
    
    if [[ $numberOfClusters > 0 ]];then
        if [[ $numberOfClusters > 1 ]];then
            echo -e "\n\t$numberOfClusters clusters exist"
        else 
            echo -e "\n\t$numberOfClusters cluster exists"
        fi

        existingClusters=`aws ec2 describe-tags --filters "Name=resource-id,Values=${vpcid}" "Name=key,Values=Clusters" | grep "\"Value\"" | cut -d":" -f2 | cut -d"\"" -f2`
        for cluster in ${existingClusters//,/ }; do
            echo -e "\n\t**** Name: ${cluster}"
            client_instances=`get_instances_of_role_in_cluster_aws "client" "$cluster"`
            server_instances=`get_instances_of_role_in_cluster_aws "server" "$cluster"`

            # echo "server_instances: $server_instances"
            numClient=`echo $client_instances | tr , "\n" | wc -l`
            numServer=`echo $server_instances | tr , "\n" | wc -l`
            numClient=${numClient// /}
            numServer=${numServer// /}

            if [[ "$client_instances" != "None" ]]; then 
                echo -e "\t${numClient} Client:\n\t\t$client_instances"
            fi
            if [[ "$server_instances" != "None" ]]; then 
                server_instances=${server_instances// /}                
                echo -e "\t${numServer} Server(s):"
                for server in ${server_instances//,/ }; 
                do 
                    echo -e "\t\t${server}"
                done
            fi
        done
    
    fi
}


status_aws () {
    option="$1"
    easy_parse_option="easy_parse"

    if [[ -z $option || $option != $easy_parse_option ]]; then 
        echo "Selected AWS Region: ${aws_region} (change this by --set-aws-region <region>)"
    fi

    vpcid_numberOfClusters=`get_number_of_clusters_aws` 
    vpcid=`echo $vpcid_numberOfClusters | cut -d"," -f1`
    numberOfClusters=`echo $vpcid_numberOfClusters | cut -d"," -f2`
    # echo "vpcid_numberOfClusters: $vpcid_numberOfClusters"
    if [[ ! -z $vpcid ]]; then
        if [[ -z $option || $option != $easy_parse_option ]]; then 
            echo "VPC ($vpcid) exists in ${aws_region}"
        fi
    fi

    if [[ -z $numberOfClusters ]]; then echo "Unable to get info about number of clusters from vpc's tag"; exit 1; fi

    

    if [[ $numberOfClusters == 0 ]];then
        if [[ -z $option || $option != $easy_parse_option ]]; then 
            echo -e "No clusters exist.. \n\tUse \"-cdc | ccc <cluster-name>\" to create one"
        else
            echo -e "\n\t0 clusters exist"
        fi
    fi
    
    if [[ $numberOfClusters > 0 ]];then
        if [[ $numberOfClusters > 1 ]];then
            echo -e "\n\t$numberOfClusters clusters exist"
        else 
            echo -e "\n\t$numberOfClusters cluster exists"
        fi

        existingClusters=`aws ec2 describe-tags --filters "Name=resource-id,Values=${vpcid}" "Name=key,Values=Clusters" | grep "\"Value\"" | cut -d":" -f2 | cut -d"\"" -f2`
        for cluster in ${existingClusters//,/ }; 
        do
            if [[ -z $option || $option != $easy_parse_option ]]; then 
                echo -e "\n\t**** Name: ${cluster}"
            else
                cluster_line_item="Name:${cluster}"
            fi
            client_instances=`get_instances_of_role_in_cluster_aws "client" "$cluster"`
            server_instances=`get_instances_of_role_in_cluster_aws "server" "$cluster"`

            # echo "server_instances: $server_instances"
            numClient=`echo $client_instances | tr , "\n" | wc -l`
            numServer=`echo $server_instances | tr , "\n" | wc -l`
            numClient=${numClient// /}
            numServer=${numServer// /}
            
            

            if [[ "$client_instances" != "None" ]]; then 
                if [[ -z $option || $option != $easy_parse_option ]]; then 
                    echo -e "\t${numClient} Client:\n\t\t$client_instances"
                else
                    cluster_line_item="$cluster_line_item|Client:${client_instances}"
                fi
            fi
            if [[ "$server_instances" != "None" ]]; then 
                server_instances=${server_instances// /}                
                if [[ -z $option || $option != $easy_parse_option ]]; then 
                    echo -e "\t${numServer} Server(s):"
                else
                    cluster_line_item="$cluster_line_item|Servers:"
                fi
                for server in ${server_instances//,/ }; 
                do
                    if [[ -z $option || $option != $easy_parse_option ]]; then  
                        echo -e "\t\t${server}"
                    else
                        cluster_line_item="${cluster_line_item}${server},"
                    fi
                done
            fi
        if [[ $option == $easy_parse_option ]]; then
            echo "${cluster_line_item}"
        fi
        done
    
    fi
}

status () {
    verify="$1"
    if [[ "${verify}" != "verify" ]]; then verify=""; fi
    echo "Default AWS Region: ${aws_region}"
    
    error_if_no_clusters_exist
    numberOfClusters=`get_number_of_clusters`
    if [[ $numberOfClusters > 0 ]]; then 
        echo -e "\n\t$numberOfClusters cluster(s) exist"
        
        for cluster in `ls ${assetsFolder}/clusters/`; 
        do
            current_region=`cat ${assetsFolder}/clusters/${cluster}/region.info 2> /dev/null | cut -d"," -f1`
            if [[ -z $current_region ]]; then current_region="Unspecified"; fi
            
            echo -e "\n\t**** Name: ${cluster}\tRegion: $current_region ****"
            client_instances=`get_instances_of_role_in_cluster "client" "$cluster" "${verify}"`
            server_instances=`get_instances_of_role_in_cluster "server" "$cluster" "${verify}"`

            numClient=`echo $client_instances | tr , "\n" | wc -l`
            numServer=`echo $server_instances | tr , "\n" | wc -l`
            numClient=${numClient// /}
            numServer=${numServer// /}

            if [[ "$client_instances" != "None" ]]; then 
                echo -e "\t${numClient} Client:\n\t\t$client_instances"
            fi
            if [[ "$server_instances" != "None" ]]; then 
                server_instances=${server_instances// /}                
                echo -e "\t${numServer} Server(s):"
                for server in ${server_instances//,/ }; 
                do 
                    echo -e "\t\t${server}"
                done
            fi
        done
        
    fi
}

## Uses aws (and no local persistance) to retreive instances of a jmeter cluster
get_instances_of_role_in_cluster_aws () {
    role=$1 
    cluster=$2
    ids="$3" # by default this will return dns names of the instances, but it'll return instance ids if $3 = InstanceId
    toRetreive="PublicDnsName" # default
    if [[ ${ids} == "InstanceId" ]]; then toRetreive="InstanceId"; fi

    allowed_states="running,pending,initializing"

    clusterExists=`does_cluster_already_exist ${cluster}`
    
    if [[ $clusterExists != "Yes" ]]; then 
        echo -e "Cluster \"$cluster\" doesn't exist.. \n(error while getting instances of role $role from cluster $cluster)"; 
        return; 
    fi

    instances=`aws ec2 describe-instances --filters "Name=tag:Cluster,Values=${cluster}"  "Name=tag:Role,Values=${role}" \
    "Name=instance-state-name,Values=${allowed_states}" --query 'Reservations[*].Instances[*].['"${toRetreive}"']' \
    | grep -v "\[" | grep -v "\]"`

    instances=${instances//\"/} #clean out the quotes
    instances=`sed -e 's/[[:space:]]*$//' <<<$instances` # cleaning out the trailing/leading whitespaces 
    echo ${instances// /,} # replace the space with comma (to convert to csv)
}

## Uses local persistance to retreive instances of a jmeter cluster and 
## verifies (if asked) with aws if those instances exist
get_instances_of_role_in_cluster () {
    role=$1 
    cluster=$2
    verify=$3 
    error_if_cluster_doesnt_exist $cluster

    if [[ ! -a ${assetsFolder}/clusters/${cluster}/${role}/instances ]]; then echo "None"; exit 0; fi    

    result=""

    original_default_region=${aws_region}
    for line in `cat ${assetsFolder}/clusters/${cluster}/${role}/instances`;
    do
        ec2name=$(echo $line|cut -d"," -f3)
        
        if [[ "${verify}" == "verify" ]]; then
            # we might need to change default aws region to this cluster's region (and revert it)
            current_region=`cat ${assetsFolder}/clusters/${cluster}/region.info 2> /dev/null | cut -d"," -f1`
            if [[ $current_region != $original_default_region && ! -z ${current_region} ]];
            then
                aws configure set default.region ${current_region}
                region_changed="true"
            fi
            instanceId=$(echo $line|cut -d"," -f1)
            state=$(aws ec2 describe-instances --instance-id ${instanceId} 2> /dev/null | grep "\"Name\"" | grep -v "Key" | cut -d "\"" -f4)
            
            #revert if back
            if [[ $region_changed == "true" ]];
            then
                aws configure set default.region ${original_default_region}
                region_changed=""
            fi

            if [[ "${state}" == running ]]; 
            then 
                if [[ ! -z ${result} ]]; then 
                    result="${result},${ec2name}"
                else 
                    result="${ec2name}"
                fi
            else
                # echo "Invalid instance, removing";
                remove_instanceid_from_record  "$instanceId" "${assetsFolder}/clusters/${cluster}/${role}"
            fi
        else
            if [[ ! -z ${result} ]]; then 
                result="${result},${ec2name}"
            else 
                result="${ec2name}"
            fi
        fi

        
    done
    echo $result
}

delete_all_cluster_aws() {
    now="$1"
    delete_vpc_too="$2"
    vpcid_numberOfClusters=`get_number_of_clusters_aws` 
    vpcid=`echo $vpcid_numberOfClusters | cut -d"," -f1`
    numberOfClusters=`echo $vpcid_numberOfClusters | cut -d"," -f2`
    echo "Deleting everything in region: ${awsregion}" >> ${logfile} 2>&1
    if [[ $numberOfClusters > 0 ]]; 
    then
        existingClusters=`aws ec2 describe-tags --filters "Name=resource-id,Values=${vpcid}" "Name=key,Values=Clusters" \
                            | grep "\"Value\"" | cut -d":" -f2 | cut -d"\"" -f2`
        for cluster in $existingClusters;do
            delete_cluster_aws $cluster
        done
    fi 
    vpcid_numberOfClusters=`get_number_of_clusters_aws`
    numberOfClusters=`echo $vpcid_numberOfClusters | cut -d"," -f2`

    if [[ $numberOfClusters == 0 ]]; 
    then 
        echo -e "No (more) clusters exist in ${aws_region}"
        if [[ $delete_vpc_too == "Delete_VPC_Too" && -z ${reuseVpcId} ]]; then 
            echo -e "VPC Deletion option chosen (${now})"
            eventually_delete_vpc_aws "${now}" "${vpcid}"
        fi

        if [[ ! -z ${reuseVpcId} ]]; then
            echo -e "Deleting the jmeter security groups"
            clientsgid=`aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpcid}" "Name=group-name,Values=jmeter_client_SG" | grep "GroupId" | cut -d: -f2`
            serversgid=`aws ec2 describe-security-groups --filters "Name=vpc-id,Values=${vpcid}" "Name=group-name,Values=jmeter_server_SG" | grep "GroupId" | cut -d: -f2`
            validate_ignore_notfound "aws ec2 delete-security-group --group-id ${clientsgid}" "Deleting client security group (${clientsgid})" >> ${logfile} 2>&1
            validate_ignore_notfound "aws ec2 delete-security-group --group-id ${serversgid}" "Deleting server security group (${serversgid})" >> ${logfile} 2>&1
        fi

        if [[ ! -z ${provided_key_file} ]]; then
            generate_key_name_for_file ${provided_key_file}
            delete_keypair_if_exists ${something_to_use_as_keyname}
        fi
    fi 
}
## Uses local persistance
delete_all_clusters() {
    now="$1"

    numberOfClusters=get_number_of_clusters
    if [[ $numberOfClusters == 0 ]]; 
    then 
        if [[ -d ${assetsFolder}/vpc ]]; 
        then 
            ask_to_delete_vpc "No clusters exist" ${now}
        else
            echo "No clusters or vpc exist."
        fi
        rm -rf ${assetsFolder}/clusters
        exit 0; 
    else
        # if any clusters exist
        for cluster in `ls ${assetsFolder}/clusters/`; 
        do
            delete_cluster $cluster
        done
        validate "rm -rf ${assetsFolder}/clusters" "Removing clusters folder: ${assetsFolder}/clusters"

        ask_to_delete_vpc "All clusters have been deleted" ${now} 
    fi
}

ask_to_delete_vpc () {
    message="$1"
    now="$2"

    if [[ -z "${message}" ]]; 
    then 
        message="No clusters exist/left"
    fi
    leftoverClusters=$(ls ${assetsFolder}/clusters 2> /dev/null| wc -l)
    leftoverClusters=${leftoverClusters// /}
    
    if [[ ${leftoverClusters} == 0 ]]; 
    then 
        while true; 
        do
            read -p "${message}, Delete all VPCs? (Y/n): " yn
            case $yn in
                [Yy]* ) eventually_delete_all_vpcs "${now}"; break;;
                [Nn]* ) exit;break;;
                * ) echo "Please answer yes or no: ";;
            esac
        done  
    fi
}

## Uses local persistance only
error_if_cluster_doesnt_exist() {
    clusterName=$1
    
    if [[ ! -d ${assetsFolder}/clusters/${clusterName} ]]; 
    then 
        echo "\"${clusterName}\" cluster doesn't exist"; 
        exit 1; 
    fi
}

delete_cluster_aws() {
    clusterName=$1
    
    alreadyExists=`does_cluster_already_exist "${clusterName}"`
    if [[ ${alreadyExists} == "No" ]]; 
    then
        echo -e "\n\"${clusterName}\" doesn't exist.."
        return
    fi

    logfile="cluster_${clusterName}.log"

    echo -e "\n\tRemoving all instances for cluster: ${clusterName}"
       
    validate "delete_all_instances_of_role_in_cluster_aws \"client\" ${clusterName}" "Deleting client instances for ${clusterName}"
    validate "delete_all_instances_of_role_in_cluster_aws \"server\" ${clusterName}" "Deleting server instances for ${clusterName}"

    validate "rm -rf ${assetsFolder}/clusters/${clusterName}" "Removing cluster folder ${assetsFolder}/clusters/${clusterName}"

    remove_cluster_from_vpc_tag ${clusterName}  
}

## Deprecated: Uses local persistance for everything
delete_cluster() {
    clusterName=$1
    error_if_cluster_doesnt_exist ${clusterName}
    logfile="cluster_${clusterName}.log"

    echo -e "\n\tRemoving all instances for cluster: ${clusterName}"
       
    validate "delete_all_instances_of_role_in_cluster \"client\" ${clusterName}" "Deleting client instances for ${clusterName}"
    validate "delete_all_instances_of_role_in_cluster \"server\" ${clusterName}" "Deleting server instances for ${clusterName}"

    validate "rm -rf ${assetsFolder}/clusters/${clusterName}" "Removing cluster folder ${assetsFolder}/clusters/${clusterName}"

    remove_cluster_from_vpc_tag ${clusterName}

}

delete_all_instances_of_role_in_cluster_aws () {
    role="$1"
    clusterName="$2"
    
    instanceIds=`get_instances_of_role_in_cluster_aws ${role} ${clusterName} "InstanceId"`

    for instanceId in ${instanceIds//,/ }; do
        echo "Deleting instance with id: $instanceId"
        delete_instance_aws ${instanceId}
    done
}

delete_instance_aws () {
    instance_id=$1

    # Delete the instance (in its region)
    if [[ ! -z instance_id ]]; then
        status=$(aws ec2 describe-instance-status --instance-ids ${instance_id})
        status_ok=`echo $status | grep "\"Status\": \"ok"`
        status_init=`echo $status | grep "\"Status\": \"initializing"`
        if [[ -z ${status_ok} && -z ${status_init} ]]; 
        then 
            echo "It doesn't seem like instance (${instance_id}) exists" >> ${logfile} 2>&1
        else
            validate "aws ec2 terminate-instances --instance-ids ${instance_id}  >> ${logfile} 2>&1" "Removing instance ${instance_id}"
        fi
    else 
        echo "Empty instance id provided for deletion!!!"
    fi
}


## Deprecated: Uses local persistance for everything
delete_all_instances_of_role_in_cluster () {
    role="$1"
    clusterName="$2"

    clusterFolder=${assetsFolder}/clusters/${clusterName}
    roleFolder=${clusterFolder}/${role}
    if [[ ! -d ${roleFolder} ]]; then echo -e "\tNo $role instances exist for \"${clusterName}\" cluster"; return; fi

    instances_to_be_removed_from_record=""

    for line in `cat ${roleFolder}/instances`; 
    do
        instance_id=`echo $line | cut -d"," -f 1`             
        delete_instance ${instance_id} ${roleFolder}
        instances_to_be_removed_from_record="${instances_to_be_removed_from_record} ${instance_id}"
    done

    
    for instanceid in ${instances_to_be_removed_from_record};
    do 
        remove_instanceid_from_record ${instanceid} ${roleFolder}
    done

}

remove_instanceid_from_record () {
    instance_id=$1
    roleFolder=$2

    cat ${roleFolder}/instances | grep -v ${instance_id} > ${roleFolder}/tmp
    mv ${roleFolder}/tmp ${roleFolder}/instances

    leftover=$(cat ${roleFolder}/instances | wc -l)
    leftover=${leftover// /}
    if [[ ${leftover} == 0 ]]; then echo -e "\tNo more instances left, deleting ${roleFolder}"; rm -rf ${roleFolder}; fi
}


delete_instance () {
    instance_id=$1
    role_folder=$2

    original_default_region=${aws_region}
    current_region=`cat $(dirname $role_folder)/region.info 2> /dev/null | cut -d"," -f1`
    if [[ $current_region != $original_default_region && ! -z ${current_region} ]];
    then
        aws configure set default.region ${current_region}
        region_changed="true"
    fi

    # Delete the instance (in its region)
    if [[ ! -z instance_id ]]; then
        status=$(aws ec2 describe-instance-status --instance-ids ${instance_id})
        status_ok=`echo $status | grep "\"Status\": \"ok"`
        status_init=`echo $status | grep "\"Status\": \"initializing"`
        if [[ -z ${status_ok} && -z ${status_init} ]]; 
        then 
            echo "It doesn't seem like instance (${instance_id}) exists, removing it from list of instances in db" >> ${logfile} 2>&1
        else
            validate "aws ec2 terminate-instances --instance-ids ${instance_id}  >> ${logfile} 2>&1" "Removing instance ${instance_id}"
        fi
    else 
        echo "Empty instance id provided for deletion!!!"
    fi

        #revert it back
    if [[ $region_changed == "true" ]];
    then
        aws configure set default.region ${original_default_region}
        region_changed=""
    fi

}

 


create_cluster () {
    
    clusterName="$1"
    logfile="cluster_${clusterName}.log"

    if [[ ! -a $logfile ]]; then
    	touch $logfile
    fi

    alreadyExists=`does_cluster_already_exist "${clusterName}"`
    if [[ ${alreadyExists} == "Yes" ]]; 
    then
        echo -e "\n\"${clusterName}\" already exists (try a different name), quitting"
        exit 1
    fi

    numberOfServers=$2
    echo "Creating a jmeter cluster \"${clusterName}\"; with ${numberOfServers} servers and a client"
    
    if [[ -z ${reuseVpcId} ]]; then
        create_vpc
    else
        reuse_vpc ${reuseVpcId} ${reuseSubnet}
    fi
    
    # adding this cluster in the vpc's Cluster tag to keep track of all the clusters associated with this vpc   
    add_cluster_to_vpc_tag ${clusterName}
    echo -e "Creating client and server parallely in background, please allow 2-3 minutes before accessing instances\nUse --get-client|server-instances-from-cluster flags to retreive the dns names for this cluster"
    create_aws_instance client "0" &
    if [[ $numberOfServers == 0 ]]; then exit 0; fi
    for i in $(seq 1 $numberOfServers); 
    do 
        create_aws_instance server "${i}" &
        sleep 2 # adding sleep so that key pair generation sees the previous create
    done
}



POSITIONAL=()
while [[ $# > 0 ]]
do
key="$1"
POSITIONAL+=($key)
case $key in
    -vpc|--reuse-vpcid)
    reuseVpcId="$2"
    # export reuseVpcId="$2"
    if [[ -z ${reuseVpcId} ]]; then echo "Please provide the VPC Id for the vpc you'd like to reuse"; exit 1; fi    
    shift # past argument
    ;;
    -subnet|--reuse-subnet)
    reuseSubnet="$2"
    shift
    ;;
    -key|--use-pubkey)
    provided_key_file="$2"
    shift
    ;;
    -libexts|--add-jmeter-library-ext-files) #comma separated lib files to be copied to jmeter lib/ext folder
    jmeter_lib_ext_files="$2" 
    shift
    ;;
    -libextzip|--add-jmeter-library-ext-archive) #comma separated lib zip files to be extracted into jmeter lib/ext folder
    jmeter_lib_ext_archive="$2" 
    shift
    ;;
    -keystore|--keystore-location) 
    keystore_location="$2" 
    shift
    ;;
    -kpass|--keystore-password) 
    keystore_password="$2" 
    shift
    ;;
    -truststore|--truststore-location) 
    truststore_location="$2" 
    shift
    ;;
    -tpass|--truststore-password) 
    truststore_password="$2" 
    shift
    ;;
esac
shift # past argument or value
done
set -- "${POSITIONAL[@]}" # restore positional parameters




while [[ $# > 0 ]]
do
key="$1"

case $key in
    -ccc|--create-cluster-called)
    clusterName="$2"
    create="TRUE"
    if [[ -z ${clusterName} ]]; then echo "Please provide a name for the cluster or use -cdc (to create a default cluster)"; exit 1; fi    
    shift # past argument
    ;;
    -cdc|--create-default-cluster)
    clusterName="${default_cluster_name}" 
    create="TRUE"
    ;;
    -servers|--number-of-servers)
    numberOfServers="$2"
    shift
    ;;
    # -vpc|--reuse-vpcid)
    # reuseVpcId="$2"
    # export reuseVpcId="$2"
    # if [[ -z ${reuseVpcId} ]]; then echo "Please provide the VPC Id for the vpc you'd like to reuse"; exit 1; fi    
    # shift # past argument
    # ;;
    # -subnet|--reuse-subnet)
    # reuseSubnet="$2"
    # shift
    # ;;
    -s|--status)
    # echo "reuseVpcId"
    status_aws
    exit 0
    ;;
    -se|--status-easy-parse)
    status_aws "easy_parse"
    exit 0
    ;;
    -sv|--verify-status)
    status "verify"
    exit 0
    ;;
    -cvpc|--create-vpc)
    create_vpc
    exit 0
    ;;
    --delete-vpc)
    delete_vpc
    exit 0
    ;;
    -dc|--delete-cluster)
    clusterName="$2"
    if [[ -z ${clusterName} ]]; then echo "Please provide a name of the cluster to delete"; exit 1; fi
    delete_cluster_aws ${clusterName}
    exit 0
    ;;
    -ddc|--delete-default-cluster)
    clusterName="${default_cluster_name}"
    delete_cluster_aws ${clusterName}
    exit 0
    ;;
    -dac|--delete-all-clusters)
    delete_all_cluster_aws
    exit 0
    ;;
    -delete|--delete-everything)
    delete_all_cluster_aws "delayed" "Delete_VPC_Too"
    exit 0
    ;;
    -dacn|--delete-all-clusters-now)
    delete_all_cluster_aws "now"
    exit 0
    ;;
    -sid|--get-server-instances-from-default)
    clusterName="${default_cluster_name}"
    get_instances_of_role_in_cluster_aws "server" ${clusterName}
    exit 0
    ;;
    -si|--get-server-instances-from-cluster)
    clusterName="$2"
    if [[ -z ${clusterName} ]]; then echo "Please provide a name of the cluster"; exit 1; fi    
    get_instances_of_role_in_cluster_aws "server" ${clusterName}
    exit 0
    ;;
    -cid|--get-client-instances-from-default)
    clusterName="${default_cluster_name}"
    get_instances_of_role_in_cluster_aws "client" ${clusterName}
    exit 0
    ;;
    -ci|--get-client-instances-from-cluster)
    clusterName="$2"
    if [[ -z ${clusterName} ]]; then echo "Please provide a name of the cluster"; exit 1; fi    
    get_instances_of_role_in_cluster_aws "client" ${clusterName}
    exit 0
    ;;
    -region|--set-aws-region)
    region="$2"  
    set_aws_region ${region}
    exit 0
    ;;
    -default-region|--get-default-aws-region) 
    get_default_aws_region
    exit 0
    ;;
    -ignorerunning) 
    IGNORE_RUNNING="$2"
    IGNORE_RUNNING=$(echo $IGNORE_RUNNING| awk '{print tolower($0)}')
    shift 
    ;;                  
    --default)
    create="FALSE"
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done
usage="./jmeter-aws <options>\nOptions include:\n\t--status|-s\n\t--verify-status|-sv\n\t--create-cluster-called <name>|-ccc <clusterName>\n\t--create-default-cluster|-cdc\n\t--number-of-servers <number>|-servers <number> \
    \n\t--delete-cluster <clusterName>|-dc <clusterName>\n\t--delete-all-clusters|-dac\n\t--get-server-instances-from-default|-sid\n\t--get-server-instances-from-cluster|-sid <clusterName> \
    \n\t--get-client-instances-from-default|-cid\n\t--get-client-instances-from-cluster|-cid <clusterName>\n\t--set-aws-region <aws-region>|-region <aws-region>\n\t--get-default-aws-region|-default-region"

if [[ $create != "TRUE" ]]; then     
    echo -e "Please provide an option e.g. \n\t$usage"
    exit 0
fi

if [[ -z ${numberOfServers} ]]; then 
    echo -e "Using 1 jmeter server (default) \n\tUse -servers <number> or --number-of-servers <number> to specify number of jmeter servers in the cluster"
    numberOfServers=1
fi

if [[ ! -z ${reuseVpcId} ]]; then
    if [[ -z ${reuseSubnet} ]]; then 
        echo -e "Subnet id is required when reusing an existing VPC, quitting.."
        exit 1
    fi
    vpccount=`aws ec2 describe-vpcs --vpc-ids ${reuseVpcId} | grep ${reuseVpcId} | wc -l`
    subnetcount=`aws ec2 describe-subnets --subnet-ids ${reuseSubnet} | grep ${reuseSubnet} | wc -l`
    vpccount=${vpccount// /}
    subnetcount=${subnetcount// /}
    if [[ ${vpccount} != 1 ]]; then echo -e "The vpc provided for re-use (${reuseVpcId}) doesn't exist"; exit 1; fi
    if [[ ${subnetcount} != 1 ]]; then echo -e "The subnet provided for re-use (${reuseSubnet}) doesn't exist"; exit 1; fi

fi

# keystore and truststore password validation
if [[ ! -z ${keystore_location} && -z ${keystore_password} ]]; then
    echo -e "Keystore location provided without a keystore password, quitting"
    exit 1
fi
if [[ ! -z ${truststore_location} && -z ${truststore_password} ]]; then
    echo -e "truststore location provided without a truststore password, quitting"
    exit 1
fi


echo "Starting cluster creation in ${aws_region} at: `date`" 2>&1 | tee $logfile
create_cluster "${clusterName}" "${numberOfServers}"
