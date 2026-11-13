# ---------- East US 2 spoke (network only) ----------
# East US had NO capacity for any free-tier size on 2026-11-12
# (Standard_B1s / B1ms / B2s all SkuNotAvailable, regional + zones 1/2/3).
# East US 2 is the same story (B1s/B1ms/B2s regional + B1s zone 1 all
# SkuNotAvailable on 2026-11-13 ~00:10 ET). Root cause, pinned 2026-11-13
# ~2:15 PM ET: NotAvailableForSubscription — a free-trial offer block,
# not quota (B-family quota is 4 vCPUs, 0 used) and not busy capacity.
# Retrying the same sizes will not fix it.
#
# The East US 2 spoke below IS deployed and peered to the hub ($0) and
# stays. The test VM moved to Central US (see centralus.tf): B2pts_v2,
# ARM64, 64 GB P6 disk, NO public IP — the $0 config. The East US 2 NIC
# + public IP (pip-test-vm, 52.251.40.163) were removed with that move so
# the $3.65/mo IP meter stops; `terraform apply` destroys them.

locals {
  use2_location = "eastus2"
}

# Second spoke VNet in East US 2, same shape as the East US spoke (web tier
# only — this spoke exists to host the test VM).
resource "azurerm_virtual_network" "spoke_use2" {
  name                = "vnet-spoke-use2"
  location            = local.use2_location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = ["10.2.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke_use2_web" {
  name                 = "web"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke_use2.name
  address_prefixes     = ["10.2.0.0/24"]
}

# Mirror of nsg-web (HTTP/HTTPS in). SSH is a separate conditional rule below.
resource "azurerm_network_security_group" "web_use2" {
  name                = "nsg-web-use2"
  location            = local.use2_location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-HTTP"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "web_use2" {
  subnet_id                 = azurerm_subnet.spoke_use2_web.id
  network_security_group_id = azurerm_network_security_group.web_use2.id
}

# Global peering: East US hub <-> East US 2 spoke (both directions).
resource "azurerm_virtual_network_peering" "hub_to_spoke_use2" {
  name                      = "hub-to-spoke-use2"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke_use2.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_use2_to_hub" {
  name                      = "spoke-use2-to-hub"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.spoke_use2.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# (Test VM moved to Central US — see centralus.tf. The East US 2 NIC +
# public IP were deleted with that move; `terraform apply` destroys them.)
