# Deploying Starburst on Kubernetes
Some simple prebuilt scripts and yamls to quickly deploy Starburst. Includes the following required and optional components:
   - Postgres Database on Kubernetes
   - Hive Metastore Service
   - Starburst Enterprise
   - Nginx LoadBalancer (optional)
   - Certificate Manager (optional)
   - Certificate Issuer (optional. Uses letsencrypt.org by default)

This directory contains all the yamls, shell commands, and instructions on deploying Starburst Enterprise to your Kubernetes environment. Before you attempt to run any of these helm scripts, ensure that your Kubernetes environment is up and running.

>**NOTE!**
*These scripts only work with the Linux/Unix bash shell. Run this on a Mac, Linux or Unix machine if possible OR use a cloud shell from your browser. Amazon, Microsoft and Google offer this utility directly from their UIs.*

---

# Helm Deployment Instructions

## Setting things up...

1. Ensure that you have installed these components:
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [helm](https://helm.sh/docs/intro/install/)
- [lens](https://k8slens.dev/)

>**NOTE!**
*You are not required to run Lens, however, it will make it a lot easier to monitor your deployments as you are running through each step*

2. Add the required Helm repositories:
```shell
helm repo add --username ${registry_usr} --password ${registry_pwd} starburstdata https://harbor.starburstdata.net/chartrepo/starburstdata
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add bitnami https://charts.bitnami.com/bitnami
```

---

## Deploying Postgres and Hive...

3. Deploy Postgres database instance:
```shell
helm upgrade postgres bitnami/postgresql --install --values ${github_link}postgres.yaml \
    --version 10.16.2 \
    --set primary.nodeSelector.starburstpool=base \
    --set readReplicas.nodeSelector.starburstpool=base
```

4. Deploy Hive Metastore Service:
```shell
helm upgrade hive starburstdata/starburst-hive --install --values ${github_link}hive.yaml \
    --set registryCredentials.username=${registry_usr:?Value not set} \
    --set registryCredentials.password=${registry_pwd:?Value not set} \
    --set nodeSelector.starburstpool=base ${xtra_args_hive}
```
---

## OPTIONAL (but strongly recommended): Deploying an Nginx Load Balancer with TLS

Setting up DNS requires a cloud domain. Google, Azure and AWS provide the facility to purchase a domain and set up a DNS zone if you do not have one. You can also use an existing domain and DNS zone that you already own inside or outside the cloud environment that you are deploying to.

The instructions below assume that you have an existing domain and DNS zone, but if you do not, you can purchase one through any of the Cloud providers for a small fee, (see [AWS](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/domain-register.html), [Azure](https://docs.microsoft.com/en-us/azure/app-service/manage-custom-dns-buy-domain), and [Google](https://cloud.google.com/domains/docs/register-domain) for more details).

If you are using an existing Domain and DNS Zone *outside* the cloud environemnt, you just need a hostname or IP address created by the cloud provider Network Load Balancer (NLB) when you deploy nginx, to create the 'A' record to your existing DNS zone.


>**NOTE!**
*Steps 5 to 8 are only needed if you require user authentication to Starburst and are deploying nginx and using dns. Skip to step 9 if you do not require an Nginx loadbalancer or tls certificate from `letsencrypt.org` installed*

5. Deploy Nginx LoadBalancer:
```shell
helm upgrade ingress-nginx ingress-nginx/ingress-nginx --install \
    --set controller.nodeSelector.starburstpool=base \
    --set defaultBackend.nodeSelector.starburstpool=base \
    --set controller.admissionWebhooks.patch.nodeSelector.starburstpool=base
```

6. Deploy Certificate Manager:
```shell
helm upgrade cert-manager jetstack/cert-manager --install --namespace certs-manager --create-namespace \
    --set installCRDs=true \
    --set nodeSelector.starburstpool=base \
    --set webhook.nodeSelector.starburstpool=base \
    --set cainjector.nodeSelector.starburstpool=base
```

7. Deploy Certificate Issuer:

Wait for the Certificate Manager to complete its deployment. Next, edit your local copy of `cert-issuer.yaml`. Add your email address to this file in the place indicated. After the file has been edited, run the following command:
```shell
kubectl apply -f cert-issuer.yaml
```

8. Setup dns:

>**NOTE!**
You are not restricted to creating a dns entry for your cluster in the same cloud where your cluster is running.

>For creating dns entries in Google Cloud, follow these steps:

Get the external IP address created for the nginx load balancer...
```shell
export nginx_loadbalancer_ip=$(kubectl get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Create the Starburst and Ranger DNS entries... 
```shell
gcloud dns --project=${google_cloud_project_dns} record-sets transaction start --zone="${google_cloud_dns_zone}" && \
gcloud dns --project=${google_cloud_project_dns} record-sets transaction add ${nginx_loadbalancer_ip:?Need to specify an IP or Hostname} --name="${starburst_url}." --ttl="3600" --type="A" --zone="${google_cloud_dns_zone}" && \
gcloud dns --project=${google_cloud_project_dns} record-sets transaction execute --zone="${google_cloud_dns_zone}"
```

OR

>For creating dns entries in AWS, follow these steps:

Get the external hostname created for the nginx load balancer...

```shell
export nginx_loadbalancer_ip=$(kubectl get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
```

Create the Starburst DNS entry... 

```shell
aws route53 change-resource-record-sets --hosted-zone-id ${hosted_zone_id:?Value not set}  --change-batch '{ "Comment": "generated by starburst-deploy", "Changes": [ { "Action": "CREATE", "ResourceRecordSet": { "Name": "'"${starburst_url:?You need to specify a url}"'", "Type": "CNAME", "TTL": 3600, "ResourceRecords": [ { "Value": "'"${nginx_loadbalancer_ip:?Need to specify an IP or Hostname}"'" } ] } } ] }'
```
OR

>For creating dns entries in Azure, follow these steps:

Get the external IP address created for the nginx load balancer...

```shell
# Get the external IP address created for the nginx load balancer
export nginx_loadbalancer_ip=$(kubectl get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
```

Create the Starburst entry... 

```shell
az network dns record-set a add-record \
    --record-set-name ${starburst_rs_name} \
    --ipv4-address ${nginx_loadbalancer_ip:?Value not set} \
    --subscription ${dns_subscription:?Value not set} \
    --resource-group ${dns_resource_group} \
    --zone-name ${zone_name:?Value not set} \
    --ttl 3600 \
    --if-none-match
```


---

## Deploying Starburst

>**NOTE!**
*If you are not deploying Nginx, remove the expose.type and expose.ingress.host 'set' values from the command below. The expose type on the Starburst application will default to `ClusterIP`.*

9. Deploy your environment variables
>*this script creates a k8s config file with all the required secrets the environment needs*
```shell
chmod 755 load_secrets.sh && . ./load_secrets.sh
```

10. Apply the secrets to your k8s cluster
```shell
kubectl apply -f secrets.yaml
```

11. Deploy Starburst Enterprise

```shell
helm upgrade starburst-enterprise starburstdata/starburst-enterprise --install --values starburst.yaml \
    --set expose.type=ingress \
    --set expose.ingress.host=${starburst_url:?You need to specify a url} \
    --set registryCredentials.username=${registry_usr:?Value not set} \
    --set registryCredentials.password=${registry_pwd:?Value not set} \
    --set sharedSecret="$(openssl rand 64 | base64)" \
    --set worker.resources.requests.memory=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 1000000)Ki) \
    --set worker.resources.requests.cpu=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 500)m) \
    --set worker.resources.limits.memory=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 1000000)Ki) \
    --set worker.resources.limits.cpu=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 500)m) \
    --set userDatabase.users[0].username=${admin_usr:?Value not set} \
    --set userDatabase.users[0].password=${admin_pwd:?Value not set} \
    --set coordinator.nodeSelector.starburstpool=base \
    --set worker.nodeSelector.starburstpool=worker ${xtra_args_starburst}
```

---

12. Conection info.

Run the appropriate command below to get a connection info summary for your environment:

>AWS Environments:
```shell
echo -e "\n\nConnection Info:\n----------------\n\ncredentials:\t${admin_usr} / ${admin_pwd}\nstarburst:\thttps://${starburst_url:-$(kubectl get svc starburst -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')}\n\nNOTE: use http endpoint if not using nginx & dns! \n\n"
```

>Google Cloud and Azure environments:
```shell
echo -e "\n\nConnection Info:\n----------------\n\ncredentials:\t${admin_usr} / ${admin_pwd}\nstarburst:\thttps://${starburst_url:-$(kubectl get svc starburst -o jsonpath='{.status.loadBalancer.ingress[0].ip}')}\n\nNOTE: use http endpoint if not using nginx & dns! \n\n"
```

13. Data Products.

The Starburst Admin user (default: sbadmin) has sysadmin privileges to the system. However, you still need to create a role and assign appropriate permissions in order to create a Data Product. Please review the required permissions [here](https://docs.starburst.io/latest/data-products/manage-data-products.html#data-product-security).