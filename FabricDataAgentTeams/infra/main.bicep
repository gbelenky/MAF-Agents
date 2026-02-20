targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (used for resource naming)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

// App Service configuration
@description('App Service SKU')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v3', 'P2v3', 'P3v3'])
param appServiceSku string = 'B1'

// Bot configuration (from Entra ID setup)
@description('Azure AD Tenant ID')
param tenantId string = subscription().tenantId

@description('Bot App Client ID (from Entra ID setup script)')
param botClientId string

// Fabric Data Agent configuration
@description('Fabric Workspace ID')
param fabricWorkspaceId string = ''

@description('Fabric Data Agent Item ID')
param fabricAgentItemId string = ''

// Bot Framework configuration
@description('Enable Azure Bot Service for Teams integration')
param enableBot bool = true

@description('Microsoft App ID for the bot (same as botClientId)')
param botMicrosoftAppId string = ''

@description('Use UserAssignedMSI for bot authentication (false = SingleTenant with client secret)')
param botUseUserAssignedMSI bool = false

@description('Enable monitoring with Log Analytics and Application Insights')
param enableMonitoring bool = true

// Resource group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
}

// User Assigned Managed Identity
module managedIdentity 'app/identity/managed-identity.bicep' = {
  name: 'managed-identity'
  scope: rg
  params: {
    name: 'id-${environmentName}'
    location: location
  }
}

// Monitoring (Log Analytics + Application Insights)
module monitoring 'app/monitoring/log-analytics.bicep' = if (enableMonitoring) {
  name: 'monitoring'
  scope: rg
  params: {
    name: 'law-${environmentName}'
    location: location
  }
}

// App Service for the Fabric Data Agent Bot (Python)
module appService 'app/web/app-service.bicep' = {
  name: 'app-service'
  scope: rg
  params: {
    name: 'app-${environmentName}'
    location: location
    sku: appServiceSku
    userAssignedIdentityId: managedIdentity.outputs.id
    userAssignedIdentityClientId: managedIdentity.outputs.clientId
    tenantId: tenantId
    botClientId: botClientId
    fabricWorkspaceId: fabricWorkspaceId
    fabricAgentItemId: fabricAgentItemId
    // Bot Framework configuration
    botMicrosoftAppId: enableBot ? (empty(botMicrosoftAppId) ? botClientId : botMicrosoftAppId) : ''
    botOAuthConnectionName: 'fabric-connection'
    // Application Insights
    appInsightsConnectionString: enableMonitoring ? monitoring!.outputs.appInsightsConnectionString : ''
  }
}

// Azure Bot Service (for Teams integration)
module botService 'app/bot/bot-service.bicep' = if (enableBot) {
  name: 'bot-service'
  scope: rg
  params: {
    name: 'bot-${environmentName}'
    appServiceUrl: appService.outputs.url
    microsoftAppId: empty(botMicrosoftAppId) ? botClientId : botMicrosoftAppId
    tenantId: tenantId
    displayName: 'Fabric Data Agent'
    botDescription: 'AI-powered Fabric Data Agent assistant for Teams'
    // UserAssignedMSI configuration
    useUserAssignedMSI: botUseUserAssignedMSI
    msaAppMSIResourceId: botUseUserAssignedMSI ? managedIdentity.outputs.id : ''
    // Application Insights integration
    appInsightsInstrumentationKey: enableMonitoring ? monitoring!.outputs.appInsightsInstrumentationKey : ''
    appInsightsApplicationId: enableMonitoring ? last(split(monitoring!.outputs.appInsightsId, '/')) : ''
  }
}

// Bot Service Diagnostics
module botDiagnostics 'app/monitoring/bot-diagnostics.bicep' = if (enableBot && enableMonitoring) {
  name: 'bot-diagnostics'
  scope: rg
  params: {
    name: 'diag-bot-${environmentName}'
    botServiceId: botService!.outputs.botId
    logAnalyticsWorkspaceId: monitoring!.outputs.logAnalyticsId
  }
}

// =============================================================================
// Outputs for azd environment
// =============================================================================
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_LOCATION string = location

// Managed Identity outputs (needed for Entra ID FIC setup)
output MANAGED_IDENTITY_CLIENT_ID string = managedIdentity.outputs.clientId
output MANAGED_IDENTITY_PRINCIPAL_ID string = managedIdentity.outputs.principalId
output MANAGED_IDENTITY_NAME string = managedIdentity.outputs.name

// App Service outputs
output APP_SERVICE_NAME string = appService.outputs.name
output APP_SERVICE_URL string = appService.outputs.url
output APP_SERVICE_HOSTNAME string = appService.outputs.hostname

// Bot Service outputs (conditional)
output BOT_NAME string = enableBot && botService != null ? botService!.outputs.botName : ''
output BOT_MESSAGING_ENDPOINT string = enableBot && botService != null ? botService!.outputs.messagingEndpoint : ''
output BOT_OAUTH_CONNECTION_NAME string = enableBot && botService != null ? botService!.outputs.oauthConnectionName : ''
output BOT_SSO_TOKEN_EXCHANGE_URL string = enableBot && botService != null ? botService!.outputs.ssoTokenExchangeUrl : ''

// Monitoring outputs
output LOG_ANALYTICS_WORKSPACE_ID string = enableMonitoring ? monitoring!.outputs.logAnalyticsWorkspaceId : ''
output APP_INSIGHTS_CONNECTION_STRING string = enableMonitoring ? monitoring!.outputs.appInsightsConnectionString : ''
