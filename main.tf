######################################
######### OpenTofu providers #########
######################################
terraform {
  required_providers {
    # OpenStack provider for Compute/Storage/Networking
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "3.1.0"
    }
    # Cloudflare provider for DNS records
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.5.0"
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
  }
}

# OpenStack Provider config
# WARNING:
#   All other configurations are assumed to be provided from environment variables,
#   make sure you loaded the correct OpenStack RC file before applying this module.
provider "openstack" {
  auth_url = "https://juno.calculquebec.ca:5000"
}

# Cloudflare provider config and variables
variable "cloudflare_api_token" {
  description = "API token for cloudflare DNS zone"
  type        = string
  sensitive   = true
}


variable "clouflare_zone_id" {
  description = "DNS zone ID, get from Cloudflare dashboard"
  type        = string
  default     = "ef0aaf0dd92b0faf0064b84a7da2b67b" # SD4H zone ID
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

#############################
######### VARIABLES #########
#############################

# Cluster name
variable "cluster_name" {
  description = "Resource name for the K8S cluster, will be the prefix to all OpenStack resources created."
  type        = string
}

variable "bastion_name" {
  description = "Friendly name for the Bastion instance."
  type        = string
}

variable "bastion_admin_user_name" {
  description = "User name for the initial admin account that will be created"
  type        = string
}

variable "bastion_admin_user_pub_key" {
  description = "Public SSH key for the admin user"
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
  type        = number
  default     = 3
}

variable "worker_count" {
  description = "The number of worker nodes to create"
  type        = number
  default     = 3
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

variable "lb_user_data_path" {
  description = "Path to the Cloud-Init file for the load balancer(s) VM(s)"
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

### FLOATING IPs AND DNS RECORDS

resource "openstack_networking_floatingip_v2" "bastion_fip" {
  pool = "Public-Network"
}

resource "openstack_networking_floatingip_v2" "lb_fip" {
  pool = "Public-Network"
}

resource "openstack_networking_floatingip_associate_v2" "bastion_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.bastion_fip.address
  port_id     = openstack_networking_port_v2.bastion_port.id
}

resource "openstack_networking_floatingip_associate_v2" "lb_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.lb_fip.address
  port_id     = openstack_networking_port_v2.lb_port.id
}

resource "cloudflare_dns_record" "bastion_dns" {
  zone_id    = var.clouflare_zone_id
  comment    = "${var.cluster_name} bastion DNS"
  content    = openstack_networking_floatingip_v2.bastion_fip.address
  name       = "bastion.${var.cluster_name}.sd4h.ca"
  proxied    = false
  type       = "A"
  ttl        = 3600
  depends_on = [openstack_networking_floatingip_associate_v2.bastion_fip_assoc]
}

resource "cloudflare_dns_record" "lb_dns" {
  zone_id    = var.clouflare_zone_id
  comment    = "${var.cluster_name} load balancer DNS"
  content    = openstack_networking_floatingip_v2.lb_fip.address
  name       = "k8s.${var.cluster_name}.sd4h.ca"
  proxied    = false
  type       = "A"
  ttl        = 3600
  depends_on = [openstack_networking_floatingip_associate_v2.lb_fip_assoc]
}

# Control plane networking
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

# Custom load-balancer networking (TODO: replace with Openstack LBaaS once available)
resource "openstack_networking_network_v2" "lb_net" {
  name           = "${var.cluster_name}-lb-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "lb_subnet" {
  name       = "${var.cluster_name}-lb-subnet"
  network_id = openstack_networking_network_v2.lb_net.id
  cidr       = "172.16.4.0/24"
  ip_version = 4
}

resource "openstack_networking_router_interface_v2" "lb_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.lb_subnet.id
}

resource "openstack_networking_port_v2" "lb_port" {
  network_id         = openstack_networking_network_v2.lb_net.id
  security_group_ids = [openstack_networking_secgroup_v2.lb_sg.id]
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.lb_subnet.id
  }
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
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"
  # 0 for min and max allows all trafic to the control-plane network from the mgmt security group
  port_range_min    = 0
  port_range_max    = 0
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# Worker: allow all TCP from mgmt (for kubespray and k8s management)
resource "openstack_networking_secgroup_rule_v2" "worker_from_mgmt" {
  direction = "ingress"
  ethertype = "IPv4"
  protocol  = "tcp"
  # 0 for min and max allows all trafic to the worker network from the mgmt security group
  port_range_min    = 0
  port_range_max    = 0
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}

# Load Balancer
resource "openstack_networking_secgroup_v2" "lb_sg" {
  name        = "${var.cluster_name}-lb-sg"
  description = "Load Balancer security group"
}

resource "openstack_networking_secgroup_rule_v2" "lb_k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.lb_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "lb_ssh_from_bastion" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.lb_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "cp_from_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_group_id   = openstack_networking_secgroup_v2.lb_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

######### COMPUTE INSTANCES

# Bastion
resource "openstack_blockstorage_volume_v3" "bastion_home" {
  name = "${var.cluster_name}-bastion-home-volume"
  size = 10
}

resource "openstack_compute_instance_v2" "bastion" {
  name      = "${var.cluster_name}-bastion"
  flavor_id = var.bastion_flavor
  key_pair  = var.keypair
  security_groups = [
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
  # user_data  = file(var.bastion_user_data_path)
  user_data = templatefile(var.bastion_user_data_path, {
    bastion_name               = var.bastion_name,
    bastion_admin_user_name    = var.bastion_admin_user_name,
    bastion_admin_user_pub_key = var.bastion_admin_user_pub_key
  })
  depends_on = [openstack_networking_subnet_v2.mgmt_subnet]
}

resource "openstack_compute_volume_attach_v2" "bastion_home_attached" {
  instance_id = openstack_compute_instance_v2.bastion.id
  volume_id   = openstack_blockstorage_volume_v3.bastion_home.id
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
  depends_on = [openstack_networking_subnet_v2.cp_subnet]
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
  depends_on = [openstack_networking_subnet_v2.worker_subnet]
}

resource "openstack_compute_instance_v2" "load_balancer" {
  # count           = 1 # TODO: param
  name            = "${var.cluster_name}-lb"
  flavor_id       = var.bastion_flavor # TODO: own flavor var
  key_pair        = var.keypair
  security_groups = [openstack_networking_secgroup_v2.lb_sg.name]
  network {
    port = openstack_networking_port_v2.lb_port.id
  }
  block_device {
    uuid                  = var.bastion_image # TODO: own image var
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = var.bastion_volume_type
    volume_size           = var.bastion_volume_size
    boot_index            = 0
    delete_on_termination = true
  }
  user_data = templatefile(var.lb_user_data_path, {
    lb_domain = "k8s.${var.cluster_name}.sd4h.ca",
    ip_addrs  = [for i in range(var.control_plane_count) : openstack_compute_instance_v2.control_plane[i].access_ip_v4]
  })
  depends_on = [openstack_networking_subnet_v2.lb_subnet]
}

output "bastion_alias" {
  description = "Bastion SSH alias."
  value       = "alias ${var.bastion_name}=ssh ${var.bastion_admin_user_name}@${cloudflare_dns_record.bastion_dns.name} -t -- "
  depends_on  = [cloudflare_dns_record.bastion_dns]
}
