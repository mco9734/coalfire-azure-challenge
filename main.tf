
# Create Resource Group
resource "azurerm_resource_group" "rg" {
    name = "proof-of-concept-rg"
    location = var.resource_group_location

}

# NETWORK REQUIREMENTS

# 1 VNet - 10.0.0.0/16
resource "azurerm_virtual_network" "vnet" {
    name = "proof-of-concept-vnet"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    address_space = ["10.0.0.0/16"]
}

# 4 Subnets

# Application subnet
resource "azurerm_subnet" "application" {
    name = "application-subnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes = ["10.0.1.0/24"]
}

# Management subnet
resource "azurerm_subnet" "management" {
    name = "management-subnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes = ["10.0.2.0/24"]
    service_endpoints = ["Microsoft.Storage"]
}

# Backend subnet
resource "azurerm_subnet" "backend" {
    name = "backend-subnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes = ["10.0.3.0/24"]
}

# Web subnet
resource "azurerm_subnet" "web" {
    name = "web-subnet"
    resource_group_name = azurerm_resource_group.rg.name
    virtual_network_name = azurerm_virtual_network.vnet.name
    address_prefixes = ["10.0.4.0/24"]
}

# COMPUTE REQUIREMENTS

# 2 Virtual Machine in an availability set running RedHat in the web subnet

# Create the availability set
resource "azurerm_availability_set" "web_as" {
    name = "avset"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    platform_fault_domain_count = 2
    platform_update_domain_count = 2
    managed = true
}

# Create the two virtual machines
resource "azurerm_linux_virtual_machine" "web_vms" {
    count = 2
    name = "web${count.index}"
    location = azurerm_resource_group.rg.location
    availability_set_id = azurerm_availability_set.web_as.id
    resource_group_name = azurerm_resource_group.rg.name
    network_interface_ids = [azurerm_network_interface.web_nic[count.index].id]
    size = "Standard_DS1_v2"
    disable_password_authentication = false

    source_image_reference {
        publisher = "RedHat"
        offer = "RHEL"
        sku = "9_4"
        version = "latest"
    }

    os_disk {
        caching = "ReadWrite"
        storage_account_type = "Standard_LRS"
        name = "myosdisk${count.index}"
    }


    computer_name = "web${count.index}"
    admin_username = var.web_username
    admin_password = var.web_password
}

# Enable virtual machine extension to install Apache (httpd)
resource "azurerm_virtual_machine_extension" "apache_vm_extension" {
    count = 2
    name = "Apache"
    virtual_machine_id  = azurerm_linux_virtual_machine.web_vms[count.index].id
    publisher = "Microsoft.Azure.Extensions"
    type = "CustomScript"
    type_handler_version = "2.0"

    settings = <<SETTINGS
 {
  "commandToExecute": "sudo yum -y install httpd && sudo systemctl start httpd && sudo firewall-cmd --permanent --add-service=http && sudo firewalld"
 }
SETTINGS

}

# Add VMs to a network security group. NSG allows SSH from management VM, allows traffic from the Load Balancer. No external traffic
resource "azurerm_network_security_group" "web_nsg" {
    name = "web-nsg"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    security_rule {
        name = "allow-ssh-from-management"
        priority = 100
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = "22"
        source_address_prefix = azurerm_subnet.management.address_prefixes[0]
        destination_address_prefix = "*"
    }

    security_rule {
        name = "allow-lb-traffic"
        priority = 200
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = "80"
        source_address_prefix = "*"
        destination_address_prefix = "10.0.4.0/24"
    }
}

# Create a nic for the VMs
resource "azurerm_network_interface" "web_nic" {
    count = 2
    name = "web-nic-${count.index}"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    

    ip_configuration {
        name = "ipconfig${count.index}"
        subnet_id = azurerm_subnet.web.id
        private_ip_address_allocation = "Dynamic"
        primary = true
    }
}

# Associate nic with nsg
resource "azurerm_network_interface_security_group_association" "web_nic_nsg" {
    for_each = { for idx, nic in azurerm_network_interface.web_nic : idx => nic }
    network_interface_id = each.value.id
    network_security_group_id = azurerm_network_security_group.web_nsg.id
}

# 1 Virtual Machine running RedHat in the Management subnet

# Create the Virtual Machine
resource "azurerm_linux_virtual_machine" "management_vm" {
    name = "management-vm"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    network_interface_ids = [azurerm_network_interface.management_nic.id]
    size = "Standard_DS1_v2"
    disable_password_authentication = false

    os_disk {
        name = "myOsDisk"
        caching = "ReadWrite"
        storage_account_type = "Premium_LRS"
    }

    source_image_reference {
        publisher = "RedHat"
        offer = "RHEL"
        sku = "9_4"
        version = "latest"
    }

    computer_name = "management"
    admin_username = var.management_username
    admin_password = var.management_password

    boot_diagnostics {
        storage_account_uri = azurerm_storage_account.my_storage_account.primary_blob_endpoint
    }
}

# Create a public IP for use with SSH
resource "azurerm_public_ip" "management_public_ip" {
    name = "managementIP"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    allocation_method = "Static"
}

# NSG allows SSH from a specific IP only
resource "azurerm_network_security_group" "management_nsg" {
    name = "management-nsg"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    security_rule {
        name = "allow-ssh-specific-ip"
        priority = 100
        direction = "Inbound"
        access = "Allow"
        protocol = "Tcp"
        source_port_range = "*"
        destination_port_range = "22"
        source_address_prefix = var.management_ssh_ip
        destination_address_prefix = "*"
    }
}

# Creates a nic for the VM
resource "azurerm_network_interface" "management_nic" {
    name = "management-nic"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name

    ip_configuration {
        name = "management-nic-ipconfig"
        subnet_id = azurerm_subnet.management.id
        private_ip_address_allocation = "Dynamic"
        public_ip_address_id = azurerm_public_ip.management_public_ip.id
    }

}

# Associates nic with nsg
resource "azurerm_network_interface_security_group_association" "management_nic_nsg" {
    network_interface_id = azurerm_network_interface.management_nic.id
    network_security_group_id = azurerm_network_security_group.management_nsg.id
}

# OTHER

# One storage account, GRS only accessible to the VM in the Management subnet

# Generate random text for a unique storage account name
resource "random_id" "random_id" {
    keepers = {
        # Generate a new ID only when a new resource group is defined
        resource_group = azurerm_resource_group.rg.name
    }

    byte_length = 8
}

# Create storage account for boot diagnostics, allows for use of serial console in Azure portal for troubleshooting
resource "azurerm_storage_account" "my_storage_account" {
    name = "diag${random_id.random_id.hex}"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    account_tier = "Standard"
    account_replication_type = "GRS"

    network_rules {
        default_action = "Deny" # Deny all traffic by default
        virtual_network_subnet_ids = [azurerm_subnet.management.id] # Allow traffic only from a specific subnet
    }
}

# One Load balancer that sends traffic to the VM’s in the availability set

# Creates the load balancer
resource "azurerm_lb" "load_balancer" {
    name = "loadBalancer"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    sku = "Standard"

    frontend_ip_configuration {
        name = "publicIPAddress"
        public_ip_address_id = azurerm_public_ip.lb_public_ip.id
    }
}

# Assigns the load balancer an IP
resource "azurerm_public_ip" "lb_public_ip" {
    name = "lb-public-ip"
    location = azurerm_resource_group.rg.location
    resource_group_name = azurerm_resource_group.rg.name
    allocation_method = "Static"
    sku = "Standard"
}

# Creates an address pool for the lb
resource "azurerm_lb_backend_address_pool" "lb_address_pool" {
    loadbalancer_id = azurerm_lb.load_balancer.id
    name = "BackEndAddressPool"
}

# Creates an lb probe
resource "azurerm_lb_probe" "lb_probe" {
    loadbalancer_id = azurerm_lb.load_balancer.id
    name = "test-probe"
    port = 80
}

# Creates a rule for the lb
resource "azurerm_lb_rule" "lb_rule" {
    loadbalancer_id = azurerm_lb.load_balancer.id
    name = "lb-rule"
    protocol = "Tcp"
    frontend_port = 80
    backend_port = 80
    disable_outbound_snat = true
    frontend_ip_configuration_name = "publicIPAddress"
    probe_id = azurerm_lb_probe.lb_probe.id
    backend_address_pool_ids = [azurerm_lb_backend_address_pool.lb_address_pool.id]
}

# Creates an outbound rule for the lb
resource "azurerm_lb_outbound_rule" "lboutbound_rule" {
    name = "test-outbound"
    loadbalancer_id = azurerm_lb.load_balancer.id
    protocol = "Tcp"
    backend_address_pool_id = azurerm_lb_backend_address_pool.lb_address_pool.id

    frontend_ip_configuration {
        name = "publicIPAddress"
    }
}

# Associate Network Interface to the Backend Pool of the Load Balancer
resource "azurerm_network_interface_backend_address_pool_association" "my_nic_lb_pool" {
    count = 2
    network_interface_id = azurerm_network_interface.web_nic[count.index].id
    ip_configuration_name = "ipconfig${count.index}"
    backend_address_pool_id = azurerm_lb_backend_address_pool.lb_address_pool.id
}
