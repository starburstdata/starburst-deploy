# Deploying Starburst on GKE from the Google Cloud Marketplace
Some simple scripts and yamls to deploy Starburst via the Google Cloud Marketplace using the command line. Please note, that the current GUI-based installation does not allow you to modify the configuration after Starburst has been deployed. This command line approach allows you to customize your deployment and apply updates as required.

>IMPORTANT! This installation assumes that you already have a GKE cluster deployed per the instructions outlined [here](https://github.com/starburstdata/starburst-deploy/tree/main/googlecloud)

The following components will be deployed:
   - Postgres Database on Kubernetes
   - Hive Metastore Service
   - Starburst Enterprise
   - Nginx LoadBalancer
   - Certificate Manager
   - Certificate Issuer

This directory contains all the yamls, shell commands, and instructions on deploying Starburst Enterprise to your Kubernetes environment. Before you attempt to run any of these helm scripts, ensure that your Kubernetes environment is up and running.

>**NOTE!**
*These scripts only work with the Linux/Unix bash shell. Run this on a Mac, Linux or Unix machine if possible OR use a cloud shell from your browser. Amazon, Microsoft and Google offer this utility directly from their UIs.*

## Setting things up...

1. Ensure that you have installed these components:
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [helm](https://helm.sh/docs/intro/install/)
- [lens](https://k8slens.dev/)

>**NOTE!**
*You are not required to run Lens, however, it will make it a lot easier to monitor your deployments as you are running through each step*

2. Add the required Helm repositories:
```shell
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add bitnami https://charts.bitnami.com/bitnami
```

---
# Google Cloud Console

## Get the license.yaml file from the Google Marketplace

3. Navigate to the [Google Cloud Marketplace SEP](https://console.cloud.google.com/marketplace/product/starburst-public/starburst-enterprise) offering and select *Configure*

4. Switch to *Deploy via command line* tab

5. If you have the *Billing Account Admininstrator* role, then leave the **Reporting service account** dropdown set to *Create new service acount*. If not, you will need to use an existing **Reporting service account** from the dropdown.

>**WARNING!**
If you do not have the *Billing Account Admininstrator* role and there are no **Reporting service accounts** available, you will not be able to proceed with the Marketplace deployment! Please see your Google Account Administrator to either provide you with this permission or to get the service account created for you. The reporting service account reports usage back to Google for Billing purposes, so it does not require specific access to the project but it will need access to report Billing usage.

6. Check the solution terms and conditions and click on the `Download License Key` button. Apply it to the cluster as follows:
```shell
kubectl apply -f license.yaml
```

7. Set the tag variable to the current version available in the Marketplace, e.g.
```shell
export TAG="2.4.0"
```

8. Set the following addional shell variables:
```shell
# Export the newly create license key name to a variable. This will be used later in the deployment
export reporting_secret_name=$(kubectl describe secret starburst-enterprise-license | grep -i "Name:" | awk '{ print $2 }')
# Static link to the default values.yaml used by the Marketplace
export github_link="https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/marketplace/googlecloud/"
```

9. Apply **Application CRD** to avoid errors
```shell
kubectl apply -f "https://raw.githubusercontent.com/GoogleCloudPlatform/marketplace-k8s-app-tools/master/crd/app-crd.yaml"
```

---
## Create an OAuth 2.0 client to authenticate your Starburst users

10. Get the URL that Starburst will be running on
```shell
echo ${starburst_url}
```

11. Navigate to the [api](https://console.cloud.google.com/apis/credentials) page in the Google Cloud console, and click on *Create Credentials* to create a new *OAuth 2.0 Client*.

12. Click on *OAuth client ID* from the selection list

13. Set the Application type to *Web Application* and provide your client with a name of your choice.

14. Under *Authorized redirect URIs*, click on *Add URI* and include it in the redirect URL for the Starburst Application that you will be deploying.
>*Example:* https://my-starburst-application.my-domain.net/oauth2/callback

15. Export the OAuth 2.0 Client ID & Secret to variables
```shell
export oauth_client_id=
export oauth_client_secret=
```

---
# Helm Deployment Instructions

## Deploying Postgres...

16. Deploy Postgres database instance:
```shell
helm upgrade postgres bitnami/postgresql --install --values ${github_link}postgres.yaml \
    --version 10.16.2 \
    --set primary.nodeSelector.starburstpool=base \
    --set readReplicas.nodeSelector.starburstpool=base
```

>NOTE: This database deploys without a public IP address and is only accessible to the services running on the cluster

## Deploying an Nginx Load Balancer and setup dns

17. Deploy Nginx LoadBalancer:
```shell
helm upgrade ingress-nginx ingress-nginx/ingress-nginx --install \
      --set controller.nodeSelector.starburstpool=base \
      --set defaultBackend.nodeSelector.starburstpool=base \
      --set controller.admissionWebhooks.patch.nodeSelector.starburstpool=base
```

18. Deploy Certificate Manager:
```shell
helm upgrade cert-manager jetstack/cert-manager --install --namespace certs-manager --create-namespace \
      --set installCRDs=true \
      --set nodeSelector.starburstpool=base \
      --set webhook.nodeSelector.starburstpool=base \
      --set cainjector.nodeSelector.starburstpool=base
```

19. Deploy Certificate Issuer:

Wait for the Certificate Manager to complete its deployment. Next, make a local copy of [cert-issuer.yaml](https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/helm/cert-issuer.yaml). Add your email address to this file in the place indicated. After the file has been edited, run the following command:
```shell
kubectl apply -f cert-issuer.yaml
```

20. Setup dns:

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

## Deploying Starburst and Ranger

21. Deploy Starburst & Hive

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
      --set starburst-hive.enabled=true
```

---

22. Conection info. Run this command to get a connection info summary for your environment:

```shell
echo -e "\n\nConnection Info:\n----------------\n\nstarburst:\thttps://${starburst_url:-$(kubectl get svc starburst -o jsonpath='{.status.loadBalancer.ingress[0].ip}')}/ui/insights\n\n"
```