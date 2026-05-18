// Azure Bot Service module

@description('Name of the Bot Service')
param name string

@description('Location for the resource (should be "global" for Bot Service)')
param location string = 'global'

@description('Tags for the resource')
param tags object = {}

@description('Microsoft App ID (Bot ID) from Entra App Registration')
param botId string

@description('Microsoft App Tenant ID')
param botTenantId string = ''

@description('Display name for the bot')
param botDisplayName string = 'Teams Streaming Bot'

@description('Bot messaging endpoint URL')
param messagingEndpoint string

@description('Bot SKU')
@allowed(['F0', 'S1'])
param sku string = 'F0'

resource botService 'Microsoft.BotService/botServices@2022-09-15' = {
  name: name
  location: location
  tags: tags
  kind: 'azurebot'
  sku: {
    name: sku
  }
  properties: {
    displayName: botDisplayName
    endpoint: messagingEndpoint
    msaAppId: botId
    msaAppType: 'SingleTenant'
    msaAppTenantId: botTenantId
    schemaTransformationVersion: '1.3'
    disableLocalAuth: false
  }
}

// Add Microsoft Teams channel
resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: botService
  name: 'MsTeamsChannel'
  location: location
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
    }
  }
}

// Add Web Chat channel for testing
resource webChatChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: botService
  name: 'WebChatChannel'
  location: location
  properties: {
    channelName: 'WebChatChannel'
    properties: {
      sites: [
        {
          siteName: 'Default Site'
          isEnabled: true
        }
      ]
    }
  }
}

output id string = botService.id
output name string = botService.name
output endpoint string = messagingEndpoint
