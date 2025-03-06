terraform {
  backend "azurerm" {
    resource_group_name   = "ospk-app-dev-rg"
    storage_account_name  = "ospkstgacct"
    container_name        = "ospktfstate"
    key                   = "terraform.tfstate"
    access_key            = "abcdefg/+Sd345AbcXyzfqfGl2uVrC5jlfsuL23ertE1Cd2=="
  }
}