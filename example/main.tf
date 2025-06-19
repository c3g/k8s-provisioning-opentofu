terraform {
  backend "s3" {
    bucket = var.s3_bucket
    key    = var.cluster_name
    region = var.s3_region
    endpoints = {
      s3 = "${var.s3_endpoint}"
    }
    # Skip validations that fail with Ceph S3
    skip_requesting_account_id  = true
    skip_credentials_validation = true
  }
}

module "k8s_cluster" {
  source = "git@github.com:c3g/k8s-provisioning-opentofu.git//?ref=v1.0.0"
  # General 
  cluster_name         = var.cluster_name
  cloudflare_api_token = var.cloudflare_api_token
  keypair              = var.keypair
  public_network_id    = var.public_network_id
  router_name          = var.router_name
  # Images
  bastion_image       = var.bastion_image
  mgmt_image          = var.mgmt_image
  control_plane_image = var.control_plane_image
  worker_image        = var.worker_image
  lb_image            = var.lb_image
  # Flavors
  bastion_flavor       = var.bastion_flavor
  mgmt_flavor          = var.mgmt_flavor
  control_plane_flavor = var.control_plane_flavor
  worker_flavor        = var.worker_flavor
  lb_flavor            = var.lb_flavor
  # Root volume sizes/types
  bastion_volume_size       = var.bastion_volume_size
  mgmt_volume_size          = var.mgmt_volume_size
  control_plane_volume_size = var.control_plane_volume_size
  worker_volume_size        = var.worker_volume_size
  bastion_volume_type       = var.bastion_volume_type
  mgmt_volume_type          = var.mgmt_volume_type
  control_plane_volume_type = var.control_plane_volume_type
  worker_volume_type        = var.worker_volume_type
  # k8s node counts
  control_plane_count = var.control_plane_count
  worker_count        = var.worker_count
  # Userdata (Cloud-Init)
  bastion_user_data_path = var.bastion_user_data_path
  mgmt_user_data_path    = var.mgmt_user_data_path
  cp_user_data_path      = var.cp_user_data_path
  worker_user_data_path  = var.worker_user_data_path
  lb_user_data_path      = var.lb_user_data_path
  # Bastion
  bastion_name               = var.bastion_name
  bastion_admin_user_name    = var.bastion_admin_user_name
  bastion_admin_user_pub_key = var.bastion_admin_user_pub_key
  # CIDRs
  mgmt_net_cidr   = var.mgmt_net_cidr
  lb_net_cidr     = var.lb_net_cidr
  worker_net_cidr = var.worker_net_cidr
  cp_net_cidr     = var.cp_net_cidr
}

output "bastion_alias" {
  value = module.k8s_cluster.bastion_alias
}
