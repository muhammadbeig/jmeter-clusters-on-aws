# jmeteraws; Provisioning apache jmeter cluster (of specified size) on amazon cloud

## Requirements
AWS CLI installed and configured.

## Usage
				./jmeter-aws <options>
					
			Options:
				--status|-s
				--create-cluster-called <name>|-ccc <clusterName>
				--create-default-cluster|-cdc
				--number-of-servers <number>|-servers <number>
				--delete-cluster <clusterName>|-dc <clusterName>
				--delete-default-cluster|-ddc
				--delete-all-clusters|-dac
				--get-server-instances-from-default|-sid
				--get-server-instances-from-cluster|-sic <clusterName>
				--get-client-instances-from-default|-cid
				--get-client-instances-from-cluster|-cic <clusterName>
				-region <aws-region>|--set-aws-region <aws-region>

## AWS Region options
###Setting AWS region:
				./jmeter-aws.sh --set-aws-region <region>  (currently only us-west and us-east regions are supported)
			Example:
				./jmeter-aws.sh --set-aws-region us-west-1
				us-west-1
			
			Default region: us-east-1

###Getting default region:
				./jmeter-aws.sh --get-default-aws-region
				Example:
				./jmeter-aws.sh --get-default-aws-region
				us-west-1

## Cluster Creation
###Creating a default cluster:
There is one default cluster per aws availability zone (AZ). The default cluster is named "default_useast1a" for us-east-1a AZ and "default_uswest1a" for us-west-1a AZ.

				./jmeter-aws.sh --create-default-cluster --number-of-servers <number>
				Example:
				./jmeter-aws.sh --create-default-cluster --number-of-servers 2
				or
				./jmeter-aws.sh -cdc -servers 2

Each cluster is created with 1 jmeter client and the number of jmeter servers specified (default # of jmeter servers = 1). The expectation is that jmeter test will then be executed using the jmeter client using the distributed mode (-R option) and using the jmeter servers from the same cluster as shown below:

				Example (run on jmeter client instance):
				bash /usr/local/apache-jmeter-2.13/bin/jmeter -n -t test/script.jmx -Jclient.rmi.localport=4001 -R <jmeter-server-1-dns>,<jmeter-server-2-dns>..

###Creating a custom cluster:
The only thing custom about a "custom cluster" is that its name is chosen by the you (user). Other than that it is the same as a default cluster.

				./jmeter-aws.sh --create-cluster-called "<alphanumeric-cluster-name>" --number-of-servers <number>
				e.g.
				./jmeter-aws.sh --create-cluster-called "mytestcluster-uswest" --number-of-servers 1
				or
				./jmeter-aws.sh -ccc "mytestcluster-uswest" -servers 1

## Cluster Status
###Display existing clusters:
				./jmeter-aws.sh --status
				or 
				./jmeter-aws.sh -s

				Example:
				./jmeter-aws.sh -s
					Default AWS Region: us-east-1

						1 cluster(s) exist

						**** Name: myclusterinuseast	Region: us-east-1 ****
						1 Client:
							ec2-52-203-120-187.compute-1.amazonaws.com
						2 Server(s):
							ec2-54-85-216-118.compute-1.amazonaws.com
							ec2-52-90-63-106.compute-1.amazonaws.com


## Getting ec2-names of instances in a custom cluster:
If you know about jmeter naming for its nodes when used in distributed mode; there are two modes of a jmeter machine: client and server. A jmeter client serves as a "controller" that is used to issue commands to execute tests. The client uses "jmeter servers" as nodes each of which run the threads of a performance test. For more information about jmeter distributed/remote testing, see http://jmeter.apache.org/usermanual/remote-test.html.

###Get list of servers in a cluster:
				./jmeter-aws.sh --get-server-instances-from-cluster <cluster-name>
				or 
				./jmeter-aws.sh -sic <cluster-name>

				Example:
				./jmeter-aws.sh --get-server-instances-from-cluster "myclusterinuseast"
				ec2-54-85-216-118.compute-1.amazonaws.com,ec2-52-90-63-106.compute-1.amazonaws.com

###Get client in a cluster:
				./jmeter-aws.sh --get-client-instances-from-cluster <cluster-name>
				or 
				./jmeter-aws.sh -cic <cluster-name>

				Example:
				./jmeter-aws.sh --get-client-instances-from-cluster "myclusterinuseast"
				ec2-52-203-120-187.compute-1.amazonaws.com			


## Getting ec2-names of instances in default clusters:
###Get list of servers in default cluster:
				./jmeter-aws.sh --get-server-instances-from-default  
				or 
				./jmeter-aws.sh -sid			

*Note: There is one default cluster per aws availability zone. Set the AWS region before running these commands to specify the region for the default cluster.*


###Get client in default cluster:
				./jmeter-aws.sh --get-client-instances-from-default
				or 
				./jmeter-aws.sh -cid

*Note: There is one default cluster per aws availability zone. Set the AWS region before running these commands to specify the region for the default cluster.*

## Deletion
### Deleting a cluster
				./jmeter-aws.sh --delete-cluster <clusterName>
							or
				./jmeter-aws.sh -dc <clusterName>
				
### Deleting the default cluster (in the selected region)
				./jmeter-aws.sh --delete-default-cluster
							or
				./jmeter-aws.sh -ddc

### Deleting all clusters
				./jmeter-aws.sh --delete-all-clusters
							or
				./jmeter-aws.sh -dac
