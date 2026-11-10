# ---------- Subnets ----------

resource "azurerm_subnet" "hub" {
  for_each = var.hub_subnets

  name                 = each.key
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [each.value]
}

resource "azurerm_subnet" "spoke" {
  for_each = var.spoke_subnets

  name                 = each.key
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.spoke.name
  address_prefixes     = [each.value]
}

# ---------- Network security groups ----------
# Tiered rules: each tier only accepts traffic from the tier in front of it.

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = azurerm_resource_group.network.location
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

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-From-Web"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = var.spoke_subnets["web"]
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "data" {
  name                = "nsg-data"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  security_rule {
    name                       = "Allow-SQL-From-App"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "1433"
    source_address_prefix      = var.spoke_subnets["app"]
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Allow-Postgres-From-App"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "5432"
    source_address_prefix      = var.spoke_subnets["app"]
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "shared" {
  name                = "nsg-shared"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  # Admin access only from a single source IP. No rule is created when
  # var.admin_source_ip is empty, so the subnet stays closed by default.
  dynamic "security_rule" {
    for_each = var.admin_source_ip != "" ? [var.admin_source_ip] : []
    content {
      name                       = "Allow-Admin-SSH-RDP"
      priority                   = 100
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_ranges    = ["22", "3389"]
      source_address_prefix      = security_rule.value
      destination_address_prefix = "*"
    }
  }
}

# ---------- NSG associations ----------

resource "azurerm_subnet_network_security_group_association" "web" {
  subnet_id                 = azurerm_subnet.spoke["web"].id
  network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.spoke["app"].id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  subnet_id                 = azurerm_subnet.spoke["data"].id
  network_security_group_id = azurerm_network_security_group.data.id
}

resource "azurerm_subnet_network_security_group_association" "shared" {
  subnet_id                 = azurerm_subnet.hub["SharedServices"].id
  network_security_group_id = azurerm_network_security_group.shared.id
}

# ---------- Route table: spoke egress via the hub firewall ----------
# The firewall itself is not deployed by this project (an Azure Firewall
# alone is roughly $1,000/mo). The table exists so the path is ready: set
# var.firewall_private_ip and spoke traffic gets a 0.0.0.0/0 route via it.

resource "azurerm_route_table" "spoke" {
  name                = "rt-spoke"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = var.tags

  dynamic "route" {
    for_each = var.firewall_private_ip != "" ? [var.firewall_private_ip] : []
    content {
      name                   = "default-via-firewall"
      address_prefix         = "0.0.0.0/0"
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = route.value
    }
  }
}

resource "azurerm_subnet_route_table_association" "web" {
  subnet_id      = azurerm_subnet.spoke["web"].id
  route_table_id = azurerm_route_table.spoke.id
}

resource "azurerm_subnet_route_table_association" "app" {
  subnet_id      = azurerm_subnet.spoke["app"].id
  route_table_id = azurerm_route_table.spoke.id
}

resource "azurerm_subnet_route_table_association" "data" {
  subnet_id      = azurerm_subnet.spoke["data"].id
  route_table_id = azurerm_route_table.spoke.id
}

# ---------- Optional NAT Gateway ----------
# Off by default. Enable with var.enable_nat_gateway for outbound-only
# internet from the spoke subnets without public IPs on the VMs.

resource "azurerm_public_ip" "nat" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "pip-nat-spoke"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway" "spoke" {
  count               = var.enable_nat_gateway ? 1 : 0
  name                = "nat-spoke"
  location            = azurerm_resource_group.network.location
  resource_group_name = azurerm_resource_group.network.name
  sku_name            = "Standard"
  tags                = var.tags
}

resource "azurerm_nat_gateway_public_ip_association" "spoke" {
  count                = var.enable_nat_gateway ? 1 : 0
  nat_gateway_id       = azurerm_nat_gateway.spoke[0].id
  public_ip_address_id = azurerm_public_ip.nat[0].id
}

resource "azurerm_subnet_nat_gateway_association" "spoke" {
  for_each = var.enable_nat_gateway ? var.spoke_subnets : {}

  subnet_id      = azurerm_subnet.spoke[each.key].id
  nat_gateway_id = azurerm_nat_gateway.spoke[0].id
}
