######### OpenStack OpenTofu provider
terraform {
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.1.0"
    }
  }
  backend "s3" {
    bucket = "fried_tofu"
    key    = var.cluster_name
    region = "us-east-1"
    endpoints = {
      s3 = "${var.s3_endpoint}"
    }
    # Skip validations that fail with Ceph S3
    skip_requesting_account_id  = true
    skip_credentials_validation = true
    # NOTE: requires AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY to be loaded in env vars
  }
}

# Configure the OpenStack Provider
# WARNING !!!
#   All other configurations are assumed to be provided from environment variables,
#   make sure you loaded the correct OpenStack RC file before applying this module.
provider "openstack" {
  auth_url = "https://juno.calculquebec.ca:5000"
}

######### Variables

# Cluster name
variable "cluster_name" {
  description = "Resource name for the K8S cluster, will be the prefix to all OpenStack resources created."
  type        = string
}

# Storage backend
# See https://opentofu.org/docs/language/settings/backends/s3/
variable "s3_endpoint" {
  description = "S3 endpoint to use for backend storage."
  type        = string
  default     = "https://objets.juno.calculquebec.ca"
}

# Openstack keypair to use
variable "keypair" {
  description = "SSH keypair name"
  type        = string
}

# Image variables
variable "bastion_image" {
  description = "Image to use for the Bastion VM"
  type        = string
}

variable "mgmt_image" {
  description = "Image to use for the management VM"
  type        = string
}

variable "control_plane_image" {
  description = "Image to use for the control-plane VMs"
  type        = string
}

variable "worker_image" {
  description = "Image to use for the worker VMs"
  type        = string
}

# Flavor variables
variable "bastion_flavor" {
  description = "Bastion flavor"
  type        = string
}

variable "mgmt_flavor" {
  description = "Management flavor"
  type        = string
}

variable "control_plane_flavor" {
  description = "K8S control plane flavor"
  type        = string
}

variable "worker_flavor" {
  description = "K8S worker flavor"
  type        = string
}

# K8S nodes counts
variable "control_plane_count" {
  description = "The number of control plane nodes to create"
  type = number
  default = 3
}

variable "worker_count" {
  description = "The number of worker nodes to create"
  type = number
  default = 3
}

# Volume sizes & types
variable "bastion_volume_size" {
  description = "Bastion volume size in GB"
  type        = number
}

variable "mgmt_volume_size" {
  description = "Management volume size in GB"
  type        = number
}

variable "control_plane_volume_size" {
  description = "K8S control Plane volume size in GB"
  type        = number
}

variable "worker_volume_size" {
  description = "K8S worker node volume size in GB"
  type        = number
}

variable "bastion_volume_type" {
  description = "Bastion volume type"
  type        = string
}

variable "mgmt_volume_type" {
  description = "Management volume type"
  type        = string
}

variable "control_plane_volume_type" {
  description = "K8S control Plane volume type"
  type        = string
}

variable "worker_volume_type" {
  description = "K8S worker volume type"
  type        = string
}

variable "public_network_id" {
  description = "ID of the public network"
  type        = string
}

variable "router_name" {
  description = "OpenStack router name"
  type        = string
}

# User data
variable "bastion_user_data_path" {
  description = "Path to the Cloud-Init file for Bastion setup"
  type        = string
}

variable "mgmt_user_data_path" {
  description = "Path to the Cloud-Init file for MGMT VM"
  type        = string
}

variable "cp_user_data_path" {
  description = "(Optional) Path to the Cloud-Init file for Control-Plane VMs"
  type        = string
}

variable "worker_user_data_path" {
  description = "(Optional) Path to the Cloud-Init file for Control-Plane VMs"
  type        = string
}

######### NETWORKING

# Bastion + Management subnet
resource "openstack_networking_network_v2" "mgmt_net" {
  name           = "${var.cluster_name}-mgmt-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "mgmt_subnet" {
  name       = "${var.cluster_name}-mgmt-subnet"
  network_id = openstack_networking_network_v2.mgmt_net.id
  cidr       = "172.16.1.0/24"
  ip_version = 4
}

data "openstack_networking_router_v2" "router" {
  name = var.router_name
}

resource "openstack_networking_router_interface_v2" "mgmt_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.mgmt_subnet.id
}

resource "openstack_networking_port_v2" "bastion_port" {
  network_id         = openstack_networking_network_v2.mgmt_net.id
  security_group_ids = [openstack_networking_secgroup_v2.bastion_sg.id]
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.mgmt_subnet.id
  }
}

resource "openstack_networking_floatingip_associate_v2" "bastion_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.bastion_fip.address
  port_id     = openstack_networking_port_v2.bastion_port.id
}

# Control plane subnet
resource "openstack_networking_network_v2" "cp_net" {
  name = "${var.cluster_name}-cp-net"
}

resource "openstack_networking_subnet_v2" "cp_subnet" {
  name       = "${var.cluster_name}-cp-subnet"
  network_id = openstack_networking_network_v2.cp_net.id
  cidr       = "172.16.2.0/24"
  ip_version = 4
}

# Worker subnet
resource "openstack_networking_network_v2" "worker_net" {
  name = "${var.cluster_name}-worker-net"
}

resource "openstack_networking_subnet_v2" "worker_subnet" {
  name       = "${var.cluster_name}-worker-subnet"
  network_id = openstack_networking_network_v2.worker_net.id
  cidr       = "172.16.3.0/24"
  ip_version = 4
}

######### SECURITY GROUPS

# Bastion: allow SSH from anywhere
resource "openstack_networking_secgroup_v2" "bastion_sg" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Allow SSH"
}

resource "openstack_networking_secgroup_rule_v2" "bastion_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_sg.id
}

# Management: allow SSH only from bastion
resource "openstack_networking_secgroup_v2" "mgmt_sg" {
  name        = "${var.cluster_name}-mgmt-sg"
  description = "Allow SSH from bastion"
}

resource "openstack_networking_secgroup_rule_v2" "mgmt_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.mgmt_sg.id
}

# Control plane: allow SSH from mgmt
resource "openstack_networking_secgroup_v2" "cp_sg" {
  name        = "${var.cluster_name}-cp-sg"
  description = "Allow SSH and TCP from mgmt"
}

resource "openstack_networking_secgroup_rule_v2" "cp_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# Worker: allow SSH from mgmt
resource "openstack_networking_secgroup_v2" "worker_sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Allow SSH and TCP from mgmt"
}

resource "openstack_networking_secgroup_rule_v2" "worker_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}

# Control plane: allow all TCP from mgmt (for kubespray and k8s management)
resource "openstack_networking_secgroup_rule_v2" "cp_from_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  # 0 for min and max allows all trafic to the control-plane network from the mgmt security group
  port_range_min    = 0
  port_range_max    = 0
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# Worker: allow all TCP from mgmt (for kubespray and k8s management)
resource "openstack_networking_secgroup_rule_v2" "worker_from_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  # 0 for min and max allows all trafic to the worker network from the mgmt security group
  port_range_min    = 0
  port_range_max    = 0
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}

######### FLOATING IP FOR BASTION

resource "openstack_networking_floatingip_v2" "bastion_fip" {
  pool = "Public-Network"
}

######### COMPUTE INSTANCES

# Bastion
# TODO: bootstrap OVH's The Bastion
resource "openstack_compute_instance_v2" "bastion" {
  name      = "${var.cluster_name}-bastion"
  flavor_id = var.bastion_flavor
  key_pair  = var.keypair
  security_groups = [
    "default",
    openstack_networking_secgroup_v2.bastion_sg.name
  ]
  network {
    port = openstack_networking_port_v2.bastion_port.id
  }
  block_device {
    uuid                  = var.bastion_image
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = var.bastion_volume_type
    volume_size           = var.bastion_volume_size
    boot_index            = 0
    delete_on_termination = true
  }
  # user_data  = file("${var.bastion_user_data_path}")
  user_data  = file(var.bastion_user_data_path)
  depends_on = [openstack_networking_subnet_v2.mgmt_subnet]
}

# Management VM
resource "openstack_compute_instance_v2" "mgmt" {
  name            = "${var.cluster_name}-mgmt"
  flavor_id       = var.mgmt_flavor
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.mgmt_sg.name]
  network {
    uuid = openstack_networking_network_v2.mgmt_net.id
  }
  block_device {
    uuid                  = var.mgmt_image
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = var.mgmt_volume_type
    volume_size           = var.mgmt_volume_size
    boot_index            = 0
    delete_on_termination = true
  }
  user_data  = file("${var.mgmt_user_data_path}")
  depends_on = [openstack_networking_subnet_v2.mgmt_subnet]
}

# Control plane VMs
resource "openstack_compute_instance_v2" "control_plane" {
  count           = var.control_plane_count
  name            = "${var.cluster_name}-cp-${count.index + 1}"
  flavor_id       = var.control_plane_flavor
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.cp_sg.name]
  network {
    uuid = openstack_networking_network_v2.cp_net.id
  }
  block_device {
    uuid                  = var.control_plane_image
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = var.control_plane_volume_type
    volume_size           = var.control_plane_volume_size
    boot_index            = 0
    delete_on_termination = true
  }
  user_data  = file("${var.cp_user_data_path}")
  depends_on = [openstack_networking_network_v2.cp_net]
}

# Worker VMs
resource "openstack_compute_instance_v2" "worker" {
  count           = var.worker_count
  name            = "${var.cluster_name}-worker-${count.index + 1}"
  flavor_id       = var.worker_flavor
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.worker_sg.name]
  network {
    uuid = openstack_networking_network_v2.worker_net.id
  }
  block_device {
    uuid                  = var.worker_image
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = var.worker_volume_type
    volume_size           = var.worker_volume_size
    boot_index            = 0
    delete_on_termination = true
  }
  user_data  = file("${var.worker_user_data_path}")
  depends_on = [openstack_networking_network_v2.worker_net]
}
