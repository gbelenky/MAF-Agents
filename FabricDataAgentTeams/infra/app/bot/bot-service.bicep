// Azure Bot Service for Teams integration
// Includes OAuth connection for SSO with Fabric API

@description('Name of the bot resource')
param name string

@description('Location for the bot resource (global for Bot Service)')
param location string = 'global'

@description('App Service URL for the messaging endpoint')
param appServiceUrl string

@description('Microsoft App ID for the bot (from Entra ID registration)')
param microsoftAppId string

@description('Microsoft App Tenant ID')
param tenantId string

@description('Display name for the bot')
param displayName string = 'Fabric Data Agent'

@description('Description for the bot')
param botDescription string = 'AI-powered Fabric Data Agent assistant for Teams'

@description('OAuth connection name for Fabric API access')
param oauthConnectionName string = 'fabric-connection'

@description('Use UserAssignedMSI authentication instead of SingleTenant')
param useUserAssignedMSI bool = false

@description('User Assigned Managed Identity resource ID (required if useUserAssignedMSI is true)')
param msaAppMSIResourceId string = ''

@description('Application Insights Instrumentation Key')
param appInsightsInstrumentationKey string = ''

@description('Application Insights Application ID')
param appInsightsApplicationId string = ''

// Azure Bot Service resource
resource bot 'Microsoft.BotService/botServices@2022-09-15' = {
  name: name
  location: location
  kind: 'azurebot'
  sku: {
    name: 'S1'
  }
  properties: {
    displayName: displayName
    description: botDescription
    endpoint: '${appServiceUrl}/api/messages'
    msaAppId: microsoftAppId
    msaAppTenantId: tenantId
    msaAppType: useUserAssignedMSI ? 'UserAssignedMSI' : 'SingleTenant'
    msaAppMSIResourceId: useUserAssignedMSI ? msaAppMSIResourceId : null
    developerAppInsightKey: appInsightsInstrumentationKey
    developerAppInsightsApplicationId: appInsightsApplicationId
    luisAppIds: []
    isCmekEnabled: false
    isStreamingSupported: true
    schemaTransformationVersion: '1.3'
  }
}

// Microsoft Teams channel
resource teamsChannel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'MsTeamsChannel'
  location: location
  properties: {
    channelName: 'MsTeamsChannel'
    properties: {
      isEnabled: true
      enableCalling: false
      incomingCallRoute: ''
      deploymentEnvironment: 'CommercialDeployment'
      acceptedTerms: true
    }
  }
}

// M365 Extensions channel (for M365 Copilot)
resource m365Channel 'Microsoft.BotService/botServices/channels@2022-09-15' = {
  parent: bot
  name: 'M365Extensions'
  location: location
  properties: {
    channelName: 'M365Extensions'
  }
}

// OAuth Connection for Fabric API with SSO
// Note: The client secret and scopes must be set via Azure CLI after deployment
// This creates a placeholder connection that the admin script will configure
resource oauthConnection 'Microsoft.BotService/botServices/connections@2022-09-15' = {
  parent: bot
  name: oauthConnectionName
  location: location
  properties: {
    serviceProviderDisplayName: 'Azure Active Directory v2'
    serviceProviderId: '30dd229c-58e3-4a48-bdfd-91ec48eb906c'
    clientId: microsoftAppId
    clientSecret: 'PLACEHOLDER_SET_VIA_CLI'
    scopes: 'https://api.fabric.microsoft.com/.default openid profile'
    parameters: [
      {
        key: 'tenantID'
        value: tenantId
      }
      {
        key: 'tokenExchangeUrl'
        value: 'api://botid-${microsoftAppId}'
      }
    ]
  }
}

output botId string = bot.id
output botName string = bot.name
output messagingEndpoint string = '${appServiceUrl}/api/messages'
output oauthConnectionName string = oauthConnection.name
output ssoTokenExchangeUrl string = 'api://botid-${microsoftAppId}'
