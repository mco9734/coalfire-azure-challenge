output "management_ip_address" {
    value = azurerm_linux_virtual_machine.management_vm.public_ip_address
}

output "lb_public_ip_address" {
  value = "http://${azurerm_public_ip.lb_public_ip.ip_address}"
}