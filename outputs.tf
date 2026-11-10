output "resource_group_name" {
  description = "Name of the resource group holding the network."
  value       = azurerm_resource_group.network.name
}

output "hub_vnet_id" {
  description = "Resource ID of the hub VNet."
  value       = azurerm_virtual_network.hub.id
}

output "spoke_vnet_id" {
  description = "Resource ID of the spoke VNet."
  value       = azurerm_virtual_network.spoke.id
}

output "hub_subnets" {
  description = "Hub subnet names mapped to their resource IDs."
  value       = { for k, s in azurerm_subnet.hub : k => s.id }
}

output "spoke_subnets" {
  description = "Spoke subnet names mapped to their resource IDs."
  value       = { for k, s in azurerm_subnet.spoke : k => s.id }
}

output "spoke_nsg_ids" {
  description = "Spoke NSG names mapped to their resource IDs."
  value = {
    web  = azurerm_network_security_group.web.id
    app  = azurerm_network_security_group.app.id
    data = azurerm_network_security_group.data.id
  }
}
