terraform {
  required_providers {
    delphix = {
      source  = "delphix-integrations/delphix"
      version = "1.0.0"
    }
  }
}

variable "name" {
  default = ""
}

variable "dct_host" {
  default = ""
}

variable "dct_api_key" {
  default = ""
}

variable "datasource_id" {
  default = "Postgres_master"
}

# Configure the DXI Provider
provider "delphix" {
  tls_insecure_skip = true
  key               = var.dct_api_key
  host              = var.dct_host
}

# Provision a VDB 1
resource "delphix_vdb" "provision_vdb_1" {
  name                   = "${var.name}-dev"
  source_data_id         = var.datasource_id
  auto_select_repository = true
}
