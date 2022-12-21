# Deploying an EKS cluster
Command line instructions to deploy an Amazon EKS cluster. These have been designed to run on Linux/Unix, Mac or in a Cloud Shell. There are no additional files required to support these instructions.

## Setup instructions

1. Ensure that you have installed these components:
    - [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
    - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
    - [helm](https://helm.sh/docs/intro/install/)
    - [eksctl](https://eksctl.io/introduction/#installation)

2. Ensure that you are running these in the `bash` shell

>NOTE!
This is pretty important if you are running these commands on a Mac, which defaults to the zsh. You will need to switch to the bash terminal since it can handle multi-line strings referenced later in some of the helm commands

```shell
bash
```

3. Edit and set the following shell variables:

>TIP: Copy and paste this section into a shell script and edit the values from there.

```shell
## Deploy Starburst ##
export registry_usr=           # Harbor Repository username provided to you by Starburst
export registry_pwd=           # Harbor Repository password provided to you by Starburst
export admin_usr=              # Choose an admin user name you will use to login to Starburst & Ranger. Do NOT use 'admin'
export admin_pwd=              # Choose an admin password you will use to login to Starburst & Ranger. MUST be a minimum of 8 characters and contain at least one uppercase, lowercase and numeric value.

# Shouldn't need to change this link, unless we move the repo
export github_link="https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/helm/"

# AWS DNS
export hosted_zone_id=

# These URLS are used if deploying nginx and dns.
export starburst_url=                          # Don't include the http:// prefix
export ranger_url=                             # Don't include the http:// prefix

# Cluster specifics
export starburst_license=starburstdata.license  # # License file provided by Starburst
export region=                                 # AWS Region to deploy your cluster to
export cluster_name=                           # Give your cluster a name

# Insights DB details
# These are the defaults if you choose to deploy your postgresDB to the K8s cluster
# You can adjust these to connect to an external DB, but be advised that the nodes in the K8s cluster must have access to the URL
export database_connection_url=jdbc:postgresql://postgresql:5432/insights
export database_username=postgres
export database_password=password123

# Data Products. Leave the password unset as below, if you are connecting directly to the coordinator on port 8080
export data_products_enabled=true
export data_products_jdbc_url=jdbc:trino://coordinator:8080
export data_products_username=${admin_usr}
export data_products_password=

# Starburst Access Control
export starburst_access_control_enabled=true
export starburst_access_control_authorized_users=${admin_usr}

# These last remaining values are static
export xtra_args_hive=""
export xtra_args_starburst=""
export xtra_args_ranger=""
```

4. Download the `eksctl` yaml [file](https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/aws/eksctl.yaml)

5. Edit the `eksctl` yaml file and set the following placeholder's to the correct values for your environment
    - CLUSTER_NAME
    - CLUSTER_REGION
    - CLUSTER_VPC
    - CLUSTER_SUBNET_1
    - CLUSTER_SUBNET_2

>**NOTE!**
Apart from the `starburstpool` labels on the managed nodes, you are not restricted to using the default values set in this file. You are free to modify any of the other default values in this file. However, it is recommended that the minimum EC2 machine size for either the `base` or `worker` pool should have at least 8 CPU cores and 32GB of MEM.

6. Create the EKS cluster
```shell
eksctl create cluster -f eksctl.yaml
```

>**NOTE!**
How you authenticate to your AWS environment will depend on your particular security setup. If using IAM Keys, you will need to run `aws configure` and set your keys accordingly. If you are using Okta, you may want to use [gimme-aws-creds](https://github.com/Nike-Inc/gimme-aws-creds).

7. Upload your Starburst license file as a secret to your GKE cluster
```shell
kubectl create secret generic starburst --from-file ${starburst_license}
```

8. Install the cluster autoscaler
```shell
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm repo add bitnami https://charts.bitnami.com/bitnami
```

```shell
helm upgrade metricsserver bitnami/metrics-server --install \
    --set apiService.create=true \
    --namespace kube-system \
    --set nodeSelector.starburstpool=base
```

```shell
helm upgrade autoscaler autoscaler/cluster-autoscaler --install \
    --version 9.3.0 \
    --set cloudProvider=aws \
    --set awsRegion=${region:?Value not set} \
    --set autoDiscovery.clusterName=${cluster_name:?Value not set} \
    --set extraArgs.skip-nodes-with-local-storage=false \
    --set extraArgs.skip-nodes-with-system-pods=false \
    --set extraArgs.balance-similar-node-groups=true \
    --set extraArgs.expander=least-waste \
    --set service.labels.app=node-autoscaler \
    --namespace kube-system \
    --set nodeSelector.starburstpool=base
```

---
## Post-installation

9. Retrieving the kubectl config file.
If you are deploying to a cloud shell or to a remote system and you are using Lens locally to monitor the deployments, then run this command on your remote system to retrieve the kubernetes configuration:
```shell
echo aws eks update-kubeconfig --name ${cluster_name} --region ${region}
```
Then run the output from the echo command on your local machine to update your local kubectl.config with your new cluster's details.

---

## Cleaning up

10. Deleting your cluster.
```shell
eksctl delete cluster -f eksctl.yaml 
```

11. Remove DNS entries.

```shell
aws route53 change-resource-record-sets --hosted-zone-id ${hosted_zone_id:?Value not set}  --change-batch '{ "Comment": "generated by starburst-deploy", "Changes": [ { "Action": "DELETE", "ResourceRecordSet": { "Name": "'"${starburst_url:?You need to specify a url}"'", "Type": "CNAME", "TTL": 3600, "ResourceRecords": [ { "Value": "'"${nginx_loadbalancer_ip:?Need to specify an IP or Hostname}"'" } ] } } ] }'
```

```shell
aws route53 change-resource-record-sets --hosted-zone-id ${hosted_zone_id:?Value not set}  --change-batch '{ "Comment": "generated by starburst-deploy", "Changes": [ { "Action": "DELETE", "ResourceRecordSet": { "Name": "'"${ranger_url:?You need to specify a url}"'", "Type": "CNAME", "TTL": 3600, "ResourceRecords": [ { "Value": "'"${nginx_loadbalancer_ip:?Need to specify an IP or Hostname}"'" } ] } } ] }'
```