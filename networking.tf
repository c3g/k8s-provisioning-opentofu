######################################
############# NETWORKING #############
######################################

##############
### ROUTER ###
##############

data "openstack_networking_router_v2" "router" {
  name = var.router_name
}

################
### NETWORKS ###
################

# Bastion + Management subnet
resource "openstack_networking_network_v2" "mgmt_net" {
  name           = "${var.cluster_name}-mgmt-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "mgmt_subnet" {
  name       = "${var.cluster_name}-mgmt-subnet"
  network_id = openstack_networking_network_v2.mgmt_net.id
  cidr       = var.mgmt_net_cidr
  ip_version = 4
}

# Custom load-balancer networking (replace with Openstack LBaaS once available)
resource "openstack_networking_network_v2" "lb_net" {
  name           = "${var.cluster_name}-lb-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "lb_subnet" {
  name       = "${var.cluster_name}-lb-subnet"
  network_id = openstack_networking_network_v2.lb_net.id
  cidr       = var.lb_net_cidr
  ip_version = 4
}

# Control plane networking
resource "openstack_networking_network_v2" "cp_net" {
  name = "${var.cluster_name}-cp-net"
}

resource "openstack_networking_subnet_v2" "cp_subnet" {
  name       = "${var.cluster_name}-cp-subnet"
  network_id = openstack_networking_network_v2.cp_net.id
  cidr       = var.cp_net_cidr
  ip_version = 4
}

# Worker subnet
resource "openstack_networking_network_v2" "worker_net" {
  name           = "${var.cluster_name}-worker-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "worker_subnet" {
  name       = "${var.cluster_name}-worker-subnet"
  network_id = openstack_networking_network_v2.worker_net.id
  cidr       = var.worker_net_cidr
  ip_version = 4
}

#########################
### ROUTER INTERFACES ###
#########################

resource "openstack_networking_router_interface_v2" "cp_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.cp_subnet.id
}

resource "openstack_networking_router_interface_v2" "worker_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.worker_subnet.id
}

resource "openstack_networking_router_interface_v2" "mgmt_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.mgmt_subnet.id
}

resource "openstack_networking_router_interface_v2" "lb_router_interface" {
  router_id = data.openstack_networking_router_v2.router.id
  subnet_id = openstack_networking_subnet_v2.lb_subnet.id
}

#############
### PORTS ###
#############

resource "openstack_networking_port_v2" "bastion_port" {
  network_id         = openstack_networking_network_v2.mgmt_net.id
  security_group_ids = [openstack_networking_secgroup_v2.bastion_sg.id]
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.mgmt_subnet.id
  }
}

resource "openstack_networking_port_v2" "lb_port" {
  network_id         = openstack_networking_network_v2.lb_net.id
  security_group_ids = [openstack_networking_secgroup_v2.lb_sg.id]
  fixed_ip {
    subnet_id = openstack_networking_subnet_v2.lb_subnet.id
  }
}


####################
### FLOATING IPs ###
####################

resource "openstack_networking_floatingip_v2" "bastion_fip" {
  pool = "Public-Network"
}

resource "openstack_networking_floatingip_v2" "lb_fip" {
  pool = "Public-Network"
}

resource "openstack_networking_floatingip_associate_v2" "bastion_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.bastion_fip.address
  port_id     = openstack_networking_port_v2.bastion_port.id
  depends_on = [
    openstack_networking_port_v2.bastion_port,
    openstack_networking_router_interface_v2.mgmt_router_interface
  ]
}

resource "openstack_networking_floatingip_associate_v2" "lb_fip_assoc" {
  floating_ip = openstack_networking_floatingip_v2.lb_fip.address
  port_id     = openstack_networking_port_v2.lb_port.id
  depends_on = [
    openstack_networking_port_v2.lb_port,
    openstack_networking_router_interface_v2.lb_router_interface
  ]
}

###########
### DNS ###
###########

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

