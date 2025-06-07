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

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

######################################
############# NETWORKING #############
######################################

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
  depends_on = [ openstack_networking_port_v2.lb_port ]
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

resource "openstack_networking_router_interface_v2" "cp_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.cp_subnet.id
}

# Worker subnet
resource "openstack_networking_network_v2" "worker_net" {
  name = "${var.cluster_name}-worker-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "worker_subnet" {
  name       = "${var.cluster_name}-worker-subnet"
  network_id = openstack_networking_network_v2.worker_net.id
  cidr       = "172.16.3.0/24"
  ip_version = 4
}

resource "openstack_networking_router_interface_v2" "worker_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.worker_subnet.id
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

###################################
######### SECURITY GROUPS #########
###################################
# See ./security-groups.tf for the rules

# Bastion: allow SSH from anywhere
resource "openstack_networking_secgroup_v2" "bastion_sg" {
  name        = "${var.cluster_name}-bastion-sg"
  description = "Allow SSH"
}

# Management: allow SSH only from bastion
resource "openstack_networking_secgroup_v2" "mgmt_sg" {
  name        = "${var.cluster_name}-mgmt-sg"
  description = "Allow SSH from bastion"
}

# Control plane: allow SSH from mgmt
resource "openstack_networking_secgroup_v2" "cp_sg" {
  name        = "${var.cluster_name}-cp-sg"
  description = "Allow SSH and TCP from mgmt"
}

# Worker: allow SSH from mgmt
resource "openstack_networking_secgroup_v2" "worker_sg" {
  name        = "${var.cluster_name}-worker-sg"
  description = "Allow SSH and TCP from mgmt"
}

# Load Balancer
resource "openstack_networking_secgroup_v2" "lb_sg" {
  name        = "${var.cluster_name}-lb-sg"
  description = "Load Balancer security group"
}

#####################################
######### COMPUTE INSTANCES #########
#####################################

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
  user_data  = templatefile(var.mgmt_user_data_path, {
    cluster_name = var.cluster_name
  })
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
