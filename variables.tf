#############################
######### VARIABLES #########
#############################

###### Storage backend BEGIN ######
# See https://opentofu.org/docs/language/settings/backends/s3/

variable "s3_endpoint" {
  description = "S3 endpoint to use for backend storage."
  type        = string
  default     = "https://objets.juno.calculquebec.ca"
}

variable "s3_bucket" {
  description = "S3 bucket to store infra state"
  type = string
  default = "fried_tofu"
}

variable "s3_region" {
  description = "S3 region to use for backend storage"
  type = string
  default = "us-east-1"
}
###### Storage backend END ######

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

#### Networking

variable "mgmt_net_cidr" {
  description = "CIDR for the MGMT network"  
  type = string
}

variable "cp_net_cidr" {
  description = "CIDR for the Control-Plane network"  
  type = string
}

variable "worker_net_cidr" {
  description = "CIDR for the Worker network"  
  type = string
}

variable "lb_net_cidr" {
  description = "CIDR for the Worker network"  
  type = string
}
# "172.16.2.0/24"
