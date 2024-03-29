# Deploying an AKS cluster
Command line instructions to deploy an Azure Kubernetes Service cluster. These have been designed to run on Linux/Unix, Mac or in a Cloud Shell. There are no additional files required to support these instructions.

## Setting things up

1. Ensure that you have installed these components:
    - [azure cli](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
    - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

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
export registry_usr=
export registry_pwd=
export admin_usr=              # Choose an admin user name you will use to login to Starburst & Ranger. Do NOT use 'admin'
export admin_pwd=              # Choose an admin password you will use to login to Starburst & Ranger. MUST be a minimum of 8 characters and contain at least one uppercase, lowercase and numeric value.

# Azure DNS
export dns_subscription=       # Azure subscription ID containing your DNS zone
export dns_resource_group=     # Resource Group containing your DNS zone
export zone_name=              # DNS Zone name (e.g. some.domain.net)
export starburst_rs_name=      # Record Set DNS entry for Starburst application (e.g. sb-test-aks-starburst)
export ranger_rs_name=         # Record Set DNS entry for Ranger application (e.g sb-test-aks-ranger)

# Azure SP has to be explicitly defined. Managed Identities not currently supported
export abfs_auth_type=oauth     # Default to `oauth` unless you have a good reason to use `accessKey`
export abfs_client_id=         # Service Principal Client ID (From Azure AD)
export abfs_secret=            # Service Principal Secret (From Azure AD)
export tenant_id=              # Your Azure domain (a.k.a tenant ID)
export abfs_endpoint="https://login.microsoftonline.com/${tenant_id:?Value not set}/oauth2/token" # This value is dynalically set based on your tenant

# These URLS are used if deploying nginx and dns.
export starburst_url=${starburst_rs_name}.${zone_name} # This value is dynamically set
export ranger_url=${ranger_rs_name}.${zone_name} # This value is dynamically set

# Azure Environment
export subscription=       # Subscription ID where Starburst will be deployed
export region=             # Azure Region where the cluster will be deployed
export resource_group=     # Resource Group that will be created for the deployment
export cluster_name=       # Give your cluster a name
export storage_account=    # Storage Account that will be created for Hive

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
export starburst_license="starburstdata.license"
export xtra_args_hive="--set commonLabels.aadpodidbinding=starburst \
        --set objectStorage.azure.abfs.authType=oauth \
        --set objectStorage.azure.abfs.oauth.clientId=${abfs_client_id} \
        --set objectStorage.azure.abfs.oauth.endpoint=${abfs_endpoint} \
        --set objectStorage.azure.abfs.oauth.secret=${abfs_secret}"
export xtra_args_starburst="--set worker.tolerations[0].key=kubernetes.azure.com/scalesetpriority \
        --set controller.service.annotations.\"service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path\"=/healthz \
        --set worker.tolerations[0].operator=Exists \
        --set worker.tolerations[0].effect=NoSchedule \
        --values starburst.adls.yaml"
export xtra_args_ranger=""
```

4. Generate the Azure-specific Starburst catalog yaml

>NOTE!
This command generates a static yaml file that will be deployed later with your Starburst application

```shell
cat <<EOF > starburst.adls.yaml
catalogs:
    hive: |
        connector.name=hive
        hive.security=starburst
        hive.metastore.uri=thrift://hive:9083
        hive.azure.abfs.oauth.client-id=${abfs_client_id}
        hive.azure.abfs.oauth.secret=${abfs_secret}
        hive.azure.abfs.oauth.endpoint=${abfs_endpoint}
        cache-service.uri=http://coordinator:8180
        materialized-views.enabled=true
        materialized-views.namespace=mv_namespace
        materialized-views.storage-schema=cache
EOF
```

One these initial steps have been completed, you will use the `az-cli` to deploy the Azure infrastructure required to support the Starburst application.

---

## Installation

5. Login to the Azure CLI
```shell
az login
```

6. Create the Resource Group
```shell
az group create --resource-group ${resource_group:?Value not set} \
    --location "${region:?Value not set}" \
    --subscription "${subscription:?Value not set}"
```

7. Create the AKS cluster
```shell
az aks create --name ${cluster_name:?Value not set} \
    --subscription ${subscription:?Value not set} \
    --resource-group ${resource_group:?Value not set} \
    --enable-managed-identity \
    --enable-cluster-autoscaler \
    --min-count 1 \
    --max-count 1 \
    --node-count 1 \
    --node-vm-size Standard_D8s_v3 \
    --generate-ssh-keys \
    --network-plugin azure \
    --nodepool-name base \
    --nodepool-labels "starburstpool=base" && \
az aks nodepool add \
    --subscription ${subscription:?Value not set} \
    --resource-group ${resource_group:?Value not set} \
    --cluster-name ${cluster_name:?Value not set} \
    --name worker \
    --enable-cluster-autoscaler \
    --node-count 1 \
    --min-count 1 \
    --max-count 10 \
    --node-vm-size Standard_D8s_v3 \
    --priority Spot \
    --labels "starburstpool=worker"
```

8. Retrieving the kubectl config file.

```shell
az aks get-credentials \
    --subscription ${subscription:?Value not set} \
    --resource-group ${resource_group:?Value not set} \
    --name ${cluster_name:?Value not set}
```

9. Upload your Starburst license file as a secret to your AKS cluster

```shell
kubectl create secret generic starburst --from-file ${starburst_license}
```

10. Create a Storage Account for Hive

```shell
az storage account create --name ${storage_account:?Value not set} \
    --resource-group ${resource_group:?Value not set} \
    --subscription "${subscription:?Value not set}" \
    --kind StorageV2 \
    --sku Standard_LRS \
    --https-only false \
    --enable-hierarchical-namespace false
```

---

## Cleaning up
>NOTE!
The following steps will destroy all the infrastructure created in the previous steps. Use these commands to clean up your environment once you are done with it.

11. Delete your cluster.
```shell
az aks delete \
    --name ${cluster_name:?Value not set} \
    --subscription ${subscription:?Value not set} \
    --resource-group ${resource_group}
```

12. Remove DNS entries.

```shell
az network dns record-set a delete \
    --name ${ranger_rs_name} \
    --subscription ${dns_subscription:?Value not set} \
    --resource-group ${dns_resource_group} \
    --zone-name ${zone_name:?Value not set}
```

```shell
az network dns record-set a delete \
    --name ${starburst_rs_name} \
    --subscription ${dns_subscription:?Value not set} \
    --resource-group ${dns_resource_group} \
    --zone-name ${zone_name:?Value not set}
```

13. Delete Resource Group.

```shell
az group delete --resource-group ${resource_group:?Value not set} \
    --subscription "${subscription:?Value not set}"
```