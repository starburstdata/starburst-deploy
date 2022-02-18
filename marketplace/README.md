# Deploying Starburst through the Cloud Marketplace
The step-by-step guide on how to install Starburst through the Cloud Marketplace on your own. Please ensure you have sufficient access to your Cloud environment to do this.

>NOTE: These are Helm deployments to Kubernetes, and the Google Cloud Marketplace is the only Marketplace where this is currently supported.

## Why do I need a separate deployment option for Marketplace?
The deployment steps outlined under the root folder are designed to deploy from Starburst's Helm repository, which requires a Starburst license and credentials provided by Starburst. The Marketplace deployment does not have this restriction. The deployment, licensing and billing has been simplified to run through your existing Cloud Billing, which makes it simpler to deploy and manage.

## But why not just use the Marketplace UI?
You can use the UI, but the UI does not give you the flexibility to add your custom data sources to your deployment, or secure access to your Starburst application using Google OAuth. This approach does.

## What about AWS or Azure?
Coming soon.