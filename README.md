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
-   Openstack CLI to get UUIDs and resource names
-   (Recommended) [jq](https://jqlang.org/) to parse JSON variables from OpenStack CLI
-   (Recommended) aws CLI for advanced S3 operations
    -   Why? The aws CLI has the best interfaces to manage versionned buckets

### What/Why OpenTofu?
[OpenTofu](https://opentofu.org/) is a drop-in replacement for Terraform, it enables reliable and 
flexible infrastructure as code on a number of providers, including OpenStack.

Contrary to other Terraform compatible alternatives like Pulumi, OpenTofu is fully free, open-source and under the wing 
of the Linux Foundation, ensuring we won't need to spin on a dime if/when Terraform changes its license for the worst.

### Storage backend configuration

Read more on the OpenTofu [Backend config page](https://opentofu.org/docs/language/settings/backends/configuration/).
This repo implements the [Remote State](https://opentofu.org/docs/language/state/remote/) backend using SD4H's S3 API.

This state management strategy is more robust, especially when working in teams:
> With remote state, OpenTofu writes the state data to a remote data store, which can then be shared between all members
>  of a team. OpenTofu supports storing state in TACOS (TF Automation and Collaboration Software), HashiCorp Consul, 
> Amazon S3, Azure Blob Storage, Google Cloud Storage, Alibaba Cloud OSS, and more.

For usage on SD4H, the most convenient path is to use the provided S3 API!
Before applying this module, make sure you have the following ready:
1. Your OpenStack project has a private bucket dedicated to OpenTofu, **with bucket versioning enabled**
   1. Bucket versioning must be enabled with the S3 API, Swift will not work. (instructions bellow)
2. You have S3 credentials on that project
   1. Find existing credentials with `openstack ec2 credentials list`, pay attention to the project ID
   2. If you don't already have credentials for that project, generate them with `openstack ec2 credentials create`

If you don't have the above, here is how to set it up quickly:

```bash
# Source the OpenStack RC file for your project
source my-project-openrc.sh

# Create S3 credentials for your user in the current project
openstack ec2 credentials create

# Create a local profile for your aws CLI for S3 operations on SD4H (change my-profile to the OpenStack project name)
# This is needed to setup bucket versioning
aws configure --profile=my-profile
> AWS Access Key ID [None]: <COPY FROM ABOVE>
> AWS Secret Access Key [None]: <COPY FROM ABOVE>
> Default region name [None]: <LEAVE EMPTY>
> Default output format [None]: json  

# For convenience, make an alias that includes the SD4H object store endpoint
alias aws-sd4h-my-profile="aws --profile my-profile --endpoint-url=https://objets.juno.calculquebec.ca"

# Create a regular bucket for storage backend
aws-sd4h-my-profile s3 mb s3://fried_tofu

# Enable bucket versioning on the created bucket
aws-sd4h-my-profile s3api put-bucket-versioning \
  --bucket fried_tofu \
  --versioning-configuration Status=Enabled

# Verify versioning is enabled
aws-sd4h-my-profile s3api get-bucket-versioning --bucket fried_tofu
# Good to go if you get this in the response: { "Status" : "Enabled"}
```

Now, every time `tofu apply` is used, a new state version will be automatically uploaded to the S3 bucket we configured.
This allows us to rollback to a previous state if needed. To get the list of state object versions:

```bash
aws-sd4h-my-profile s3api list-object-versions --bucket fried_tofu --prefix <cluster_name variable value>
```

## Usage

With the S3 storage backend in place, using this template is as simple as this:

```bash
# clone or fork this repo, then cd to it

# Source the OpenStack RC file.
# Make sure to use the file for the appropriate OpenStack project!!!
source my-project-openrc.sh

# Load the S3 credentials in env variables for security
export AWS_ACCESS_KEY_ID=$(\
  openstack ec2 credential list --format json | \
  jq -r '[.[] | select(."Project ID"==$ENV.OS_PROJECT_ID)] | .[0].Access'
)
export AWS_SECRET_ACCESS_KEY=$(\
  openstack ec2 credential list --format json | \
  jq -r '[.[] | select(."Project ID"==$ENV.OS_PROJECT_ID)] | .[0].Secret'
)

# (Optional but recommended)
# Prepare the variables for the OpenTofu module
# If you don't do this, OpenTofu will give you interactive prompts to provide values.
cp terraform.tfvars.example terraform.tfvars

# Modify the variables according to your needs
vim terraform.tfvars

# Init the OpenTofu directory
tofu init

# Plan the OpenTofu deployment
tofu plan

# Review the plan and fix what needs fixing, then plan again
# Repeat until no errors in plan

# Apply your deployment plan!
tofu apply
```

Assuming that apply went well, you now have all your VMs, networks, security groups and floating IPs ready for the K8S bootstrap!

### Configuration variables

The `terraform.tfvars` file is auto discovered by OpenTofu when running `plan` and `apply`, 
use it to provide the values to the required variables.

```bash
# Cluster name, will be the prefix to all OpenStack resources created.
# Use a lower case hyphen-separated name for consistency
cluster_name = "c3g-dev-k8s"

# Image variables, always use the ID.
#   Get options with 'openstack image list'
bastion_image       = "IMAGE UUID"
mgmt_image          = "IMAGE UUID"
control_plane_image = "IMAGE UUID"
worker_image        = "IMAGE UUID"

# Flavor variables, always use the ID.
#   Get options with 'openstack flavor list'
bastion_flavor       = "FLAVOR UUID"
mgmt_flavor          = "FLAVOR UUID"
control_plane_flavor = "FLAVOR UUID"
worker_flavor        = "FLAVOR UUID"

# Volume sizes in GB.
bastion_volume_size       = 20
mgmt_volume_size          = 20
control_plane_volume_size = 50
worker_volume_size        = 50

# Volume types: volumes-ssd OR volumes-ec
bastion_volume_type       = "volumes-ssd"
mgmt_volume_type          = "volumes-ssd"
control_plane_volume_type = "volumes-ssd"
worker_volume_type        = "volumes-ssd"

# Instance counts
control_plane_count = 3 # Default (3 or more for HA)
worker_count        = 3 # Default (3 or more for HA)

# Cloud-Init (User data)
bastion_user_data_path = "userdata/bastion.yaml"  # Make sure to add your public SSH key in the Bastion cloud-init !!!
mgmt_user_data_path    = "userdata/mgmt.yaml"
cp_user_data_path      = "userdata/k8s-master.yaml"
worker_user_data_path  = "userdata/k8s-worker.yaml"

# OpenStack keypair
#   Get valid options with 'openstack keypair list'
keypair = "YOUR KEYPAIR NAME"

# Networking
public_network_id = "PUBLIC NETWORK UUID"
router_name       = "ROUTER NAME"
```

## Bastion config

After a succesful `tofu apply`, you should be able to SSH to the bastion VM.
There, follow the [installation instructions](https://ovh.github.io/the-bastion/installation/basic.html) for 
OVH's The-Bastion.

In the Bastion: 
- [Create a group](https://ovh.github.io/the-bastion/plugins/restricted/groupCreate.html#groupcreate) for the Kubernetes admins, add the required users to that group.
- [Create an account](https://ovh.github.io/the-bastion/plugins/restricted/accountCreate.html) for each K8S manager.
- [Add the accounts to the group](https://ovh.github.io/the-bastion/plugins/group-gatekeeper/groupAddMember.html#groupaddmember)
- [Get the egress key for the group you created](https://ovh.github.io/the-bastion/plugins/open/groupInfo.html)
  - This is a public SSH key that needs to be added to the management VM

To add the key to the management VM, edit the `./userdata/mgmt.yaml` file and add the egress key to the 'bastion' user:

```yaml
#cloud-config
users:
  # ... don't touch the other users, just update 'bastion'
  - name: bastion
    groups: adm, wheel, systemd-journal
    selinux_user: unconfined_u
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys: [
      # ADD BASTION GROUP'S EGRESS KEY HERE!!!
      YOUR-BASTION-GROUP-EGRESS-KEY,
    ]
```

Changing this value will result in the management VM being fully replaced, so only do this once.

Review the plan and apply it if it looks good:

```bash
# Review plan
tofu plan

# Apply the changes
tofu apply
```

Now we can add the management VM to the list of servers belonging to the Bastion group:
1. SSH into bastion with the alias (`bssh` by default).
2. Use the `groupAddServer` command to add the management server to the group.
```bash
# In Bastion:
groupAddServer --group <your group> --host <mgmt VM IP on the mgmt network> --user bastion --port 22
```

At this point, the users in the group can connect to the management VM via bastion, and bootstrap the K8S cluster!

## Kubernetes bootstrap

### Kubespray
COMING SOON

### Talos and talosctl
COMING SOON

## DNS bootstrap
COMING SOON

