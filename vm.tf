# ---------- East US 2 spoke + test VM ----------
# East US had NO capacity for any free-tier size on 2026-11-12
# (Standard_B1s / B1ms / B2s all SkuNotAvailable, regional + zones 1/2/3).
# East US 2 is the same story (B1s/B1ms/B2s regional + B1s zone 1 all
# SkuNotAvailable on 2026-11-13 ~00:10 ET) — looks like a free-subscription
# capacity restriction, not a regional blip. The East US 2 spoke below IS
# deployed and peered to the hub; only the VM itself is missing. Retry the
# apply later, or try another region / a paid size.
#
# Standard_B1s Ubuntu 22.04 LTS. List price is ~$7.60/mo, but the Azure
# free account includes 750 B1s hours/month for 12 months, so the VM itself
# is $0 while that lasts. The public IP is the only real cost: Standard
# static at $0.005/hr (~$3.65/mo, verified via Azure Retail Prices API) —
# Basic SKU IPs were retired Sep 2025 and can no longer be created.
# Covered by the $200 credit until it expires Dec 12, 2026; after that the
# IP needs pay-as-you-go or it gets disabled.
# SSH (22) is NOT open: the rule below is only created when
# var.admin_source_ip is set (currently empty). Until then, reach the VM
# via serial console or `az vm run-command`.
# NOTE: the East US NIC + public IP from the failed first attempt are gone
# — this file replaced them, so `terraform apply` destroys them.

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

resource "azurerm_public_ip" "test_vm" {
  name                = "pip-test-vm"
  location            = local.use2_location
  resource_group_name = azurerm_resource_group.network.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "test_vm" {
  name                = "nic-test-vm"
  location            = local.use2_location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke_use2_web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.test_vm.id
  }
}

resource "azurerm_linux_virtual_machine" "test_vm" {
  name                            = "vm-test-web"
  location                        = local.use2_location
  resource_group_name             = azurerm_resource_group.network.name
  size                            = "Standard_B1s"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  tags                            = var.tags

  network_interface_ids = [azurerm_network_interface.test_vm.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0CLhd3qZNKrGFVZDBUpEWqGaE3VRw1HTxPwT1VlSZZ tonio-azure-lab"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 30
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Managed boot diagnostics (no storage account needed).
  boot_diagnostics {}
}

# SSH from the admin IP only. Not created while var.admin_source_ip is empty.
resource "azurerm_network_security_rule" "ssh_admin" {
  count                       = var.admin_source_ip != "" ? 1 : 0
  name                        = "Allow-SSH-Admin"
  priority                    = 120
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.admin_source_ip
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.network.name
  network_security_group_name = azurerm_network_security_group.web_use2.name
}
