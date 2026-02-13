targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (used for resource naming)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the chat model to deploy')
@allowed(['gpt-4o-mini', 'gpt-4o'])
param chatModelName string = 'gpt-4o-mini'

@description('Version of the chat model')
param chatModelVersion string = '2024-07-18'

@description('Capacity for the chat model deployment')
param chatModelCapacity int = 30

// App Service configuration
@description('App Service SKU')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v3', 'P2v3', 'P3v3'])
param appServiceSku string = 'B1'

// Agent Identity configuration (from Entra ID setup)
@description('Azure AD Tenant ID')
param tenantId string = subscription().tenantId

@description('Agent Identity App Client ID (from Entra ID setup script)')
param agentIdentityClientId string

// Bot Framework configuration (for Teams/M365 Copilot)
@description('Enable Azure Bot Service for Teams/M365 Copilot integration')
param enableBot bool = false

@description('Microsoft App ID for the bot (from Entra ID app registration)')
param botMicrosoftAppId string = ''

@description('Use UserAssignedMSI for bot authentication (recommended for production)')
param botUseUserAssignedMSI bool = true

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
// Defined before AI Services so we can pass the workspace ID for diagnostics
module monitoring 'app/monitoring/log-analytics.bicep' = if (enableMonitoring) {
  name: 'monitoring'
  scope: rg
  params: {
    name: 'law-${environmentName}'
    location: location
  }
}

// AI Services with Foundry Project
module aiServices 'app/ai/cognitive-services.bicep' = {
  name: 'ai-services'
  scope: rg
  params: {
    name: 'ai-${environmentName}'
    location: location
    chatModelName: chatModelName
    chatModelVersion: chatModelVersion
    chatModelCapacity: chatModelCapacity
    logAnalyticsWorkspaceId: enableMonitoring ? monitoring.outputs.logAnalyticsId : ''
  }
}

// RBAC for current user (deployment principal)
module rbacUser 'app/rbac/openai-access.bicep' = {
  name: 'rbac-user'
  scope: rg
  params: {
    aiServicesName: aiServices.outputs.aiServicesName
    principalId: deployer().objectId
  }
}

// RBAC for Managed Identity
module rbacManagedIdentity 'app/rbac/managed-identity-access.bicep' = {
  name: 'rbac-managed-identity'
  scope: rg
  params: {
    aiServicesName: aiServices.outputs.aiServicesName
    principalId: managedIdentity.outputs.principalId
  }
}

// App Service for the OneDrive Agent API
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
    agentIdentityClientId: agentIdentityClientId
    foundryEndpoint: aiServices.outputs.aiServicesEndpoint
    modelDeploymentName: aiServices.outputs.chatModelDeploymentName
    // Bot Framework configuration
    botMicrosoftAppId: enableBot ? botMicrosoftAppId : ''
    botOAuthConnectionName: 'graph-connection'
    // Application Insights
    appInsightsConnectionString: enableMonitoring ? monitoring!.outputs.appInsightsConnectionString : ''
  }
  dependsOn: [
    rbacManagedIdentity
  ]
}

// Azure Bot Service (optional - for Teams/M365 Copilot)
module botService 'app/bot/bot-service.bicep' = if (enableBot) {
  name: 'bot-service'
  scope: rg
  params: {
    name: 'bot-${environmentName}'
    appServiceUrl: appService.outputs.url
    microsoftAppId: botMicrosoftAppId
    tenantId: tenantId
    displayName: 'OneDrive Agent'
    botDescription: 'AI-powered OneDrive assistant that helps users manage their files'
    // UserAssignedMSI configuration
    useUserAssignedMSI: botUseUserAssignedMSI
    msaAppMSIResourceId: botUseUserAssignedMSI ? managedIdentity.outputs.id : ''
    // Application Insights integration
    appInsightsInstrumentationKey: enableMonitoring ? monitoring!.outputs.appInsightsInstrumentationKey : ''
    appInsightsApplicationId: enableMonitoring ? last(split(monitoring!.outputs.appInsightsId, '/')) : ''
  }
}

// Bot Service Diagnostics (when both bot and monitoring are enabled)
module botDiagnostics 'app/monitoring/bot-diagnostics.bicep' = if (enableBot && enableMonitoring) {
  name: 'bot-diagnostics'
  scope: rg
  params: {
    name: 'diag-bot-${environmentName}'
    botServiceId: botService!.outputs.botId
    logAnalyticsWorkspaceId: monitoring!.outputs.logAnalyticsId
  }
}

// Outputs for azd environment
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_LOCATION string = location
output PROJECT_ENDPOINT string = aiServices.outputs.projectEndpoint
output CHAT_MODEL_DEPLOYMENT string = aiServices.outputs.chatModelDeploymentName
output AI_SERVICES_NAME string = aiServices.outputs.aiServicesName

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
