terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.53.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "=2.3.0"
    }
  }
  required_version = ">=0.14.8"
}

provider "azurerm" {
  features {}
}

data "http" "my_ip" {
  url = "http://ipv4.icanhazip.com"
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

  project         = "drok"
  location            = "usgovvirginia"
  environment         = "dev"
  business_unit       = "infra"
  subscription_id     = module.subscription.output.subscription_id
  poc                 = "Darrell Haines"
  // resource_group_type = "app"

  // additional_tags = {
  //   "support_email" = "support@contoso.com"
  //   "owner"         = "Jon Doe"
  // }
}

module "resource_group" {
  source = "github.com/Azure-Terraform/terraform-azurerm-resource-group.git?ref=v1.0.0"

  location = module.metadata.location
  names    = module.metadata.names
  tags     = module.metadata.tags
}

module "virtual_network" {
  source = "github.com/Azure-Terraform/terraform-azurerm-virtual-network.git?ref=v2.6.0"

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

module "storage_account" {
  source = "../../"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  names               = module.metadata.names
  tags                = module.metadata.tags

  account_kind             = "FileStorage"
  replication_type         = "LRS"
  account_tier             = "Premium"
  access_tier              = "Hot"
  enable_large_file_share  = true

  access_list = {
    "my_ip" = chomp(data.http.my_ip.body)
  }

  service_endpoints = {
    "iaas-outbound" = module.virtual_network.subnet["iaas-outbound"].id
  }
}