terraform {
  required_version = "~>1.14.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = "0.193.0"
    }
    elasticstack = {
      source = "elastic/elasticstack"
    }
  }
}

provider "yandex" {
  service_account_key_file = var.service_account_key_file
  cloud_id                 = var.cloud_id
  folder_id                = var.folder_id
}

provider "elasticstack" {
  kibana {
    endpoints = ["http://${var.kibana_ip}:5601"]
  }
}
