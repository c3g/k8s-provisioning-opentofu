###################################
######### SECURITY GROUPS #########
###################################

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

########################################
############ SECGROUP RULES ############
########################################

###############
### BASTION ###
###############

resource "openstack_networking_secgroup_rule_v2" "bastion_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.bastion_sg.id
}

resource "openstack_networking_secgroup_rule_v2" "mgmt_ssh_from_bastion" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.bastion_sg.id
  security_group_id = openstack_networking_secgroup_v2.mgmt_sg.id
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

###########################
### CONTROL PLANE RULES ###
###########################

# SSH from mgmt
resource "openstack_networking_secgroup_rule_v2" "cp_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# Talos API (from mgmt and cp nodes)
resource "openstack_networking_secgroup_rule_v2" "cp_talos_api_from_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 50000
  port_range_max    = 50000
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "cp_talos_api_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 50000
  port_range_max    = 50000
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# etcd peer (internal)
resource "openstack_networking_secgroup_rule_v2" "cp_etcd_peer" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2380
  port_range_max    = 2380
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# etcd client (internal)
resource "openstack_networking_secgroup_rule_v2" "cp_etcd_client" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 2379
  port_range_max    = 2379
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# Kubernetes API server (from LB and mgmt)
resource "openstack_networking_secgroup_rule_v2" "cp_k8s_api_from_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_group_id   = openstack_networking_secgroup_v2.lb_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "cp_k8s_api_from_mgmt" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# kubelet API (internal, from cp and worker)
resource "openstack_networking_secgroup_rule_v2" "cp_kubelet_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "cp_kubelet_api_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# NodePort range (default 30000-32767, from LB and internal)
resource "openstack_networking_secgroup_rule_v2" "cp_nodeport_from_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_group_id   = openstack_networking_secgroup_v2.lb_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "cp_nodeport_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "cp_nodeport_from_worker" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}

# Allow all traffic between control plane and worker nodes (for CNI, kube-proxy, etc.)
resource "openstack_networking_secgroup_rule_v2" "cp_to_worker_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = null
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "worker_to_cp_all" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = null
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.cp_sg.id
}


#############################
### WORKER SECGROUP RULES ###
#############################

# SSH from mgmt
resource "openstack_networking_secgroup_rule_v2" "worker_ssh" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 22
  port_range_max    = 22
  remote_group_id   = openstack_networking_secgroup_v2.mgmt_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}

# kubelet API (from cp and worker)
resource "openstack_networking_secgroup_rule_v2" "worker_kubelet_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "worker_kubelet_api_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 10250
  port_range_max    = 10250
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}

# NodePort range (default 30000-32767, from LB and internal)
resource "openstack_networking_secgroup_rule_v2" "worker_nodeport_from_lb" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_group_id   = openstack_networking_secgroup_v2.lb_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "worker_nodeport_internal" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_group_id   = openstack_networking_secgroup_v2.worker_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}
resource "openstack_networking_secgroup_rule_v2" "worker_nodeport_from_cp" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 30000
  port_range_max    = 32767
  remote_group_id   = openstack_networking_secgroup_v2.cp_sg.id
  security_group_id = openstack_networking_secgroup_v2.worker_sg.id
}

#####################
### LOAD BALANCER ###
#####################

# Kubernetes API from anywhere (or restrict as needed)
resource "openstack_networking_secgroup_rule_v2" "lb_k8s_api" {
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 6443
  port_range_max    = 6443
  remote_ip_prefix  = "0.0.0.0/0"
  security_group_id = openstack_networking_secgroup_v2.lb_sg.id
}

##################
### EGRESS ALL ###
##################

# Should already be enabled by default, uncomment otherwise

# resource "openstack_networking_secgroup_rule_v2" "egress_all_cp" {
#   direction         = "egress"
#   ethertype         = "IPv4"
#   protocol          = null
#   security_group_id = openstack_networking_secgroup_v2.cp_sg.id
# }
# resource "openstack_networking_secgroup_rule_v2" "egress_all_worker" {
#   direction         = "egress"
#   ethertype         = "IPv4"
#   protocol          = null
#   security_group_id = openstack_networking_secgroup_v2.worker_sg.id
# }
# resource "openstack_networking_secgroup_rule_v2" "egress_all_lb" {
#   direction         = "egress"
#   ethertype         = "IPv4"
#   protocol          = null
#   security_group_id = openstack_networking_secgroup_v2.lb_sg.id
# }
