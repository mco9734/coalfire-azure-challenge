variable "subscription_id" {
    description = "ID of Azure subscription"
    default = "<AZURE_SUBSCRIPTION_ID>"
}
variable "resource_group_location" {
  description = "The region where the virtual network is created."
  default     = "eastus"
}
variable "management_username" {
    description = "The username of the admin user of the management VM."
    default = "managementadmin"
}
variable "management_password" {
    description = "The password of the admin user of the management VM."
    default = "P@ssw0rd!"
}
variable "web_username" {
    description = "The username of the admin user of the web VM."
    default = "webadmin"
}
variable "web_password" {
    description = "The password of the admin user of the web VM."
    default = "P@ssw0rd!"
}

variable "management_ssh_ip" {
    description = "The value of the specific IP that should be allowed to SSH"
    default = "<YOUR_IP_ADDRESS>"
}