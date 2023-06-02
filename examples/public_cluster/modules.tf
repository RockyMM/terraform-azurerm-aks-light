module "azure_region" {
  source  = "claranet/regions/azurerm"
  version = "x.x.x"

  azure_region = var.azure_region
}

module "rg" {
  source  = "claranet/rg/azurerm"
  version = "x.x.x"

  location    = module.azure_region.location
  client_name = var.client_name
  environment = var.environment
  stack       = var.stack
}

module "azure_virtual_network" {
  source  = "claranet/vnet/azurerm"
  version = "x.x.x"

  environment    = var.environment
  location       = module.azure_region.location
  location_short = module.azure_region.location_short
  client_name    = var.client_name
  stack          = var.stack

  resource_group_name = module.rg.resource_group_name

  vnet_cidr = ["10.0.0.0/19"]
}

module "node_network_subnet" {
  source  = "claranet/subnet/azurerm"
  version = "x.x.x"

  environment    = var.environment
  location_short = module.azure_region.location_short
  client_name    = var.client_name
  stack          = var.stack

  resource_group_name  = module.rg.resource_group_name
  virtual_network_name = module.azure_virtual_network.virtual_network_name

  name_suffix = "nodes"

  subnet_cidr_list = ["10.0.0.0/20"]

  service_endpoints = ["Microsoft.Storage"]
}

module "appgw_network_subnet" {
  source  = "claranet/subnet/azurerm"
  version = "x.x.x"

  environment    = var.environment
  location_short = module.azure_region.location_short
  client_name    = var.client_name
  stack          = var.stack

  resource_group_name  = module.rg.resource_group_name
  virtual_network_name = module.azure_virtual_network.virtual_network_name

  name_suffix = "appgw"

  subnet_cidr_list = ["10.0.20.0/24"]
}

module "global_run" {
  source  = "claranet/run/azurerm"
  version = "x.x.x"

  client_name    = var.client_name
  location       = module.azure_region.location
  location_short = module.azure_region.location_short
  environment    = var.environment
  stack          = var.stack

  monitoring_function_splunk_token = var.monitoring_function_splunk_token

  resource_group_name = module.rg.resource_group_name

  tenant_id = var.azure_tenant_id
}

resource "tls_private_key" "key" {
  algorithm = "RSA"
}

module "aks" {
  #source  = "claranet/aks-light/azurerm"
  #version = "x.x.x"
  source = "git@git.fr.clara.net:claranet/projects/cloud/azure/terraform/modules/aks-light.git?ref=AZ-1027-init--module"

  providers = {
    kubernetes = kubernetes.aks-module
  }

  client_name = var.client_name
  environment = var.environment
  stack       = var.stack

  resource_group_name = module.rg.resource_group_name
  location            = module.azure_region.location
  location_short      = module.azure_region.location_short

  private_cluster_enabled = false
  service_cidr            = "10.0.16.0/22"
  kubernetes_version      = "1.25.5"

  nodes_subnet_id = module.node_network_subnet.subnet_id
  nodes_pools = [
    {
      name            = "pool1"
      count           = 1
      vm_size         = "Standard_D1_v2"
      os_type         = "Linux"
      os_disk_type    = "Ephemeral"
      os_disk_size_gb = 30
      vnet_subnet_id  = module.node_network_subnet.subnet_id
    },
    {
      name                = "bigpool1"
      count               = 3
      vm_size             = "Standard_F8s_v2"
      os_type             = "Linux"
      os_disk_size_gb     = 30
      vnet_subnet_id      = module.node_network_subnet.subnet_id
      enable_auto_scaling = true
      min_count           = 3
      max_count           = 9
    }
  ]

  linux_profile = {
    username = "nodeadmin"
    ssh_key  = tls_private_key.key.public_key_openssh
  }

  oms_log_analytics_workspace_id = module.global_run.log_analytics_workspace_id
  azure_policy_enabled           = false

  logs_destinations_ids = [module.global_run.log_analytics_workspace_id]

  container_registries_id = [module.acr.acr_id]
}

module "acr" {
  source  = "claranet/acr/azurerm"
  version = "x.x.x"

  location            = module.azure_region.location
  location_short      = module.azure_region.location_short
  resource_group_name = module.rg.resource_group_name
  sku                 = "Standard"

  client_name = var.client_name
  environment = var.environment
  stack       = var.stack

  logs_destinations_ids = [module.global_run.log_analytics_workspace_id]
}
