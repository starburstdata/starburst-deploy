# starburst-deploy

Some easy to follow step-by-step instructions on installing Starburst to AWS, Azure or Google Cloud.

>**NOTE!**
*Instructions have been updated and include multiple different jumpstarts, depending on how you would like to deploy. In addition, it is now necessary to download the repo to your local system before running the commands*

---

## Download the repository to your local environment
```shell
gh repo clone starburstdata/starburst-deploy
```

## How to use
Installation is a 2 stage process:

1. Stage 1 - install the Kubernetes cluster in your cloud environment using the instructions provided in either the `aws`, `azure` or `googlecloud` folders.

2. Stage 2 - install the Starburst application components using the instructions provided in one of the jumpstarts which can be found under the `helm` folder.