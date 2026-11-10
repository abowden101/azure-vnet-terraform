variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the resource group that holds the network."
  type        = string
  default     = "rg-vnet-lab"
}

variable "hub_address_space" {
  description = "Address space for the hub VNet."
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "spoke_address_space" {
  description = "Address space for the spoke VNet."
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "hub_subnets" {
  description = "Hub subnets: name => CIDR. GatewaySubnet and AzureFirewallSubnet are reserved names Azure requires."
  type        = map(string)
  default = {
    GatewaySubnet       = "10.0.0.0/24"
    AzureFirewallSubnet = "10.0.1.0/24"
    SharedServices      = "10.0.2.0/24"
  }
}

variable "spoke_subnets" {
  description = "Spoke subnets: name => CIDR."
  type        = map(string)
  default = {
    web  = "10.1.0.0/24"
    app  = "10.1.1.0/24"
    data = "10.1.2.0/24"
  }
}

variable "admin_source_ip" {
  description = "Your public IP as a /32 CIDR (e.g. 203.0.113.10/32) allowed to reach the SharedServices subnet for admin access. Leave empty to skip the admin rule."
  type        = string
  default     = ""
}

variable "enable_nat_gateway" {
  description = "Create a NAT Gateway for the spoke subnets (adds roughly $32/mo). Default false."
  type        = bool
  default     = false
}

variable "firewall_private_ip" {
  description = "Private IP of a hub firewall/NVA (e.g. 10.0.1.4). When set, spoke subnets get a 0.0.0.0/0 route via it. Leave empty (default) — the firewall itself is not deployed by this project."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default = {
    project     = "azure-vnet-terraform"
    environment = "lab"
    owner       = "antonio-bowden"
  }
}
