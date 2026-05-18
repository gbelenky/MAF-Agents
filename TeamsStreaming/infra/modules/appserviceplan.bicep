// App Service Plan module

@description('Name of the App Service Plan')
param name string

@description('Location for the resource')
param location string = resourceGroup().location

@description('Tags for the resource')
param tags object = {}

@description('SKU configuration')
param sku object = {
  name: 'B1'
  tier: 'Basic'
}

resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'linux'
  sku: sku
  properties: {
    reserved: true // Required for Linux
  }
}

output id string = appServicePlan.id
output name string = appServicePlan.name
