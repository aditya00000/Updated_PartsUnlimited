terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.22.0"
    }
  }
  backend "azurerm" {
    resource_group_name  = "SA-TF-BACKENDS"
    storage_account_name = "azb23tfremotebackends"
    container_name       = "tfremotebackends"
    key                  = "dev.terraform.tfstate"
  }
}

provider "azurerm" {
  # Configuration options
  features {

  }
}

module "create-rg-01" {
  source = "./modules/rg"
  rg_name = var.rg_01_name
  rg_location = var.rg_01_location
  tag_env_name = var.tag_env_name
}


resource "azurerm_virtual_network" "vnet-01" {
  name                = var.vnet_01_name
  location            = var.rg_01_location
  resource_group_name = var.rg_01_name
  address_space       = var.vnet_01_address_space
  depends_on = [
    module.create-rg-01
  ]

  subnet {
    name           = var.subnet1_name
    address_prefix = var.subnet1_address_prefix
  }

  subnet {
    name           = var.subnet2_name
    address_prefix = var.subnet2_address_prefix
  }

  tags = {
    automation  = "terraform"
    environment = var.tag_env_name
  }
}

data "azurerm_key_vault" "kv-01" {
  name                = "kv-azb23-dev"
  resource_group_name = "SA-TF-BACKENDS"
}

data "azurerm_key_vault_secret" "kv-01-sec-01" {
  name         = "db-pwd"
  key_vault_id = data.azurerm_key_vault.kv-01.id
}

data "azurerm_key_vault_secret" "kv-01-sec-02" {
  name         = "azb23-db-01"
  key_vault_id = data.azurerm_key_vault.kv-01.id
}

resource "azurerm_sql_server" "sql-server-01" {
  name                         = "azb23-sql-server-01"
  resource_group_name = var.rg_01_name
  location            = var.rg_01_location
  version                      = "12.0"
  administrator_login          = "vineel"
  administrator_login_password = data.azurerm_key_vault_secret.kv-01-sec-01.value
  depends_on = [
    module.create-rg-01
  ]
 tags = {
    automation  = "terraform"
    environment = var.tag_env_name
  }
}

resource "azurerm_sql_database" "sql-db-01" {
  name                = "azb23-db-01"
  resource_group_name = var.rg_01_name
  location            = var.rg_01_location
  server_name         = azurerm_sql_server.sql-server-01.name
  depends_on = [
    module.create-rg-01,
    resource.azurerm_sql_server.sql-server-01
  ]
  tags = {
    automation  = "terraform"
    environment = var.tag_env_name
  }
}

resource "azurerm_service_plan" "asp-01" {
  name                = "asp-webapps-01"
  resource_group_name = var.rg_01_name
  location            = var.rg_01_location
  sku_name            = "P1v2"
  os_type             = "Windows"
  depends_on = [
    module.create-rg-01,
    resource.azurerm_sql_database.sql-db-01
  ]
}

resource "azurerm_windows_web_app" "app-01" {
  name                = "azb23-win-app-01"
  resource_group_name = var.rg_01_name
  location            = var.rg_01_location
  service_plan_id     = azurerm_service_plan.asp-01.id
  depends_on = [
    module.create-rg-01,
    resource.azurerm_service_plan.asp-01
  ]

  site_config {}
  
  connection_string {
    name  = "from-kv"
    type  = "SQLServer"
    value = data.azurerm_key_vault_secret.kv-01-sec-02.value
  }
}