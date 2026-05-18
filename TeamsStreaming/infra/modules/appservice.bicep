// App Service (Web App) module

@description('Name of the App Service')
param name string

@description('Location for the resource')
param location string = resourceGroup().location

@description('Tags for the resource')
param tags object = {}

@description('Resource ID of the App Service Plan')
param appServicePlanId string

@description('Runtime stack (e.g., DOTNETCORE|8.0)')
param runtimeStack string = 'DOTNETCORE|8.0'

@description('Application settings')
param appSettings array = []

resource appService 'Microsoft.Web/sites@2024-04-01' = {
  name: name
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: runtimeStack
      alwaysOn: true
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      webSocketsEnabled: true // Required for real-time bot communication
      appSettings: concat(appSettings, [
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'false'
        }
      ])
    }
  }
}

output id string = appService.id
output name string = appService.name
output defaultHostName string = appService.properties.defaultHostName
output principalId string = appService.identity.principalId
