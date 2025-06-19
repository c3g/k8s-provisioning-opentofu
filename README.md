# Kubernetes provisioning module for OpenStack with OpenTofu

![Infrastructure diagram](./docs/infra.png)

Use this OpenTofu module to provision the infrastructure needed for a secure, high-availability K8S cluster:
- Bastion VM
  - **Only instance to allow SSH from outside**
  - See [The Bastion](https://ovh.github.io/the-bastion/using/basics/first_steps.html) usage docs
  - The opentofu module outputs the Bastion alias for the bootstrapped user
  - Jump proxy SSH connections to:
    - Management VM
    - Load Balancer
  - FLoating IP with a Cloudflare DNS record
  - On the `mgmt-net` network
- Management VM
  - Contains the tools to bootstrap and manage the K8S cluster
  - On the `mgmt-net` network
  - SSH access via Bastion **only**
- Load Balancer VMs
  - Provision an HAProxy VM preconfigured for k8s endpoints on the control-plane
  - HAProxy config for K8S endpoints is auto generated and enabled with Cloud-Init
  - On the `lb-net` network
    - Security group for TCP ingress on port `6443` only
  - SSH access via Bastion **only**
- Control plane VMs
  - Provision the desired number of VMs for the K8S control plane
  - On the `cp-net` network
    - Allow 6443 TCP ingress from load-balancer security-group
    - Allows mgmt and worker security-group trafic
    - SSH via mgmt only (Kubespray)
- Worker VMs
  - Provision the desired number of VMs as K8S worker nodes
  - On the `worker-net` network
    - Allows mgmt and control plane security-group trafic
    - SSH via mgmt only (Kubespray)


## Requirements
Make sure you meet the requirements before using this repository:
-   An OpenStack RC file you can source in your terminal
-   Adequate OpenStack quotas for the resources you plan on creating
-   [OpenTofu CLI](https://opentofu.org/docs/intro/install/)
-   Openstack CLI to get UUIDs and resource names
-   (Recommended) [jq](https://jqlang.org/) to parse JSON variables from OpenStack CLI
-   (Recommended) aws CLI for advanced S3 operations
    -   Why? The aws CLI has the best interfaces to manage versionned buckets

### What/Why OpenTofu?
[OpenTofu](https://opentofu.org/) is a drop-in replacement for Terraform, it enables reliable and 
flexible infrastructure as code on a number of providers, including OpenStack.

Contrary to other Terraform compatible alternatives like Pulumi, OpenTofu is fully free, open-source and under the wing 
of the Linux Foundation, ensuring we won't need to spin on a dime if/when Terraform changes its license for the worst.

## Usage

This repository is intended to be used as a versioned OpenTofu module.

If you meet the requirements, see the [usage](./docs/usage.md) documentation for an example.

