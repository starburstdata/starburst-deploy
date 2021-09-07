# Deploying a GKE cluster
Command line instructions to deploy a Google Kubernetes Engine cluster. These have been designed to run on Linux/Unix, Mac or in a Cloud Shell. There are no additional files required to support these instructions.

## Setup instructions
1. Edit and set the following shell variables:
```
# Google Cloud DNS
export google_cloud_project_dns=?
export google_cloud_dns_zone=?

# Cluster specifics
export starburst_license=starburstdata.license
export zone=?
export google_cloud_project=?
export iam_account=<sa-name@project-id.iam.gserviceaccount.com>
export cluster_name=?
```

2. Create the GKE cluster
```
gcloud container --project "${google_cloud_project:?Project name not set}" clusters create "${cluster_name:?Cluster name not set}" \
    --zone "${zone:?Zone not set}" \
    --no-enable-basic-auth \
    --metadata disable-legacy-endpoints=true \
    --num-nodes "1" \
    --enable-ip-alias \
    --node-locations "${zone:?Zone not set}" && \
gcloud container --quiet node-pools delete default-pool \
    --cluster="${cluster_name:?Cluster name not set}" && \
gcloud container --project "${google_cloud_project:?Project name not set}" node-pools create "base" \
    --cluster "${cluster_name:?Cluster name not set}" \
    --zone "${zone:?Zone not set}" \
    --machine-type "e2-standard-8" \
    --num-nodes "1" \
    --node-labels starburstpool=base \
    --node-locations "${zone:?Zone not set}" && \
gcloud container --project "${google_cloud_project:?Project name not set}" node-pools create "worker" \
    --cluster "${cluster_name:?Cluster name not set}" \
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

3. Upload your Starburst license file as a secret to your GKE cluster
```
kubectl create secret generic starburst --from-file ${starburst_license}
```
4. Get your service account credentials from Google
```
gcloud iam service-accounts keys create key-file \
    --iam-account=${iam_account:?Service Account not set}
```

5. Upload your service account key.json to the GKE cluster
```
kubectl create secret generic service-account-key --from-file key.json
```
---
## Post-installation

6. Retrieving the kubectl config file.
If you are deploying to a cloud shell or to a remote system and you are using Lens locally to monitor the deployments, then run this command on your local machine to retrieve the kubernetes configuration:
```
gcloud container clusters get-credentials ${cluster_name:?Cluster name not set} --zone ${zone:?Zone not set} --project ${google_cloud_project:?Project not set}
```
---