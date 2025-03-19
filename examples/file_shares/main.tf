provider "azurerm" {
  features {}
  storage_use_azuread = true
}

data "http" "my_ip" {
  url = "https://ifconfig.me"
}

data "azurerm_subscription" "current" {
}

resource "random_string" "random" {
  length  = 12
  upper   = false
  special = false
}

module "subscription" {
  source          = "github.com/Azure-Terraform/terraform-azurerm-subscription-data.git?ref=v1.0.0"
  subscription_id = data.azurerm_subscription.current.subscription_id
}

module "naming" {
  source = "git@github.com:Azure-Terraform/example-naming-template.git?ref=v1.0.0"
}

module "metadata" {
  source = "github.com/Azure-Terraform/terraform-azurerm-metadata.git?ref=v1.1.0"

  naming_rules = module.naming.yaml

  market              = "us"
  project             = "https://github.com/Azure-Terraform/terraform-azurerm-storage-account/tree/main/example"
  location            = "eastus2"
  environment         = "sandbox"
  product_name        = random_string.random.result
  business_unit       = "infra"
  product_group       = "contoso"
  subscription_id     = module.subscription.output.subscription_id
  subscription_type   = "dev"
  resource_group_type = "app"
}

module "resource_group" {
  source = "github.com/Azure-Terraform/terraform-azurerm-resource-group.git?ref=v1.0.0"

  location = module.metadata.location
  names    = module.metadata.names
  tags     = module.metadata.tags
}

module "virtual_network" {
  source = "github.com/Azure-Terraform/terraform-azurerm-virtual-network.git?ref=v5.0.0"

  naming_rules = module.naming.yaml

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  names               = module.metadata.names
  tags                = module.metadata.tags

  address_space = ["10.1.1.0/24"]

  subnets = {
    iaas-outbound = {
      cidrs             = ["10.1.1.0/27"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
}

locals {
  storage_account_name = "sandboxxyzdevsa"
  smb_contributors = [
    # sre team entra object id,
    # gh runner service principal object id, etc
  ]
}

module "storage_account" {
  source = "../../"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  tags                = module.metadata.tags

  public_network_access_enabled = true
  replication_type              = "LRS"
  enable_large_file_share       = true

  access_list = {
    "my_ip" = data.http.my_ip.body
  }

  service_endpoints = {
    "iaas-outbound" = module.virtual_network.subnet["iaas-outbound"].id
  }

  smb_contributors = local.smb_contributors

  storage_share = [
    {
      name  = "otel"
      quota = "50"
      metadata = {
        "key1" = "value1"
        "key2" = "value2"
      }
    },
    {
      name  = "traefik"
      quota = "50"
      metadata = {
        "key3" = "value3"
        "key4" = "value4"
      }
    },
  ]
  share_file = {
    otel = {
      file_share_name   = "otel"
      storage_share_url = "https://${local.storage_account_name}.file.core.windows.net/otel"
      folder_path       = "./files/otel"
    },
    traefik = {
      file_share_name   = "traefik"
      storage_share_url = "https://${local.storage_account_name}.file.core.windows.net/traefik"
      folder_path       = "./files/traefik"
    },
  }
  depends_on = [module.resource_group, module.virtual_network]
}
