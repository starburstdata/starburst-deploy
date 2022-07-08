# Deploying Starburst on GKE from the Google Cloud Marketplace
Some simple scripts and yamls to deploy Starburst via the Google Cloud Marketplace using the command line. Please note, that the current GUI-based installation does not allow you to modify the configuration after Starburst has been deployed. This command line approach allows you to customize your deployment and apply updates as required.

The following components will be installed and deployed:
   - A GKE cluster
   - Postgres Database on Kubernetes
   - Hive Metastore Service
   - Starburst Enterprise
   - Nginx LoadBalancer
   - Certificate Manager
   - Certificate Issuer

>**NOTE!**
*These scripts only work with the Linux/Unix bash shell. Run this on a Mac, Linux or Unix machine if possible OR use a cloud shell from your browser. Google offers this utility directly from their UI Console.*

## Setting things up...

1. Ensure that you are running these in the `bash` shell

>NOTE!
This is pretty important if you are running these commands on a Mac, which defaults to the zsh. You will need to switch to the bash terminal since it can handle multi-line strings referenced later in some of the helm commands

```shell
bash
```

2. Ensure that you have installed these components:
    - [gcloud cli](https://cloud.google.com/sdk/docs/install)
    - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
    - [helm](https://helm.sh/docs/intro/install/)
    - [lens](https://k8slens.dev/) OR [k9s](https://k9scli.io/)

>**NOTE!**
*You are not required to run Lens or k9s, however, it will make it a lot easier to monitor your deployments as you are running through this. You will want to verify that each pod has been deployed successfully before continuing to the next step in the process*

3. Add the required Helm repositories:
```shell
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add bitnami https://charts.bitnami.com/bitnami
```

---
# Deploy a GKE cluster

4. Edit and set the following shell variables:

>TIP: Copy and paste this section into a shell script and edit the values from there.

```shell
# Shouldn't need to change this link, unless we move the repo
export github_link="https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/marketplace/googlecloud/"

# Google Cloud DNS
# The Google Cloud Project ID where your DNS Zone is defined. This may be different to the project that you are deployiong the cluster to. Either way, this value will need to be set.
export google_cloud_project_dns=""
# The DNS Zone name (NOT the DNS Name). You can find this value in https://console.cloud.google.com/net-services/dns/zones
export google_cloud_dns_zone=""

# Cluster specifics
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
# We'll automatically get the domain for the zone you are selecting.
# Setting up DNS requires a cloud domain. Google provides the facility to purchase a domain and set up a DNS zone if you do not have one. You can also use an existing domain and DNS zone that you already own inside your Google Cloud environment.
# The instructions below assume that you have an existing domain and DNS zone, but if you do not, you can purchase one through any of the Cloud providers for a small fee, (see [Google](https://cloud.google.com/domains/docs/register-domain) for more details).
# If you are using an existing Domain and DNS Zone outside the cloud environment, you just need a hostname or IP address created by the cloud provider Network Load Balancer (NLB) when you deploy nginx, to create the 'A' record to your existing DNS zone.
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

5. Generate the Google Cloud-specific Starburst catalog yaml

>NOTE!
This command generates a yaml file that will be deployed later with your Starburst application. Edit this file to add any additional catalogs you need Starburst to connect to. The default values file on GitHub already contains entries for Hive and Postgres.

```shell
cat <<EOF > starburst.catalog.yaml
starburst-enterprise:
    catalogs:
        bigquery: |
            connector.name=bigquery
            bigquery.project-id=${google_cloud_project}
EOF
```

6. Create the GKE cluster

>**NOTE!**
The initial cluster create command in Google includes a default node pool which is deleted by the script and replaced with two separate node pools: `base` and `worker`. The worker pool uses preemptible nodes by default. You should remove this line if you require on-demand nodes instead.


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

## Get the license.yaml file from the Google Marketplace

9. Navigate to the [Google Cloud Marketplace SEP](https://console.cloud.google.com/marketplace/product/starburst-public/starburst-enterprise) offering and select *Configure*

10. Switch to *Deploy via command line* tab

11. If you have the *Billing Account Admininstrator* role, then leave the **Reporting service account** dropdown set to *Create new service acount*. If not, you will need to use an existing **Reporting service account** from the dropdown.

>**WARNING!**
If you do not have the *Billing Account Admininstrator* role and there are no **Reporting service accounts** available, you will not be able to proceed with the Marketplace deployment! Please see your Google Account Administrator to either provide you with this permission or to get the service account created for you. The reporting service account reports usage back to Google for Billing purposes, so it does not require specific access to the project but it will need access to report Billing usage.

12. Check the solution terms and conditions and click on the `Download License Key` button. Apply it to the cluster as follows:
```shell
kubectl apply -f license.yaml
```

13. Set the tag variable to the current version available in the Marketplace, e.g.
```shell
export TAG="2.5.0"
```

14. Retrieve the reporting secret name from the cluster which was deployed via `license.yaml`
```shell
# Export the newly create license key name to a variable. This will be used later in the deployment
export reporting_secret_name=$(kubectl describe secret starburst-enterprise-license | grep -i "Name:" | awk '{ print $2 }')
```

15. Apply **Application CRD** to avoid errors
```shell
kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"
```

---
## Create an OAuth 2.0 client to authenticate your Starburst users

16. Get the URL that Starburst will be running on
```shell
echo ${starburst_url}
```

17. Navigate to the [api](https://console.cloud.google.com/apis/credentials) page in the Google Cloud console, and click on *Create Credentials* to create a new *OAuth 2.0 Client*.

18. Click on *OAuth client ID* from the selection list

19. Set the Application type to *Web Application* and provide your client with a name of your choice.

20. Under *Authorized redirect URIs*, click on *Add URI* and include it in the redirect URL for the Starburst Application that you will be deploying.
>*Example:* https://my-starburst-application.my-domain.net/oauth2/callback

21. Export the OAuth 2.0 Client ID & Secret to variables
```shell
export oauth_client_id=
export oauth_client_secret=
```

---
# Helm Deployment Instructions

## Deploying Postgres...

22. Deploy Postgres database instance:
```shell
helm upgrade postgres bitnami/postgresql --install --values ${github_link}postgres.yaml \
    --version 10.16.2 \
    --set primary.nodeSelector.starburstpool=base \
    --set readReplicas.nodeSelector.starburstpool=base
```

>NOTE: This database deploys without a public IP address and is only accessible to the services running on the cluster

## Deploying an Nginx Load Balancer with TLS

23. Deploy Nginx LoadBalancer:
```shell
helm upgrade ingress-nginx ingress-nginx/ingress-nginx --install \
      --set controller.nodeSelector.starburstpool=base \
      --set defaultBackend.nodeSelector.starburstpool=base \
      --set controller.admissionWebhooks.patch.nodeSelector.starburstpool=base
```

24. Deploy Certificate Manager:
```shell
helm upgrade cert-manager jetstack/cert-manager --install --namespace certs-manager --create-namespace \
      --set installCRDs=true \
      --set nodeSelector.starburstpool=base \
      --set webhook.nodeSelector.starburstpool=base \
      --set cainjector.nodeSelector.starburstpool=base
```

25. Deploy Certificate Issuer:

Wait for the Certificate Manager to complete its deployment. Next, make a local copy of [cert-issuer.yaml](https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/helm/cert-issuer.yaml). Add your email address to this file in the place indicated. After the file has been edited, run the following command:
```shell
kubectl apply -f cert-issuer.yaml
```

26. Setup dns:

Get the external IP address created for the nginx load balancer...
```shell
export nginx_loadbalancer_ip=$(kubectl get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Create the Starburst DNS entry... 
```shell
gcloud dns --project=${google_cloud_project_dns} record-sets transaction start --zone="${google_cloud_dns_zone}" && \
gcloud dns --project=${google_cloud_project_dns} record-sets transaction add ${nginx_loadbalancer_ip:?Need to specify an IP or Hostname} --name="${starburst_url}." --ttl="3600" --type="A" --zone="${google_cloud_dns_zone}" && \
gcloud dns --project=${google_cloud_project_dns} record-sets transaction execute --zone="${google_cloud_dns_zone}"
```

---

## Deploying Starburst

27. Deploy Starburst & Hive

```shell
helm upgrade starburst-enterprise https://storage.googleapis.com/starburst-enterprise/helmCharts/sep-gcp/starburst-enterprise-platform-charts-${TAG:?Tag not set}.tgz --install --values ${github_link}values.yaml \
      --set deployerHelm.image="gcr.io/starburst-public/starburstdata/deployer:$TAG" \
      --set reportingSecret=${reporting_secret_name:?Reporting Secret Name not set} \
      --set metricsReporter.image="gcr.io/starburst-public/starburstdata/metrics_reporter:$TAG" \
      --set starburst-enterprise.image.tag="$TAG" \
      --set starburst-enterprise.initImage.tag="$TAG" \
      --set starburst-enterprise.coordinator.resources.limits.cpu=${coordinator_resources_limits_cpu:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=base' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 2800)m)} \
      --set starburst-enterprise.coordinator.resources.requests.cpu=${coordinator_resources_requests_cpu:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=base' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 2800)m)} \
      --set starburst-enterprise.coordinator.resources.limits.memory=${coordinator_resources_memory:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=base' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 5000000)Ki)} \
      --set starburst-enterprise.coordinator.resources.requests.memory=${coordinator_resources_memory:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=base' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 5000000)Ki)} \
      --set starburst-enterprise.worker.minReplicas=1 \
      --set starburst-enterprise.worker.maxReplicas=10 \
      --set starburst-enterprise.worker.resources.limits.cpu=${worker_resources_limits_cpu:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 800)m)} \
      --set starburst-enterprise.worker.resources.requests.cpu=${worker_resources_requests_cpu:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 800)m)} \
      --set starburst-enterprise.worker.resources.limits.memory=${worker_resources_memory:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 1000000)Ki)} \
      --set starburst-enterprise.worker.resources.requests.memory=${worker_resources_memory:-$(echo $(expr $(eval kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 1000000)Ki)} \
      --set starburst-enterprise.sharedSecret="$(openssl rand 64 | base64)" \
      --set "starburst-enterprise.coordinator.etcFiles.properties.config\.properties=coordinator=true
node-scheduler.include-coordinator=false
http-server.http.port=8080
discovery-server.enabled=true
discovery.uri=http://localhost:8080
usage-metrics.cluster-usage-resource.enabled=true
http-server.authentication.allow-insecure-over-http=true
web-ui.enabled=true
http-server.process-forwarded=true
web-ui.authentication.type=oauth2
http-server.authentication.type=oauth2
http-server.authentication.oauth2.issuer=https://accounts.google.com
http-server.authentication.oauth2.auth-url=https://accounts.google.com/o/oauth2/v2/auth
http-server.authentication.oauth2.token-url=https://oauth2.googleapis.com/token
http-server.authentication.oauth2.userinfo-url=https://openidconnect.googleapis.com/v1/userinfo
http-server.authentication.oauth2.jwks-url=https://www.googleapis.com/oauth2/v3/certs
http-server.authentication.oauth2.principal-field=email
http-server.authentication.oauth2.scopes=openid\,https://www.googleapis.com/auth/userinfo.email
http-server.authentication.oauth2.client-id=${oauth_client_id:?OAuth Client ID not set}
http-server.authentication.oauth2.client-secret=${oauth_client_secret:?OAuth Client Secret not set}" \
      --set starburst-enterprise.expose.type=ingress \
      --set starburst-enterprise.expose.ingress.host=${starburst_url:?You need to specify a url} \
      --set starburst-hive.objectStorage.gs.cloudKeyFileSecret=service-account-key \
      --set starburst-hive.image.tag="$TAG" \
      --set starburst-hive.gcpExtraNodePool=base \
      --set starburst-hive.enabled=true ${xtra_args_starburst}
```

---

28. Conection info. Run this command to get a connection info summary for your environment:

```shell
echo -e "\n\nConnection Info:\n----------------\n\nstarburst:\thttps://${starburst_url:-$(kubectl get svc starburst -o jsonpath='{.status.loadBalancer.ingress[0].ip}')}/ui/insights\n\n"
```

---

## Cleaning up
Use these handy commands to clean up your installation when you are done.

29. Delete your cluster.
```shell
gcloud container clusters delete ${cluster_name} \
    --project "${google_cloud_project:?Project name not set}" \
    --zone "${zone}"
```

30. Remove DNS entries.
```shell
gcloud dns record-sets delete "${starburst_url}." \
    --project "${google_cloud_project}" \
    --zone="${google_cloud_dns_zone}" \
    --type="A"
```