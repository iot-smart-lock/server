# Specify the provider and version
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=2.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Create a Resource Group
resource "azurerm_resource_group" "myweb" {
  name     = "${var.prefix}-rg"
  location = var.region
  tags = {
        Site = "${var.prefix}.com"
    }
}

# Create a DNS Zone
resource "azurerm_dns_zone" "myweb" {
  name                = "${var.prefix}.com"
  resource_group_name = azurerm_resource_group.myweb.name
  tags = {
        Site = "${var.prefix}.com"
    }
}

# Create a Virtual Network
resource "azurerm_virtual_network" "myweb" {
  name                = "${var.prefix}-net"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.myweb.location
  resource_group_name = azurerm_resource_group.myweb.name

  tags = {
        Site = "${var.prefix}.com"
    }
}

# Add a Subnet
resource "azurerm_subnet" "internal" {
  name                 = "internal"
  resource_group_name  = azurerm_resource_group.myweb.name
  virtual_network_name = azurerm_virtual_network.myweb.name
  address_prefixes       = ["10.0.1.0/24"]
}

# Allocate a Static Public IP
resource "azurerm_public_ip" "external" {
  name                = "external"
  location            = var.region
  resource_group_name = azurerm_resource_group.myweb.name
  allocation_method   = "Static"

  tags = {
        Site = "${var.prefix}.com"
    }
}

# Create a Network Security Group and allow inbound port(s)
resource "azurerm_network_security_group" "myweb" {
  name                = "${var.prefix}-nsg"
  location            = var.region
  resource_group_name = azurerm_resource_group.myweb.name

  security_rule {
        name                       = "SSH"
        priority                   = 1001
        direction                  = "Inbound"
        access                     = "Allow"
        protocol                   = "Tcp"
        source_port_range          = "*"
        destination_port_range     = "22"
        source_address_prefix      = "*"
        destination_address_prefix = "*"
    }

    security_rule {
      name                       = "HTTP"
      priority                   = 1002
      direction                  = "Inbound"
      access                     = "Allow"
      protocol                   = "Tcp"
      source_port_range          = "*"
      destination_port_range     = "1880"
      source_address_prefix      = "*"
      destination_address_prefix = "*"
    }

  tags = {
        Site = "${var.prefix}.com"
    }
}

# Create a Network Interface with a Dynamic Private IP
resource "azurerm_network_interface" "myweb" {
  name                      = "${var.prefix}-nic"
  location                  = azurerm_resource_group.myweb.location
  resource_group_name       = azurerm_resource_group.myweb.name

  ip_configuration {
       name                          = "${var.prefix}-nic_conf"
       subnet_id                     = azurerm_subnet.internal.id
       private_ip_address_allocation = "Dynamic"
       public_ip_address_id          = azurerm_public_ip.external.id
    }

  tags = {
        Site = "${var.prefix}.com"
    }
}

# Create an Ubuntu Virtual Machine with key based access and run a script on boot; use a Standard SSD
resource "azurerm_virtual_machine" "myweb" {
  name                  = "${var.prefix}-vm"
  location              = azurerm_resource_group.myweb.location
  resource_group_name   = azurerm_resource_group.myweb.name
  network_interface_ids = [azurerm_network_interface.myweb.id]
  vm_size               = "Standard_A1_v2"

  storage_image_reference {
      publisher = "Canonical"
      offer     = "UbuntuServer"
      sku       = "18.04-LTS"
      version   = "latest"
    }

  storage_os_disk {
      name              = "${var.prefix}-disk"
      caching           = "ReadWrite"
      create_option     = "FromImage"
      managed_disk_type = "StandardSSD_LRS"
    }

  os_profile {
      computer_name  = var.prefix
      admin_username = "ubuntu"
      admin_password = "ubuntu"
    }

  os_profile_linux_config {
        disable_password_authentication = true
        ssh_keys {
            path     = "/home/ubuntu/.ssh/authorized_keys"
            key_data = file("/.ssh/${var.prefix}.pub")
          }
    }

  tags = {
        Site = "${var.prefix}.com"
    }

  provisioner "remote-exec" {
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("C:/Users/maxim/.ssh/LanguageDetection/id_rsa")
      host        = azurerm_public_ip.external.ip_address
    }

    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg",
      "echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io",
      "git clone https://github.com/iot-smart-lock/server.git",
      "cd server",
      "sudo docker build .",
      "sudo docker compose up",
    ]
  }
}

output "public_ip_address" {
  value = azurerm_public_ip.external.ip_address
}
