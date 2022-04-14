# Deploying a GKE cluster
Command line instructions to deploy a Google Kubernetes Engine cluster. These have been designed to run on Linux/Unix, Mac or in a Cloud Shell. There are no additional files required to support these instructions.

## Setting things up

1. Ensure that you have installed these components:
    - [gcloud cli](https://cloud.google.com/sdk/docs/install)
    - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

>NOTE!
Don't forget to authenticate your gcloud client by running `gcloud login` before continuing on to the next step.

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
export registry_usr=""           # Harbor Repository username provided to you by Starburst
export registry_pwd=""           # Harbor Repository passowrd provided to you by Starburst
export admin_usr=              # Choose an admin user name you will use to login to Starburst & Ranger. Do NOT use 'admin'
export admin_pwd=              # Choose an admin password you will use to login to Starburst & Ranger. MUST be a minimum of 8 characters and contain at least one uppercase, lowercase and numeric value.

# Shouldn't need to change this link, unless we move the repo
export github_link="https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/helm/"

# Google Cloud DNS
# The Google Cloud Project ID where your DNS Zone is defined. This may be different to the project that you are deployiong the cluster to. Either way, this value will need to be set.
export google_cloud_project_dns=""
# The DNS Zone name (NOT the DNS Name). You can find this value in https://console.cloud.google.com/net-services/dns/zones
export google_cloud_dns_zone=""

# Cluster specifics
# License file provided by Starburst. Not required if you are deploying via the Google Cloud Marketplace
export starburst_license=starburstdata.license
# Zone where the cluster will be deployed. e.g. us-east4-b
export zone=""
# Google Cloud Project ID where the cluster is being deployed
export google_cloud_project=""
# Google Service account name. The service account is used to access services like GCS and BigQuery, so you should ensure that it has the relevant permissions for these
export iam_account=<sa-name@project-id.iam.gserviceaccount.com>
# Give your cluster a name
export cluster_name=""

# Set the machine type here. Feel free to change these values to suit your needs.
export base_node_type="e2-standard-8"
export worker_node_type="e2-standard-8"

# These next values are automatically set based on your input values
# We'll automatically get the domain for the zone you are selecting. Comment this out if you don't need DNS
export google_cloud_dns_zone_name=$(gcloud dns managed-zones describe ${google_cloud_dns_zone:?Zone not set} --project ${google_cloud_project_dns:?Project ID not set} | grep dnsName | awk '{ print $2 }' | sed 's/.$//g')

# This is the public URL to access Starburst
export starburst_url=${cluster_name:?Cluster Name not set}-starburst.${google_cloud_dns_zone_name}
# This is the public URL to access Ranger
export ranger_url=${cluster_name:?Cluster Name not set}-ranger.${google_cloud_dns_zone_name}

# These last remaining values are static
export xtra_args_hive="--set objectStorage.gs.cloudKeyFileSecret=service-account-key"
export xtra_args_starburst="--values starburst.catalog.yaml"
export xtra_args_ranger=""
```

4. Generate the Google Cloud-specific Starburst catalog yaml

>NOTE!
This command generates a yaml file that will be deployed later with your Starburst application. Edit this file to add any additional catalogs you need Starburst to connect to. If you are deploying via the Google Cloud Marketplace, then you can skip this step since Marketplace uses a different yaml file.

```shell
cat <<EOF > starburst.catalog.yaml
catalogs:
    bigquery: |
        connector.name=bigquery
        bigquery.project-id=${google_cloud_project}
EOF
```

---

## Installation

**NOTE!**
>The initial cluster create command in Google includes a default node pool which is deleted by the script and replaced with two separate node pools: `base` and `worker`. The worker pool uses preemptible nodes by default. You should remove this line if you require on-demand nodes instead.

5. Create the GKE cluster
```shell
gcloud container clusters create "${cluster_name:?Cluster name not set}" \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone:?Zone not set}" \
    --no-enable-basic-auth \
    --metadata disable-legacy-endpoints=true \
    --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --num-nodes "1" \
    --enable-ip-alias \
    --node-locations "${zone:?Zone not set}" && \
gcloud container --quiet node-pools delete default-pool \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone:?Zone not set}" \
    --cluster="${cluster_name:?Cluster name not set}" && \
gcloud container node-pools create "base" \
    --cluster "${cluster_name:?Cluster name not set}" \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone:?Zone not set}" \
    --machine-type "${base_node_type}" \
    --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --num-nodes "1" \
    --node-labels starburstpool=base \
    --node-locations "${zone:?Zone not set}" && \
gcloud container node-pools create "worker" \
    --cluster "${cluster_name:?Cluster name not set}" \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone:?Zone not set}" \
    --machine-type "${worker_node_type}" \
    --scopes "https://www.googleapis.com/auth/cloud-platform" \
    --preemptible \
    --num-nodes "1" \
    --enable-autoscaling \
    --min-nodes "1" \
    --max-nodes "4" \
    --node-labels starburstpool=worker \
    --node-locations "${zone:?Zone not set}"
```

6. Upload your Starburst license file as a secret to your GKE cluster

>NOTE: Skip this step if you are deploying through the Google Marketplace

```shell
kubectl create secret generic starburst --from-file ${starburst_license}
```

## The Google Service Account
The Hive Mestastore Service (HMS) requires a Service Account in order to access Google Cloud Storage (GCS). Ensure that you have an existing one set up, or create a new one with the relevant GCS bucket permissions before proceeding with the next two steps. The Starburst application will use the permission scope set at the creation of the GKE cluster.

7. Get your service account credentials from Google
```shell
gcloud iam service-accounts keys create key.json \
    --iam-account=${iam_account:?Service Account not set}
```

8. Upload your service account key.json to the GKE cluster
```shell
kubectl create secret generic service-account-key --from-file key.json
```

---
## Post-installation

9. Retrieving the kubectl config file.
If you are deploying to a cloud shell or to a remote system and you are using Lens locally to monitor the deployments, then run this command on your remote system to retrieve the kubernetes configuration:

```shell
echo gcloud container clusters get-credentials ${cluster_name:?Cluster name not set} --zone ${zone:?Zone not set} --project ${google_cloud_project:?Project not set}
```

Then run the output from the echo command on your local machine to update your local kubectl.config with your new cluster's details.

---

## Cleaning up

10. Delete your cluster.
```shell
gcloud container clusters delete ${cluster_name} \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone}"
```

11. Remove DNS entries.
```shell
gcloud dns record-sets delete "${starburst_url}." \
    --project "${google_cloud_project}" \
    --zone="${google_cloud_dns_zone}" \
    --type="A"
```
```shell
gcloud dns record-sets delete "${ranger_url}." \
    --project "${google_cloud_project}" \
    --zone="${google_cloud_dns_zone}" \
    --type="A"
```