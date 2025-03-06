terraform {
    required_providers {
        azurerm = {
        source  = "hashicorp/azurerm"
        version = ">=3.0.0"
        }
    }
}

provider "azurerm" {
    features {}
    subscription_id = "5eae0f3c-efbr7y-4cdf63-abc08-7b3b4b5b5b5b"
  
}

variable "prefix" {
  default = "ospk-app-dev"
}

resource "azurerm_resource_group" "ospk_rg" {
  name     = "${var.prefix}-rg"
  location = "East US"
}

resource "azurerm_virtual_network" "ospk_vnet" {
  name                = "${var.prefix}-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.ospk_rg.location
  resource_group_name = azurerm_resource_group.ospk_rg.name
}

resource "azurerm_subnet" "ospk_vm_subnet" {
  name                 = "${var.prefix}-vm-subnet"
  resource_group_name  = azurerm_resource_group.ospk_rg.name
  virtual_network_name = azurerm_virtual_network.ospk_vnet.name
  address_prefixes     = ["10.1.2.0/24"]
}

resource "azurerm_subnet" "ospk_aks_subnet" {
  name                 = "${var.prefix}-aks-subnet"
  resource_group_name  = azurerm_resource_group.ospk_rg.name
  virtual_network_name = azurerm_virtual_network.ospk_vnet.name
  address_prefixes     = ["10.1.3.0/24"]
}

resource "azurerm_public_ip" "ospk_vm_public_ip" {
  name                = "${var.prefix}-public-ip"
  location            = azurerm_resource_group.ospk_rg.location
  resource_group_name = azurerm_resource_group.ospk_rg.name
  allocation_method   = "Static"
  
}

# Network Security Group (NSG) for VM
resource "azurerm_network_security_group" "ospk_vm_nsg" {
  name                = "${var.prefix}-vm-nsg"
  location            = azurerm_resource_group.ospk_rg.location
  resource_group_name = azurerm_resource_group.ospk_rg.name
}

# SSH Inbound Rule (Port 22)
resource "azurerm_network_security_rule" "ssh_rule" {
  name                        = "Allow-SSH"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.ospk_rg.name
  network_security_group_name = azurerm_network_security_group.ospk_vm_nsg.name
}

resource "azurerm_network_interface" "ospk_vm_nic" {
  name                = "${var.prefix}-nic"
  location            = azurerm_resource_group.ospk_rg.location
  resource_group_name = azurerm_resource_group.ospk_rg.name

  ip_configuration {
    name                          = "ospk-vm-nic-config"
    subnet_id                     = azurerm_subnet.ospk_vm_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ospk_vm_public_ip.id
  }
}

# Associate NSG with VM Subnet
resource "azurerm_subnet_network_security_group_association" "ospk_vm_nsg_assoc" {
  subnet_id                 = azurerm_subnet.ospk_vm_subnet.id
  network_security_group_id = azurerm_network_security_group.ospk_vm_nsg.id
}

resource "azurerm_virtual_machine" "ospk_vm" {
  name                  = "${var.prefix}-vm"
  location              = azurerm_resource_group.ospk_rg.location
  resource_group_name   = azurerm_resource_group.ospk_rg.name
  network_interface_ids = [azurerm_network_interface.ospk_vm_nic.id]
  vm_size               = "Standard_DS1_v2"

  # Uncomment this line to delete the OS disk automatically when deleting the VM
  # delete_os_disk_on_termination = true

  # Uncomment this line to delete the data disks automatically when deleting the VM
  # delete_data_disks_on_termination = true


  storage_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }
  storage_os_disk {
    name              = "ospkAppDevDisk"
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }
  os_profile {
    computer_name  = "${var.prefix}-vm"
    admin_username = "ubuntu"
  }

  os_profile_linux_config {
    disable_password_authentication = true
    ssh_keys {
      path     = "/home/ubuntu/.ssh/authorized_keys"
      key_data = file("~/.ssh/id_rsa.pub")
    }
  }
  tags = {
    environment = "Development"
  }
}

resource "azurerm_kubernetes_cluster" "ospk_aks" {
  name                = "${var.prefix}-aks"
  location            = azurerm_resource_group.ospk_rg.location
  resource_group_name = azurerm_resource_group.ospk_rg.name
  dns_prefix          = "ospkaks"

  default_node_pool {
    name           = "agentpool"
    node_count     = 1
    vm_size        = "Standard_D2_v2"
    vnet_subnet_id = azurerm_subnet.ospk_aks_subnet.id
  }

  network_profile {
    network_plugin     = "azure"
    network_policy     = "azure"
    service_cidr       = "10.1.4.0/24"
    dns_service_ip     = "10.1.4.10"
    outbound_type      = "loadBalancer"
  }

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = "Development"
  }
}

output "aks_cluster_name" {
  value = azurerm_kubernetes_cluster.ospk_aks.name
}

output "kube_config" {
  value     = azurerm_kubernetes_cluster.ospk_aks.kube_config_raw
  sensitive = true
}

# Output Public IP
output "ospk_vm_pip" {
  value = azurerm_public_ip.ospk_vm_public_ip.ip_address
}

# Output Public IP
output "ospk_vm_name" {
  value = azurerm_virtual_machine.ospk_vm.name
}
