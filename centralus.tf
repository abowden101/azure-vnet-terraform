# ---------- Central US spoke + test VM ($0 config) ----------
# Why Central US: the free trial restricts B1s/B1ms/B2s and D2s_v3 in
# eastus AND eastus2 (NotAvailableForSubscription — a trial-offer block,
# not quota). A 2026-11-13 SKU scan found Standard_B2pts_v2 unrestricted
# in Central US. B2pts_v2 (2 vCPU / 1 GiB, ARM, burstable) is also in the
# 12-month free allowance (750 hrs/mo), so compute is $0.
#
# $0 config, line by line:
# - Compute: B2pts_v2, 750 free hrs/mo for 12 months -> $0.
# - Disk: 64 GB P6 Premium SSD (Premium_LRS + disk_size_gb 64) — the free
#   allowance covers 2 x 64 GB P6. The old 30 GB Standard SSD would bill
#   ~$2.40/mo, so it is NOT used here.
# - Public IP: NONE. Standard IPs are $0.005/hr (~$3.65/mo) whether
#   attached or not, and Basic SKU IPs were retired Sep 2025. Manage the
#   VM via serial console or `az vm run-command` (both free, no IP needed).
# - Network: VNet / subnet / NSG / peering are $0.
# - Total: $0/mo, and the $200 credit is not touched. After the credit
#   expires (Dec 12, 2026) the subscription must be upgraded to
#   pay-as-you-go to keep the free services — with this config there is
#   still nothing to bill. Set a budget alert after upgrading.
# - ARM64: B2pts_v2 is ARM, so the image is 22_04-lts-arm64.
# - 1 GiB RAM is tight — fine for a test box proving the deployment.
# NOTE: the East US 2 spoke (vm.tf) stays deployed and peered ($0); only
# its NIC + public IP were removed so the $3.65/mo IP meter stops.

locals {
  centralus_location = "centralus"
}

# Third spoke VNet in Central US, same shape as the East US 2 spoke
# (web tier only — this spoke exists to host the test VM).
resource "azurerm_virtual_network" "spoke_centralus" {
  name                = "vnet-spoke-centralus"
  location            = local.centralus_location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = ["10.3.0.0/16"]
  tags                = var.tags
}

resource "azurerm_subnet" "spoke_centralus_web" {
  name                 = "web"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke_centralus.name
  address_prefixes     = ["10.3.0.0/24"]
}

# Mirror of nsg-web (HTTP/HTTPS in). SSH is a separate conditional rule below.
resource "azurerm_network_security_group" "web_centralus" {
  name                = "nsg-web-centralus"
  location            = local.centralus_location
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

resource "azurerm_subnet_network_security_group_association" "web_centralus" {
  subnet_id                 = azurerm_subnet.spoke_centralus_web.id
  network_security_group_id = azurerm_network_security_group.web_centralus.id
}

# Global peering: East US hub <-> Central US spoke (both directions).
resource "azurerm_virtual_network_peering" "hub_to_spoke_centralus" {
  name                      = "hub-to-spoke-centralus"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.hub.name
  remote_virtual_network_id = azurerm_virtual_network.spoke_centralus.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "spoke_centralus_to_hub" {
  name                      = "spoke-centralus-to-hub"
  resource_group_name       = azurerm_resource_group.network.name
  virtual_network_name      = azurerm_virtual_network.spoke_centralus.name
  remote_virtual_network_id = azurerm_virtual_network.hub.id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# No public IP on purpose (see header comment). The NIC has a private
# address only; manage the VM via serial console or `az vm run-command`.
resource "azurerm_network_interface" "test_vm_centralus" {
  name                = "nic-test-vm-centralus"
  location            = local.centralus_location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke_centralus_web.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "test_vm" {
  name                            = "vm-test-web"
  location                        = local.centralus_location
  resource_group_name             = azurerm_resource_group.network.name
  size                            = "Standard_B2pts_v2"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  tags                            = var.tags

  network_interface_ids = [azurerm_network_interface.test_vm_centralus.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL0CLhd3qZNKrGFVZDBUpEWqGaE3VRw1HTxPwT1VlSZZ tonio-azure-lab"
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Premium_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-arm64"
    version   = "latest"
  }

  # Managed boot diagnostics (no storage account needed).
  boot_diagnostics {}
}

# SSH from the admin IP only. Not created while var.admin_source_ip is empty.
# (No public IP exists, so this rule has nothing to expose until one is added.)
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
  network_security_group_name = azurerm_network_security_group.web_centralus.name
}
