# Deploying Starburst on EKS through the AWS Marketplace
Command line instructions to deploy an Amazon EKS cluster. These have been designed to run on Linux/Unix, Mac or in a Cloud Shell. There are no additional files required to support these instructions.

## Setup instructions

1. Ensure that you have installed these components:
    - [aws cli](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html)
    - [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl/)
    - [helm](https://helm.sh/docs/intro/install/). *minimum Helm version required: 3.7.1*
    - [eksctl](https://eksctl.io/introduction/#installation)
    - [lens](https://k8slens.dev/) OR [k9s](https://k9scli.io/)

2. Ensure that you are running these in the `bash` shell

>NOTE!
This is pretty important if you are running these commands on a Mac, which defaults to the zsh. You will need to switch to the bash terminal since it can handle multi-line strings referenced later in some of the helm commands

```shell
bash
```

3. Edit and set the following shell variables:

>TIP: Copy and paste this section into a shell script and edit the values from there.

```shell
# Shouldn't need to change this link, unless we move the repo
export github_link="https://raw.githubusercontent.com/starburstdata/starburst-deploy/main/marketplace/aws/"

# Starburst Specifics
export starburst_version=380.1.1

# Cluster specifics
export region=                                 # AWS Region to deploy your cluster to
export cluster_name=                           # Give your cluster a name

# These last remaining values are static
export xtra_args_hive=""
export xtra_args_starburst=""
export xtra_args_ranger=""
```

---
## Deploy an EKS cluster

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

7. Install the cluster autoscaler
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
## Deploy Starburst from the AWS Marketplace

8. Login to the AWS Console and navigate to the AWS Marketplace. Click on Discover Products and search for Starburst EKS in the Marketplace. Select the `Starburst Enterprise for EKS PayGo` option from the search results.
<img src="./img/aws_eks_marketplace_paygo_listing.png?sanitize=true">

9. Click the `Continue to Subscribe` button, then click the `Continue to Configuration` button. Select `Helm Chart` for the Fulfillment option, `Helm Chart CLI Installation` and pick the latest version of Starburst Enterprise. Finally click on the `Continue to Launch` button.

10. Create a Kubernetes Namespace for your Starburst cluster
```shell
kubectl create namespace starburst-enterprise
```

11. Create an AWS IAM role and Kubernetes service account
```shell
eksctl create iamserviceaccount \
    --name starburst-enterprise-sa \
    --namespace starburst-enterprise \
    --cluster ${cluster_name:?Value not set} \
    --attach-policy-arn arn:aws:iam::aws:policy/AWSMarketplaceMeteringFullAccess \
    --attach-policy-arn arn:aws:iam::aws:policy/AWSMarketplaceMeteringRegisterUsage \
    --attach-policy-arn arn:aws:iam::aws:policy/service-role/AWSLicenseManagerConsumptionPolicy \
    --approve \
    --override-existing-serviceaccounts
```

12. Set global variable for Helm to mitigate errors in helm deployment
```shell
export HELM_EXPERIMENTAL_OCI=1
```

13. Retrieve the login credentials for the AWS Elastic Container Registry (ECR)
```shell
aws ecr get-login-password \
    --region us-east-1 | helm registry login \
    --username AWS \
    --password-stdin 709825985650.dkr.ecr.us-east-1.amazonaws.com
```

14. Create a local directory for the Starburst Helm chart
```shell
mkdir awsmp-chart && cd awsmp-chart
```

15. Download the latest Helm chart from the AWS ECR.
```shell
helm pull oci://709825985650.dkr.ecr.us-east-1.amazonaws.com/starburst/starburst-enterprise-helm-chart-paygo --version ${starburst_version:?Value not set}-paygo.aws.1
```

16. Extract the helm chart package
```shell
tar xf $(pwd)/* && find $(pwd) -maxdepth 1 -type f -delete
```

17. Install the Starburst application via Helm
```shell
helm install starburst-enterprise-$(echo ${starburst_version%%.*}) \
    --namespace starburst-enterprise ./* 
```

---
## Post-installation

18. Retrieving the kubectl config file.
If you are deploying to a cloud shell or to a remote system and you are using Lens locally to monitor the deployments, then run this command on your remote system to retrieve the kubernetes configuration:
```shell
echo aws eks update-kubeconfig --name ${cluster_name:?Value not set} --region ${region:?Value not set}
```
Then run the output from the echo command on your local machine to update your local kubectl.config with your new cluster's details.

---

## Cleaning up

19. Deleting your cluster.
```shell
eksctl delete cluster -f eksctl.yaml 
```
