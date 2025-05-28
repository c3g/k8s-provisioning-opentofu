# Kubernetes provisioning template for OpenStack with OpenTofu

Use this repository as a template to provision the resources needed for a secure high-availability K8S cluster:
- Bastion VM
  - Secures SSH access to the management VM
  - FLoating IP
  - On the `mgmt-net` network
  - Security group for SSH
- Management VM
  - Accessible via Bastion only
  - Contains the tools to bootstrap and manage the K8S cluster
  - On the `mgmt-net` network
  - Security group allows SSH from Bastion only
- Control plane VMs
  - Provision a number of VMs for the K8S control plane
  - On the `cp-net` network
  - Security group allows mgmt and worker trafic
- Worker VMs
  - Provision a number of VMs as K8S worker nodes
  - On the `worker-net` network
  - Security group allows mgmt and control plane trafic


## Requirements
Make sure you meet the requirements before using this repository:
-   An OpenStack RC file you can source in your terminal
-   Adequate OpenStack quotas for the resources you plan on creating
-   [OpenTofu](https://opentofu.org/docs/intro/install/)
-   (Recommended) openstack CLI to get UUIDs and resource names

## What/Why OpenTofu?
[OpenTofu](https://opentofu.org/) is a drop-in replacement for Terraform, it enables reliable and 
flexible infrastructure as code on a number of providers, including OpenStack.

Contrary to other Terraform compatible alternatives like Pulumi, OpenTofu is fully free, open-source and under the wing of the Linux Foundation, ensuring we won't need to spin on a dime if/when Terraform changes
its license for the worst.

## Usage

Using this template is as simple as this:

```bash
# clone or fork this repo, then cd to it

# Prepare the variables for the OpenTofu module
cp terraform.tfvars.example terraform.tfvars

# Modify the variables according to your needs
#   code terraform.tfvars   # in VSCode
#   vim terraform.tfvars   # in Vim

# Init the OpenTofu directory
tofu init

# Plan the OpenTofu deployment
tofu plan

# Review the plan and fix what needs fixing, then plan again
# Repeat until no errors in plan

# Apply your deployment plan!
tofu apply
```

Assuming that apply went well, you now have all your VMs, networks, security groups and floating IP ready for the K8S bootstrap!

## Kubernetes bootstrap

### Kubespray
COMING SOON

### Talos and talosctl
COMING SOON

## DNS bootstrap
COMING SOON

