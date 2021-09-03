# Deploying Starburst to Kubernetes
Some simple prebuilt scripts and yamls to quickly deploy Starburst. Includes the following required and optional components:
   - Postgres Database on Kubernetes
   - Hive Metastore Service
   - Starburst Enterprise
   - Apache Ranger
   - Nginx LoadBalancer (optional)
   - Certificate Manager (optional)
   - Certificate Issuer (optional. Uses letsencrypt.org by default)

This directory contains all the yamls, shell commands, and instructions on deploying Starburst Enterprise to your Kubernetes environment. Before you attempt to run any of these helm scripts, ensure that your Kubernetes environment is up and running.

**NOTE!**
*These scripts only work with the Linux/Unix bash shell. Run this on a Mac, Linux or Unix machine if possible OR use a cloud shell from your browser. Amazon, Microsoft and Google offer this utility directly from their UIs.*

---

# Helm Deployment Instructions

## Setting things up...

1. Ensure that you have installed these components:
- [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
- [helm](https://helm.sh/docs/intro/install/)

2. Set the following shell variables according to your deployment goals:
```
## Deploy Starburst ##
export registry_usr=?
export registry_pwd=?
export admin_usr=?
export admin_pwd=?
# For Google Deployments
export google_cloud_project=?
# Shouldn't need to change this link, unless we move the repo
export github_link="https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/helm/"
# These URLS are used if deploying nginx and dns.
export starburst_url=?
export ranger_url=?
```

3. Add the required Helm repositories:
```
helm repo add --username ${registry_usr} --password ${registry_pwd} starburstdata https://harbor.starburstdata.net/chartrepo/starburstdata
helm repo add jetstack https://charts.jetstack.io
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```
---

## Deploying Postgres and Hive...
4. Deploy Postgres database instance:
```
helm upgrade postgres bitnami/postgresql --install --values ${github_link}postgres.yaml \
	--set primary.nodeSelector.starburstpool=base \
	--set readReplicas.nodeSelector.starburstpool=base
```

5. Deploy Hive Metastore Service:
```
helm upgrade hive starburstdata/starburst-hive --install --values ${github_link}hive.yaml \
	--set registryCredentials.username=${registry_usr} \
	--set registryCredentials.password=${registry_pwd} \
	--set objectStorage.gs.cloudKeyFileSecret=service-account-key \
	--set nodeSelector.starburstpool=base
```
---

## OPTIONAL: Deploying an Nginx Load Balancer

**NOTE!**
*Steps 6 to 8 are only required if you are deploying nginx and using dns to access the deployed applications.*

6. Deploy Nginx LoadBalancer
```
helm upgrade ingress-nginx ingress-nginx/ingress-nginx --install \
	--set controller.nodeSelector.starburstpool=base \
	--set defaultBackend.nodeSelector.starburstpool=base \
	--set controller.admissionWebhooks.patch.nodeSelector.starburstpool=base
```

7. Deploy Certificate Manager
```
helm upgrade cert-manager jetstack/cert-manager --install --namespace certs-manager --create-namespace \
	--set installCRDs=true \
	--set nodeSelector.starburstpool=base \
	--set webhook.nodeSelector.starburstpool=base \
	--set cainjector.nodeSelector.starburstpool=base
```

8. Deploy Certificate Issuer
```
kubectl apply -f cert-issuer.yaml
```
---

## Deploying Starburst and Ranger

**NOTE!**
*If you are not deploying Nginx, remove the expose.type and expose.ingress.host 'set' values from the command below*

9. Deploy Starburst Enterprise
```
helm upgrade starburst-enterprise starburstdata/starburst-enterprise --install --values ${github_link}starburst.yaml --values ${github_link}starburst.yaml \
	--set expose.type=ingress \
	--set expose.ingress.host=${starburst_url:?You need to specify a url} \
	--set registryCredentials.username=${registry_usr} \
	--set registryCredentials.password=${registry_pwd} \
	--set "catalogs.bigquery=connector.name=bigquery
		bigquery.project-id=${google_cloud_project}" \
	--set "catalogs.postgresql=connector.name=postgresql
		connection-url=jdbc:postgresql://postgresql:5432/insights
		connection-user=postgres
		connection-password=${postgres_pwd}" \
	--set "coordinator.etcFiles.properties.access-control\.properties=access-control.name=ranger
		ranger.authentication-type=BASIC
		ranger.policy-rest-url=http://ranger:6080
		ranger.service-name=starburst-enterprise
		ranger.username=${admin_usr}
		ranger.password=${admin_pwd}
		ranger.policy-refresh-interval=10s" \
	--set "worker.etcFiles.properties.access-control\.properties=access-control.name=ranger
		ranger.authentication-type=BASIC
		ranger.policy-rest-url=http://ranger:6080
		ranger.service-name=starburst-enterprise
		ranger.username=${admin_usr}
		ranger.password=${admin_pwd}
		ranger.policy-refresh-interval=10s" \
	--set worker.resources.requests.memory=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 1000000)Ki) \
	--set worker.resources.requests.cpu=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 500)m) \
	--set worker.resources.limits.memory=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.memory}' | awk -F "Ki" '{ print $1 }') - 1000000)Ki) \
	--set worker.resources.limits.cpu=$(echo $(expr $(kubectl get nodes --selector='starburstpool=worker' -o jsonpath='{.items[0].status.allocatable.cpu}' | awk -F "m" '{ print $1 }') - 500)m) \
	--set userDatabase.users[0].username=${admin_usr} \
	--set userDatabase.users[0].password=${admin_pwd} \
	--set expose.ingress.host=${starburst_url:?You need to specify a url} \
	--set coordinator.nodeSelector.starburstpool=base \
	--set worker.nodeSelector.starburstpool=worker
```

10. Deploy Apache Ranger
```
helm upgrade starburst-ranger starburstdata/starburst-ranger --install --values ${github_link}ranger.yaml \
	--set expose.type=ingress \
	--set expose.ingress.host=${ranger_url:?You need to specify a url} \
	--set registryCredentials.username=${registry_usr} \
	--set registryCredentials.password=${registry_pwd} \
	--set admin.serviceUser=${admin_usr} \
	--set datasources[0].username=${admin_usr} \
	--set datasources[0].password=${admin_pwd} \
	--set nodeSelector.starburstpool=base
```
---