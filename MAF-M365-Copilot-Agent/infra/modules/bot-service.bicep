// Azure Bot Service
@description('Name of the bot')
param name string

@description('Location for the resource (use global for Bot Service)')
param location string

@description('Display name of the bot')
param displayName string

@description('Messaging endpoint URL')
param endpoint string

@description('Microsoft App ID')
param microsoftAppId string

@description('Microsoft App Tenant ID')
param microsoftAppTenantId string

@description('Tags for the resource')
param tags object = {}

resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'F0'
  }
  kind: 'azurebot'
  properties: {
    displayName: displayName
    endpoint: endpoint
    msaAppId: microsoftAppId
    msaAppTenantId: microsoftAppTenantId
    msaAppType: 'SingleTenant'
    schemaTransformationVersion: '1.3'
  }
}

// Teams channel
resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'MsTeamsChannel'
  location: location
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
    }
  }
}

// M365 Extensions channel (Outlook, Copilot)
resource m365Channel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'M365Extensions'
  location: location
}

output id string = bot.id
output name string = bot.name
