# Module usage

This module can be reused like any other OpenTofu/Terraform module, the process follows these steps:

1. Create a git repository for your IaC
2. Create a local dir for the repository
3. Configure the S3 storage backend
4. Declare a `module` block in `main.tf` that uses this module
5. Provide the required variables
6. Plan the deployment
7. Apply the deployment
8. Destroy the deployment when no longer needed

The following sections cover this process in more details.

## Create a git repository for your IaC

> [!NOTE]
> This step is optional but STRONGLY recommended for production setups.
> 
> If you are just making tests you can simply create a local directory.

This repository should be private.

Use the git repository to commit and push changes as your infrastructure needs evolve.
Multiple clusters can share the same repository, make a directory for each cluster.

Add collaborators to the repository to contribute as a team.

## Create a local directory

Either clone the repository from the previous step, or create a local directory manually for testing.

Open the project directory with your favorite IDE.

The following project structure is recommended:
```
.
├── main.tf
├── terraform.tfvars
├── variables.tf
└── userdata
    ├── bastion.yaml
    ├── k8s-master.yaml
    ├── k8s-worker.yaml
    ├── load-balancer.yaml
    └── mgmt.yaml
```

An example of this structure can be copied from the `example` directory in this repo.

## Storage backend configuration

Read more on the OpenTofu [Backend config page](https://opentofu.org/docs/language/settings/backends/configuration/).
This repo implements the [Remote State](https://opentofu.org/docs/language/state/remote/) backend using SD4H's S3 API.

This state management strategy is more robust, especially when working in teams:
> With remote state, OpenTofu writes the state data to a remote data store, which can then be shared between all members
>  of a team. OpenTofu supports storing state in TACOS (TF Automation and Collaboration Software), HashiCorp Consul, 
> Amazon S3, Azure Blob Storage, Google Cloud Storage, Alibaba Cloud OSS, and more.

For usage on SD4H, the most convenient path is to use the provided S3 API!
> [!IMPORTANT]
> Before applying this module, make sure you have the following ready:
1. Your OpenStack project has a private bucket dedicated to OpenTofu, **with bucket versioning enabled**
   1. Bucket versioning must be enabled with the S3 API, Swift will not work. (instructions bellow)
2. You have S3 credentials on that project
   1. Find existing credentials with `openstack ec2 credentials list`, pay attention to the project ID
   2. If you don't already have credentials for that project, generate them with `openstack ec2 credentials create`

**If you don't have the above, here is how to set it up quickly:**

```bash
# Source the OpenStack RC file for your project
source my-project-openrc.sh

# Create S3 credentials for your user in the current project
openstack ec2 credentials create

# Create a local profile for your aws CLI for S3 operations on SD4H (change my-profile to the OpenStack project name)
# This is needed to setup bucket versioning
aws configure --profile=my-profile
# > AWS Access Key ID [None]: <COPY FROM ABOVE>
# > AWS Secret Access Key [None]: <COPY FROM ABOVE>
# > Default region name [None]: <LEAVE EMPTY>
# > Default output format [None]: json  

# For convenience, make an alias that includes the SD4H object store endpoint
# Use an alias name that clearly identifies the OpenStack project name
alias aws-sd4h-my-profile="aws --profile my-profile --endpoint-url=https://objets.juno.calculquebec.ca"

# Create a regular bucket for storage backend
aws-sd4h-my-profile s3 mb s3://fried_tofu

# Enable bucket versioning on the created bucket
aws-sd4h-my-profile s3api put-bucket-versioning \
  --bucket fried_tofu \
  --versioning-configuration Status=Enabled

# Verify versioning is enabled
aws-sd4h-my-profile s3api get-bucket-versioning --bucket fried_tofu
# {
#    "Status": "Enabled",
#    "MFADelete": "Disabled"
# }
```

Set the S3 bucket variable in `terraform.tfvars`:

```bash
# terraform.tfvars
s3_bucket = "fried_tofu"
```

Now, every time `tofu apply` is used, a new state version will be automatically uploaded to the S3 bucket we configured.


This allows us to retrieve a previous state if needed. To get the list of state object versions:

```bash
aws-sd4h-my-profile s3api list-object-versions --bucket fried_tofu --prefix <cluster_name variable value>
```

## Cloud-Init templates

The VM provisioning relies on Cloud-Init for all nodes, ready to use files can be found at `userdata/`.

Add a public SSH key you own in the authorized keys sections. This is only for admin recovery in case Bastion goes belly-up.

All SSH connections will go through The Bastion host, an admin user will be created for you so you can manage the instance.

> [!WARNING]
> Always avoid leaking sensitive data to source control.
>
> If a cloud-init file includes sensitive information (e.g. Talos machine configs), **it should never be commited to source-control in plain text**. Add such files to your `.gitignore` file to avoid leaking credentials.
>
> [SOPS](https://getsops.io/) can be used to encrypt the yaml values in Cloud-Init files, if tracking of files with secrets is needed.

## Configuration variables

The `terraform.tfvars` file is auto discovered by OpenTofu when running `plan` and `apply`, 
use it to provide the values to the required variables.

The OpenStack CLI will come in handy here to obtain IDs and names of existing resources that are required:
- Images
- Flavors
- Networks, Routers
- Volume types
- Key pairs

## Usage

With the S3 storage backend in place, using this module is as simple as this:

```bash
# Source the OpenStack RC file.
# Make sure to use the file for the appropriate OpenStack project!!!
source my-project-openrc.sh

# Load the S3 credentials in env variables for security
# The following commands extract the ACCESS_KEY and SECRET from the first credential found in the current project
# These keys
export AWS_ACCESS_KEY_ID=$(\
  openstack ec2 credential list --format json | \
  jq -r '[.[] | select(."Project ID"==$ENV.OS_PROJECT_ID)] | .[0].Access'
)
export AWS_SECRET_ACCESS_KEY=$(\
  openstack ec2 credential list --format json | \
  jq -r '[.[] | select(."Project ID"==$ENV.OS_PROJECT_ID)] | .[0].Secret'
)

# Modify the variables according to your needs (see previous section)
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

It also creates a DNS record for the Bastion VM: `bastion.<CLUSTER NAME>.sd4h.ca`

## Bastion config

After a succesful `tofu apply`, the module will output the Bastion alias for your admin user.

You will need to wait a few minutes for the Cloud-Init to be fully applied before attempting to SSH.

Once the Clout-Init has been applied, you should be able to SSH using the alias output.
If the Bastion DNS record is not propagated yet, using the IP instead of the domain also works.

### Create Bastion group

```bash
# Create a group
<BASTION ALIAS> --osh groupCreate --group k8s --owner <BASTION ADMIN USER NAME> --algo ed25519
# Copy the group's public key
```

### Prepare VMs to be accessible via Bastion

To make VMs accessible via the Bastion group you created, you need to add the group's public SSH key to the VMs' user data.

Do the following in:
  - `userdata/mgmt.yaml`
  - `userdata/load-balancer.yaml` (optional, can be done later)

```yaml
#cloud-config
users:
  # ... don't touch the other users, just update the 'bastion' user
  - name: bastion
    groups: adm, wheel, systemd-journal
    selinux_user: unconfined_u
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys: [
      # ADD BASTION GROUP'S EGRESS KEY HERE!!!
      <YOUR-BASTION-GROUP-EGRESS-KEY>,
    ]
```

Changing Cloud-Init files will result in VMs being fully replaced, you only need to do this once.

Review the plan and apply it if it looks good:

```bash
# Review plan
tofu plan

# Apply the changes
tofu apply
```

Wait for Cloud-Init to finish, otherwise the new authorized SSH key will not be ready.

### Add VMs to the Bastion group

Now we can add the VMs to the list of servers belonging to the Bastion group.
Use the `groupAddServer` Bastion command to add the management server to the group.
```bash
# For the mgmt VM
<BASTION ALIAS> --osh groupAddServer --group k8s --host <CLUSTER NAME>-mgmt --user bastion --port 22

# For the Load Balancer (optional)
<BASTION ALIAS> --osh groupAddServer --group k8s --host <LB PRIVATE IP> --user bastion --port 22 --comment "load balancer"

# Test access!
# e.g. bssh bastion@c3g-dev-k8s-mgmt
<BASTION ALIAS> bastion@<CLUSTER NAME>-mgmt
```

At this point, the users in the group can connect to the management VM via bastion, and bootstrap the K8S cluster!
K8S managers will need to have Bastion accounts, they can jump to the management VM by using the Bastion SSH alias:
```bash
# Users need to setup their Bastion alias in their .bash_aliases
alias bssh-<CLUSTER NAME>='ssh <USERNAME>@bastion.<CLUSTER NAME>.sd4h.ca -t -- '

# SSH to the mgmt VM via Bastion!
<BASTION ALIAS> bastion@<CLUSTER NAME>-mgmt
```

## Kubernetes bootstrap

Everything should now be ready to begin bootstraping your HA Kubernetes cluster!
- An HAProxy load balancer is serving the K8S endpoints
- Networks and security groups isolate control-plane and workers

We recommend and document two popular options: [Kubespray](https://kubespray.io) and [Talos Linux](https://www.talos.dev/v1.10/)

### Kubespray
COMING SOON

### Talos and talosctl

Refer to the official Talos Linux instructions for cluster configuration on Openstack, [here](https://www.talos.dev/v1.10/talos-guides/install/cloud-platforms/openstack/#cluster-configuration).

The steps before "Cluster Configuration" have been taken care of by the OpenTofu module, start from there until you have a working kubeconfig.

#### Generate Clout-Init files for Talos
```bssh
# SSH to the management VM
<BASTION ALIAS> bastion@<CLUSTER NAME>-mgmt

# Install talosctl
curl -sL https://talos.dev/install | sh

# Generate the talosconfig
talosctl gen config <CLUSTER NAME> https://${LB_PUBLIC_IP}:6443

# Copy the content of 'controlplane.yaml'
# Copy the content of 'worker.yaml'
```

#### Provision Talos control-plane and workers
Paste the content of 'controlplane.yaml' into `userdata/k8s-master.yaml`.
Paste the content of 'worker.yaml' into `userdata/k8s-worker.yaml`.

> [!CAUTION]
> Talos Cloud-Init files contain sensitive information, never commit them.
> 
> The files can be retrieved from the mgmt VM by authorized Bastion users when needed.

This will cause a replacement of all control-plane and worker nodes, with the required Talos user data for bootstrap.

Plan and apply the changes:
```bash
tofu plan   # make sure planned changes look OK
tofu apply  # apply the changes
```

#### Bootstrap Talos

Once the control-plane and worker VMs are up and running, we can bootstrap the Talos cluster.
Take note of the private IP for one of the control-plane VMs (doesn't matter which one!).

```bash
# SSH to the management VM
<BASTION ALIAS> bastion@<CLUSTER NAME>-mgmt

# Configure Talos bootstrap endpoint
talosctl --talosconfig talosconfig config endpoint <control plane 1 IP>
talosctl --talosconfig talosconfig config node <control plane 1 IP>

# Bootstrap the cluster!
talosctl --talosconfig talosconfig bootstrap

# Get the kubeconfig file and place it at the expected location for kubectl
talosctl --talosconfig talosconfig kubeconfig .
mkdir -p ~/.kube
cp kubeconfig ~/.kube/config

# Start using the cluster!
kubectl get nodes     # All nodes should be in status "Ready"
kubectl get pods -A   # All pods in kube-system namespace should be running
```


## Cleaning up

At any time, the provisioned infrastructure can be quickly destroyed and recreated with a few `tofu` commands:

```bash
# Destroy
tofu destroy

# Recreate
tofu plan
tofu apply
```
