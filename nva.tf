# ---------- NVA routing lab ----------
# A Linux network virtual appliance (NVA) that the Central US web subnet
# routes through. This is the hands-on version of the hub-spoke + NVA
# pattern: UDR -> IP forwarding -> NAT.
#
# Placement: the NVA lives in Central US, NOT in the East US hub.
# B2pts_v2 is restricted in East US / East US 2 on this subscription
# (NotAvailableForSubscription), and it is the only $0-size available,
# so the NVA runs in the Central US spoke in its own `nva` subnet.
# The mechanics are identical: the web subnet's default route points at
# the NVA's private IP, the NVA forwards and NATs.
#
# How it works:
# - vm-test-web (10.3.0.4, web subnet) has a UDR: 0.0.0.0/0 ->
#   VirtualAppliance 10.3.1.4 (the NVA).
# - The NVA's NIC has IP forwarding enabled, so Azure delivers the
#   packets to it. Cloud-init turns on net.ipv4.ip_forward and adds
#   iptables MASQUERADE + FORWARD rules (see nva-cloud-init.yaml).
# - The NVA's own subnet has no UDR, so its outbound uses Azure's
#   system default route to the internet.
#
# Cost: a second B2pts_v2. The 750 free hrs/mo are already used by
# vm-test-web, so a second one running 24/7 bills ~$0.00949/hr
# (~$6.93/mo, verified via Retail Prices API). The 64 GB P6 disk is
# free — it is the second of the 2 x 64 GB allowance. Deallocate the
# VM (`az vm deallocate -g rg-vnet-lab -n vm-nva`) to stop the compute
# meter; while it is off, the web subnet has no internet, because its
# default route still points at the NVA. Start it again with
# `az vm start -g rg-vnet-lab -n vm-nva`.
# NOTE: the B-family quota is 4 vCPUs in Central US; vm-test-web +
# vm-nva use all 4. A third B-series VM there needs a quota increase.
#
# Verify from vm-test-web (via `az vm run-command`):
#   ip route get 8.8.8.8        # should show via 10.3.1.4
#   ping -c 2 8.8.8.8           # proves forwarding works
#   curl -s -m 10 ifconfig.me  # proves NAT + internet works
# Verify on the NVA:
#   sysctl net.ipv4.ip_forward                       # 1
#   iptables -t nat -L POSTROUTING -n -v             # MASQUERADE counters climb

# Own subnet for the NVA inside the Central US spoke. No UDR here, so the
# NVA itself reaches the internet on Azure's system default route. No
# custom NSG: the default VNet rules already allow intra-VNet traffic.
resource "azurerm_subnet" "spoke_centralus_nva" {
  name                 = "nva"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke_centralus.name
  address_prefixes     = ["10.3.1.0/24"]
}

# IP forwarding is the critical flag: without it Azure never delivers
# packets destined for other hosts to this NIC.
resource "azurerm_network_interface" "nva" {
  name                  = "nic-nva"
  location              = local.centralus_location
  resource_group_name   = azurerm_resource_group.network.name
  ip_forwarding_enabled = true
  tags                  = var.tags

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.spoke_centralus_nva.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "nva" {
  name                            = "vm-nva"
  location                        = local.centralus_location
  resource_group_name             = azurerm_resource_group.network.name
  size                            = "Standard_B2pts_v2"
  admin_username                  = "azureuser"
  disable_password_authentication = true
  tags                            = var.tags

  network_interface_ids = [azurerm_network_interface.nva.id]

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

  # Cloud-init: IP forwarding + iptables NAT, applied at boot and on
  # every reboot via the nva-firewall systemd service.
  custom_data = base64encode(file("${path.module}/nva-cloud-init.yaml"))

  # Managed boot diagnostics (no storage account needed).
  boot_diagnostics {}
}

# Default route for the Central US web subnet: everything goes via the NVA.
resource "azurerm_route_table" "centralus_web" {
  name                = "rt-centralus-web"
  location            = local.centralus_location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  route {
    name                   = "default-via-nva"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = azurerm_network_interface.nva.private_ip_address
  }
}

resource "azurerm_subnet_route_table_association" "centralus_web" {
  subnet_id      = azurerm_subnet.spoke_centralus_web.id
  route_table_id = azurerm_route_table.centralus_web.id
}
