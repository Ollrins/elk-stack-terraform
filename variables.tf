variable "service_account_key_file" {
  type        = string
  description = "Path to service account key file"
}

variable "cloud_id" {
  type        = string
  description = "Yandex Cloud ID"
}

variable "folder_id" {
  type        = string
  description = "Yandex Folder ID"
}

variable "ssh_public_key" {
  type        = string
  description = "Path to SSH public key file"
}

variable "ssh_user" {
  type        = string
  description = "SSH username"
  default     = "Ollrins"
}

variable "vm_image_id" {
  type        = string
  description = "VM image ID (Rocky Linux 9)"
  default     = "fd828j3n8sa03unu5arm"
}

variable "zone" {
  type        = string
  description = "Availability zone"
  default     = "ru-central1-e"
}

variable "platform_id" {
  type        = string
  description = "Compute platform"
  default     = "standard-v3"
}

variable "vm_cores" {
  type        = number
  description = "CPU cores"
  default     = 4
}

variable "vm_memory" {
  type        = number
  description = "Memory (GB)"
  default     = 8
}

variable "core_fraction" {
  type        = number
  description = "CPU core fraction"
  default     = 100
}

variable "disk_size" {
  type        = number
  description = "Boot disk size in GB"
  default     = 30
}

variable "disk_type" {
  type        = string
  description = "Boot disk type"
  default     = "network-ssd"
}

variable "subnet_cidr" {
  type        = string
  description = "CIDR block for subnet"
  default     = "192.168.20.0/24"
}

variable "internal_cidr" {
  type        = string
  description = "Internal CIDR"
  default     = "192.168.0.0/16"
}

variable "network_name" {
  type        = string
  description = "VPC network name"
  default     = "elk-lab-network"
}

variable "vm_name" {
  type        = string
  description = "VM name"
  default     = "elk-lab"
}

variable "sg_name" {
  type        = string
  description = "Security group name"
  default     = "elk-lab-sg"
}

variable "timezone" {
  type        = string
  description = "Timezone"
  default     = "Europe/Moscow"
}

variable "elk_version" {
  type        = string
  description = "Elastic Stack version"
  default     = "8.11.0"
}

variable "kibana_ip" {
  type        = string
  description = "Public IP of Kibana host"
}
