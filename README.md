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
-   [OpenTofu CLI](https://opentofu.org/docs/intro/install/)
-   An S3 bucket in your OpenStack project reserved for OpenTofu (e.g. "fried_tofu")
-   S3 credentials valid for the bucket
-   (Recommended) openstack CLI to get UUIDs and resource names

## What/Why OpenTofu?
[OpenTofu](https://opentofu.org/) is a drop-in replacement for Terraform, it enables reliable and 
flexible infrastructure as code on a number of providers, including OpenStack.

Contrary to other Terraform compatible alternatives like Pulumi, OpenTofu is fully free, open-source and under the wing 
of the Linux Foundation, ensuring we won't need to spin on a dime if/when Terraform changes its license for the worst.

### Storage backend

Read more on the OpenTofu [Backend config page](https://opentofu.org/docs/language/settings/backends/configuration/).
This repo implements the [Remote State](https://opentofu.org/docs/language/state/remote/) backend using SD4H's S3 API.

This state management strategy is more robust, especially when working in teams:
> With remote state, OpenTofu writes the state data to a remote data store, which can then be shared between all members
>  of a team. OpenTofu supports storing state in TACOS (TF Automation and Collaboration Software), HashiCorp Consul, 
> Amazon S3, Azure Blob Storage, Google Cloud Storage, Alibaba Cloud OSS, and more.

For usage on SD4H, the most convenient path is to use the provided S3 API!
Before applying this module, make sure you have the following ready:
1. Your OpenStack project has a private bucket dedicated to OpenTofu
2. You have S3 credentials on that project
   1. Find existing credentials with `openstack ec2 credentials create`, pay attention to the project ID
   2. If you don't already have credentials for that project, generate them with `openstack ec2 credentials create`

## Usage

Using this template is as simple as this:

```bash
# clone or fork this repo, then cd to it

# Source the OpenStack RC file.
# Make sure to use the file for the appropriate OpenStack project!!!
# You will be prompted for your password
source my-project-openrc.sh

# List your S3 credentials
openstack ec2 credentials list

# Load the S3 credentials in env variables for security
export AWS_ACCESS_KEY_ID=<ACCESS KEY VALUE FROM ABOVE>
export AWS_SECRET_ACCESS_KEY=<SECRET KEY VALUE FROM ABOVE>

# (Optional but recommended)
# Prepare the variables for the OpenTofu module
# If you don't do this, OpenTofu will give you interactive prompts to provide values.
cp terraform.tfvars.example terraform.tfvars

# Modify the variables according to your needs
#   code terraform.tfvars   # in VSCode
#   vim terraform.tfvars    # in Vim

# Init the OpenTofu directory
tofu init

# Plan the OpenTofu deployment
tofu plan

# Review the plan and fix what needs fixing, then plan again
# Repeat until no errors in plan

# Apply your deployment plan!
tofu apply
```

Assuming that apply went well, you now have all your VMs, networks, 
security groups and floating IP ready for the K8S bootstrap!

### Configuration variables

The `terraform.tfvars` file is auto discovered by OpenTofu when running `plan` and `apply`, 
use it to provide the values to the required variables.

```bash
# Cluster name, will be the prefix to all OpenStack resources created.
# Use a lower case hyphen-separated name for consistency
cluster_name = "c3g-dev-k8s"

# Image variables, always use the ID.
#   Get options with 'openstack image list'
bastion_image = "IMAGE UUID"
mgmt_image = "IMAGE UUID"
control_plane_image = "IMAGE UUID"
worker_image = "IMAGE UUID"

# Flavor variables, always use the ID.
#   Get options with 'openstack flavor list'
bastion_flavor = "FLAVOR UUID"         # ha2-2.5gb
mgmt_flavor = "FLAVOR UUID"            # ha2-2.5gb
control_plane_flavor = "FLAVOR UUID"   # ha8-10gb
worker_flavor = "FLAVOR UUID"          # ha8-10gb

# Volume sizes in GB.
bastion_volume_size = 20
mgmt_volume_size = 20
control_plane_volume_size = 50
worker_volume_size = 50

# Volume types
bastion_volume_type = "volumes-ssd"
mgmt_volume_type = "volumes-ssd"
control_plane_volume_type = "volumes-ssd"
worker_volume_type = "volumes-ssd"

# OpenStack keypair
#   Get valid options with 'openstack keypair list'
keypair = "YOUR KEYPAIR NAME"

# Networking
public_network_id = "PUBLIC NETWORK UUID"
router_name = "ROUTER NAME"

```

## Kubernetes bootstrap

### Kubespray
COMING SOON

### Talos and talosctl
COMING SOON

## DNS bootstrap
COMING SOON

