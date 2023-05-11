terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "dev-dap-rg" {
  name     = "dev-dap-devops-001"
  location = "West US 2"
}

resource "azurerm_storage_account" "dev-dap-sa" {
  name                     = "dev-dap-devops-iot-storage"
  resource_group_name      = azurerm_resource_group.dev-dap-rg.name
  location                 = azurerm_resource_group.dev-dap-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

resource "azurerm_storage_container" "dev-dap-sc" {
  name                  = "dev-dap-iot"
  storage_account_name  = azurerm_storage_account.dev-dap-sa.name
  container_access_type = "private"
}

resource "azurerm_eventhub_namespace" "eventhub-namespace" {
  name                = "dev-dap-iot-namespace"
  resource_group_name = azurerm_resource_group.dev-dap-rg.name
  location            = azurerm_resource_group.dev-dap-rg.location
  sku                 = "Basic"
}

resource "azurerm_eventhub" "dev-dap-eventhub" {
  name                = "dev-dap-eventhub"
  resource_group_name = azurerm_resource_group.dev-dap-rg.name
  namespace_name      = azurerm_eventhub_namespace.eventhub-namespace.name
  partition_count     = 2
  message_retention   = 1
}

resource "azurerm_eventhub_authorization_rule" "dev-dap-auth-rule" {
  resource_group_name = azurerm_resource_group.dev-dap-rg.name
  namespace_name      = azurerm_eventhub_namespace.eventhub-namespace.name
  eventhub_name       = azurerm_eventhub.dev-dap-eventhub.name
  name                = "acctest"
  send                = true
}

resource "azurerm_iothub" "iothub" {
  name                = "dev-dap-IoTHub"
  resource_group_name = azurerm_resource_group.dev-dap-rg.name
  location            = azurerm_resource_group.dev-dap-rg.location

  sku {
    name     = "S1"
    capacity = "1"
  }

  endpoint {
    type                       = "AzureIotHub.StorageContainer"
    connection_string          = azurerm_storage_account.dev-dap-sa.primary_blob_connection_string
    name                       = "export"
    batch_frequency_in_seconds = 60
    max_chunk_size_in_bytes    = 10485760
    container_name             = azurerm_storage_container.dev-dap-sc.name
    encoding                   = "Avro"
    file_name_format           = "{iothub}/{partition}_{YYYY}_{MM}_{DD}_{HH}_{mm}"
  }

  endpoint {
    type              = "AzureIotHub.EventHub"
    connection_string = azurerm_eventhub_authorization_rule.dev-dap-auth-rule.primary_connection_string
    name              = "export2"
  }

  route {
    name           = "export"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["export"]
    enabled        = true
  }

  route {
    name           = "export2"
    source         = "DeviceMessages"
    condition      = "true"
    endpoint_names = ["export2"]
    enabled        = true
  }

  enrichment {
    key            = "tenant"
    value          = "$twin.tags.Tenant"
    endpoint_names = ["export", "export2"]
  }

  cloud_to_device {
    max_delivery_count = 30
    default_ttl        = "PT1H"
    feedback {
      time_to_live       = "PT1H10M"
      max_delivery_count = 15
      lock_duration      = "PT30S"
    }
  }

  tags = {
    purpose = "testing"
  }
}