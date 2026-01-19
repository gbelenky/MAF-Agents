// MAF M365 Copilot Agent - Azure Infrastructure
// Deploys: Function App, Storage, Bot Service, App Insights, DTS
targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g., dev, prod)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Location for Durable Task Scheduler (limited availability)')
param dtsLocation string = 'northeurope'

@description('Name of the resource group')
param resourceGroupName string = 'rg-${environmentName}'

@description('Azure OpenAI endpoint URL')
param azureOpenAIEndpoint string

@description('Azure OpenAI deployment name')
param azureOpenAIDeployment string

@description('Bot display name')
param botDisplayName string = 'MAF Copilot Agent'

@secure()
@description('Microsoft App ID for Bot')
param microsoftAppId string

@secure()
@description('Microsoft App Password for Bot')
param microsoftAppPassword string

@description('Microsoft App Tenant ID (for single-tenant bots)')
param microsoftAppTenantId string

// Generate unique token for resource names
var resourceToken = uniqueString(subscription().id, location, environmentName)

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
}

// User-Assigned Managed Identity
module identity './modules/identity.bicep' = {
  name: 'identity'
  scope: rg
  params: {
    name: 'id-${resourceToken}'
    location: location
    tags: {
      'azd-env-name': environmentName
    }
  }
}

// Log Analytics Workspace
module logAnalytics './modules/log-analytics.bicep' = {
  name: 'logAnalytics'
  scope: rg
  params: {
    name: 'log${resourceToken}'
    location: location
    tags: {
      'azd-env-name': environmentName
    }
  }
}

// Application Insights
module appInsights './modules/app-insights.bicep' = {
  name: 'appInsights'
  scope: rg
  params: {
    name: 'appi${resourceToken}'
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    tags: {
      'azd-env-name': environmentName
    }
  }
}

// Storage Account
module storage './modules/storage.bicep' = {
  name: 'storage'
  scope: rg
  params: {
    name: 'st${resourceToken}'
    location: location
    managedIdentityPrincipalId: identity.outputs.principalId
    tags: {
      'azd-env-name': environmentName
    }
  }
}

// Durable Task Scheduler
module dts './modules/durable-task-scheduler.bicep' = {
  name: 'dts'
  scope: rg
  params: {
    name: 'dts${resourceToken}'
    location: dtsLocation
    taskHubName: 'default'
    managedIdentityPrincipalId: identity.outputs.principalId
    tags: {
      'azd-env-name': environmentName
    }
  }
}

// Function App with App Service Plan
module functionApp './modules/function-app.bicep' = {
  name: 'functionApp'
  scope: rg
  params: {
    name: 'func${resourceToken}'
    location: location
    appServicePlanName: 'asp${resourceToken}'
    storageAccountName: storage.outputs.name
    appInsightsConnectionString: appInsights.outputs.connectionString
    appInsightsInstrumentationKey: appInsights.outputs.instrumentationKey
    managedIdentityId: identity.outputs.id
    managedIdentityClientId: identity.outputs.clientId
    logAnalyticsWorkspaceId: logAnalytics.outputs.id
    dtsEndpoint: dts.outputs.endpoint
    dtsTaskHubName: dts.outputs.taskHubName
    azureOpenAIEndpoint: azureOpenAIEndpoint
    azureOpenAIDeployment: azureOpenAIDeployment
    microsoftAppId: microsoftAppId
    microsoftAppPassword: microsoftAppPassword
    microsoftAppTenantId: microsoftAppTenantId
    tags: {
      'azd-env-name': environmentName
      'azd-service-name': 'api'
    }
  }
}

// Azure Bot Service
module bot './modules/bot-service.bicep' = {
  name: 'bot'
  scope: rg
  params: {
    name: 'bot${resourceToken}'
    location: 'global'
    displayName: botDisplayName
    endpoint: 'https://${functionApp.outputs.defaultHostName}/api/messages'
    microsoftAppId: microsoftAppId
    microsoftAppTenantId: microsoftAppTenantId
    tags: {
      'azd-env-name': environmentName
    }
  }
}

// Outputs
output RESOURCE_GROUP_ID string = rg.id
output RESOURCE_GROUP_NAME string = rg.name
output FUNCTION_APP_NAME string = functionApp.outputs.name
output FUNCTION_APP_URL string = functionApp.outputs.defaultHostName
output BOT_NAME string = bot.outputs.name
output STORAGE_ACCOUNT_NAME string = storage.outputs.name
output APP_INSIGHTS_NAME string = appInsights.outputs.name
output DTS_NAME string = dts.outputs.name
output DTS_ENDPOINT string = dts.outputs.endpoint
