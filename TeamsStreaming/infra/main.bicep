// Main Bicep template for Teams Streaming Bot
// This deploys: App Service Plan, App Service, Azure Bot, and optionally Azure OpenAI

targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the environment (e.g., dev, staging, prod)')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Bot App ID (Microsoft Entra App Registration)')
param botId string

@secure()
@description('Bot App Password/Secret')
param botPassword string

@description('Bot Tenant ID for SingleTenant configuration')
param botTenantId string = ''

@description('Azure OpenAI Endpoint URL')
param azureOpenAIEndpoint string = ''

@description('Azure OpenAI Deployment Name')
param azureOpenAIDeploymentName string = 'gpt-4o'

@secure()
@description('Azure OpenAI API Key (optional if using Managed Identity)')
param azureOpenAIApiKey string = ''

@description('SKU for App Service Plan')
param appServicePlanSku string = 'S1'

@description('Bot display name in Teams')
param botDisplayName string = 'Teams Streaming Bot'

// Variables
var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  'project': 'teams-streaming-bot'
}

// Compute tier mapping
var skuTierMap = {
  F1: 'Free'
  B1: 'Basic'
  B2: 'Basic'
  B3: 'Basic'
  S1: 'Standard'
  S2: 'Standard'
  S3: 'Standard'
  P1v2: 'PremiumV2'
  P2v2: 'PremiumV2'
  P3v2: 'PremiumV2'
}

// Resource Group
resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: 'rg-${environmentName}'
  location: location
  tags: tags
}

// Log Analytics Workspace (required for Application Insights)
module logAnalytics 'modules/loganalytics.bicep' = {
  name: 'logAnalytics'
  scope: rg
  params: {
    name: '${abbrs.logAnalyticsWorkspace}${resourceToken}'
    location: location
    tags: tags
  }
}

// Application Insights
module appInsights 'modules/applicationinsights.bicep' = {
  name: 'appInsights'
  scope: rg
  params: {
    name: '${abbrs.appInsights}${resourceToken}'
    location: location
    tags: tags
    workspaceId: logAnalytics.outputs.id
  }
}

// App Service Plan
module appServicePlan 'modules/appserviceplan.bicep' = {
  name: 'appServicePlan'
  scope: rg
  params: {
    name: '${abbrs.webServerFarms}${resourceToken}'
    location: location
    tags: tags
    sku: {
      name: appServicePlanSku
      tier: contains(skuTierMap, appServicePlanSku) ? skuTierMap[appServicePlanSku] : 'Standard'
    }
  }
}

// App Service (Web App for the Bot)
module appService 'modules/appservice.bicep' = {
  name: 'appService'
  scope: rg
  params: {
    name: '${abbrs.webSitesAppService}${resourceToken}'
    location: location
    tags: union(tags, { 'azd-service-name': 'bot' })
    appServicePlanId: appServicePlan.outputs.id
    runtimeStack: 'DOTNETCORE|8.0'
    appSettings: [
      {
        name: 'BOT_ID'
        value: botId
      }
      {
        name: 'BOT_PASSWORD'
        value: botPassword
      }
      {
        name: 'BOT_TYPE'
        value: 'SingleTenant'
      }
      {
        name: 'BOT_TENANT_ID'
        value: botTenantId
      }
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: azureOpenAIEndpoint
      }
      {
        name: 'AZURE_OPENAI_DEPLOYMENT_NAME'
        value: azureOpenAIDeploymentName
      }
      {
        name: 'AZURE_OPENAI_API_KEY'
        value: azureOpenAIApiKey
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        value: appInsights.outputs.connectionString
      }
      // M365 Agents SDK connection settings (hierarchical config override)
      {
        name: 'Connections__BotServiceConnection__Settings__ClientId'
        value: botId
      }
      {
        name: 'Connections__BotServiceConnection__Settings__ClientSecret'
        value: botPassword
      }
      {
        name: 'Connections__BotServiceConnection__Settings__TenantId'
        value: botTenantId
      }
      {
        name: 'TokenValidation__Audiences__0'
        value: botId
      }
    ]
  }
}

// Azure Bot Service
module botService 'modules/botservice.bicep' = {
  name: 'botService'
  scope: rg
  params: {
    name: '${abbrs.cognitiveServicesBot}${resourceToken}'
    location: 'global'
    tags: tags
    botId: botId
    botTenantId: botTenantId
    botDisplayName: botDisplayName
    messagingEndpoint: 'https://${appService.outputs.defaultHostName}/api/messages'
  }
}

// Outputs
output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output BOT_ID string = botId
output BOT_DISPLAY_NAME string = botDisplayName
output SERVICE_BOT_NAME string = appService.outputs.name
output SERVICE_BOT_URL string = 'https://${appService.outputs.defaultHostName}'
output BOT_MESSAGING_ENDPOINT string = 'https://${appService.outputs.defaultHostName}/api/messages'
output AZURE_BOT_NAME string = botService.outputs.name
output APPLICATIONINSIGHTS_NAME string = appInsights.outputs.name
output LOGANALYTICS_WORKSPACE_NAME string = logAnalytics.outputs.name
