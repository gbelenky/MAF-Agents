// Azure Bot Service for Teams and M365 Copilot integration
// Includes OAuth connection for SSO with Graph API

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
param displayName string = 'OneDrive Agent'

@description('Description for the bot')
param botDescription string = 'AI-powered OneDrive assistant that helps users manage their files'

@description('OAuth connection name for Graph API access')
param oauthConnectionName string = 'graph-connection'

@description('Scopes for the OAuth connection')
param graphScopes string = 'Files.Read Files.ReadWrite User.Read'

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

// OAuth Connection for Graph API with SSO
// Note: The client secret must be set via Azure CLI after deployment
// az bot authsetting set --resource-group <rg> --name <bot> --setting-name graph-connection \
//   --client-id <app-id> --client-secret <secret> ...
resource oauthConnection 'Microsoft.BotService/botServices/connections@2022-09-15' = {
  parent: bot
  name: oauthConnectionName
  location: location
  properties: {
    clientId: microsoftAppId
    clientSecret: '' // Will be set post-deployment via script
    scopes: graphScopes
    serviceProviderId: '30dd229c-58e3-4a48-bdfd-91ec48eb906c' // Azure Active Directory v2
    serviceProviderDisplayName: 'Azure Active Directory v2'
    parameters: [
      {
        key: 'tenantId'
        value: tenantId
      }
      {
        key: 'tokenExchangeUrl'
        value: 'api://botid-${microsoftAppId}' // SSO token exchange URL
      }
    ]
  }
}

// Outputs
output botId string = bot.id
output botName string = bot.name
output messagingEndpoint string = '${appServiceUrl}/api/messages'
output oauthConnectionName string = oauthConnectionName
output ssoTokenExchangeUrl string = 'api://botid-${microsoftAppId}'
output msaAppType string = useUserAssignedMSI ? 'UserAssignedMSI' : 'SingleTenant'
