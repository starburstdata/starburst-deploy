# Deploying a GKE cluster
Command line instructions to deploy a Google Kubernetes Engine cluster. These have been designed to run on Linux/Unix, Mac or in a Cloud Shell. There are no additional files required to support these instructions.

## Setting things up

1. Ensure that you have installed these components:
    - [gcloud cli](https://cloud.google.com/sdk/docs/install)
    - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)

2. Ensure that you are running these in the `bash` shell

>NOTE!
This is pretty important if you are running these commands on a Mac, which defaults to the zsh. You will need to switch to the bash terminal since it can handle multi-line strings referenced later in some of the helm commands

```shell
bash
```

3. Edit and set the following shell variables:
```shell
## Deploy Starburst ##
export registry_usr=?
export registry_pwd=?
export admin_usr=?
export admin_pwd=?

# Shouldn't need to change this link, unless we move the repo
export github_link="https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/helm/"

# These URLS are used if deploying nginx and dns.
export starburst_url=?
export ranger_url=?

# Google Cloud DNS
export google_cloud_project_dns=?
export google_cloud_dns_zone=?

# Cluster specifics
export starburst_license=starburstdata.license
export zone=?
export google_cloud_project=?
export iam_account=<sa-name@project-id.iam.gserviceaccount.com>
export cluster_name=?

export xtra_args_hive="--set objectStorage.gs.cloudKeyFileSecret=service-account-key"
export xtra_args_starburst="--values starburst.bigQuery.yaml"
export xtra_args_ranger=""
```

4. Generate the Azure-specific Starburst catalog yaml

>NOTE!
This command generates a static yaml file that will be deployed later with your Starburst application

```shell
cat <<EOF > starburst.bigQuery.yaml
catalogs:
    bigquery: |
        connector.name=bigquery
        bigquery.project-id=${google_cloud_project}
EOF
```

---

## Installation

5. Create the GKE cluster
```shell
gcloud container clusters create "${cluster_name:?Cluster name not set}" \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone:?Zone not set}" \
    --no-enable-basic-auth \
    --metadata disable-legacy-endpoints=true \
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
    --machine-type "e2-standard-8" \
    --num-nodes "1" \
    --node-labels starburstpool=base \
    --node-locations "${zone:?Zone not set}" && \
gcloud container node-pools create "worker" \
    --cluster "${cluster_name:?Cluster name not set}" \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone:?Zone not set}" \
    --machine-type "e2-standard-8" \
    --preemptible \
    --num-nodes "1" \
    --enable-autoscaling \
    --min-nodes "1" \
    --max-nodes "4" \
    --node-labels starburstpool=worker \
    --node-locations "${zone:?Zone not set}"
```

6. Upload your Starburst license file as a secret to your GKE cluster
```shell
kubectl create secret generic starburst --from-file ${starburst_license}
```
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