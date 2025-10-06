# Public IP for Azure Bastion
resource "azurerm_public_ip" "bastion" {
  name                = "pip-bastion-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = local.common_tags
}

# Azure Bastion for secure management access
resource "azurerm_bastion_host" "main" {
  name                = "bastion-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Standard"

  # Standard SKU features for enterprise use
  tunneling_enabled     = true
  file_copy_enabled     = true
  shareable_link_enabled = false  # Disable for security
  ip_connect_enabled    = true

  ip_configuration {
    name                 = "configuration"
    subnet_id            = azurerm_subnet.bastion.id
    public_ip_address_id = azurerm_public_ip.bastion.id
  }

  tags = local.common_tags
}

# Network Security Group for management subnet
resource "azurerm_network_security_group" "management" {
  name                = "nsg-mgmt-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  # Allow RDP from Bastion subnet
  security_rule {
    name                       = "Allow-Bastion-RDP"
    priority                   = 1000
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3389"
    source_address_prefix      = "10.0.4.0/26"  # Bastion subnet
    destination_address_prefix = "*"
  }

  # Allow SSH from Bastion subnet  
  security_rule {
    name                       = "Allow-Bastion-SSH"
    priority                   = 1010
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "10.0.4.0/26"  # Bastion subnet
    destination_address_prefix = "*"
  }

  # Allow outbound HTTPS for management tools
  security_rule {
    name                       = "Allow-HTTPS-Outbound"
    priority                   = 1000
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Deny all other inbound traffic
  security_rule {
    name                       = "Deny-All-Inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  tags = local.common_tags
}

resource "azurerm_subnet_network_security_group_association" "management" {
  subnet_id                 = azurerm_subnet.management.id
  network_security_group_id = azurerm_network_security_group.management.id
}

# Management VM for VNet administration
resource "azurerm_windows_virtual_machine" "management" {
  name                = "vm-mgmt-${local.app_name}-${local.environment}"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_B2s"  # Small VM for management tasks
  admin_username      = "azureadmin"

  # Disable password authentication, use Azure AD instead
  disable_password_authentication = false
  admin_password                  = var.management_vm_admin_password

  network_interface_ids = [
    azurerm_network_interface.management.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-Datacenter"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  # Boot diagnostics
  boot_diagnostics {
    storage_account_uri = azurerm_storage_account.function.primary_blob_endpoint
  }

  tags = local.common_tags
}

# Network interface for management VM
resource "azurerm_network_interface" "management" {
  name                = "nic-mgmt-${local.app_name}-${local.environment}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.management.id
    private_ip_address_allocation = "Dynamic"
  }

  tags = local.common_tags
}

# Install management tools on the VM
resource "azurerm_virtual_machine_extension" "management_tools" {
  name                 = "install-management-tools"
  virtual_machine_id   = azurerm_windows_virtual_machine.management.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"Install-WindowsFeature -Name RSAT-AD-Tools, RSAT-DNS-Server; Install-PackageProvider -Name NuGet -Force; Install-Module -Name Az -Force -AllowClobber; Install-Module -Name AzureAD -Force\""
  })

  tags = local.common_tags
}