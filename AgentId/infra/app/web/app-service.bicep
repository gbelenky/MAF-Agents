@description('Name for the App Service')
param name string

@description('Location for the resource')
param location string

@description('Tags to apply to resources')
param tags object = {}

@description('The SKU for the App Service Plan')
@allowed(['B1', 'B2', 'B3', 'S1', 'S2', 'S3', 'P1v3', 'P2v3', 'P3v3'])
param sku string = 'B1'

@description('User Assigned Managed Identity resource ID')
param userAssignedIdentityId string

@description('User Assigned Managed Identity client ID')
param userAssignedIdentityClientId string

// Agent OBO configuration
@description('Azure AD Tenant ID')
param tenantId string

@description('Agent Identity App Client ID')
param agentIdentityClientId string

@description('Target scope for OBO (e.g., https://graph.microsoft.com/.default)')
param targetScope string = 'https://graph.microsoft.com/.default'

// MAF Agent configuration
@description('AI Foundry Project endpoint')
param foundryEndpoint string

@description('Model deployment name')
param modelDeploymentName string

// Bot Framework configuration (optional - for Teams/M365 Copilot)
@description('Microsoft App ID for the bot')
param botMicrosoftAppId string = ''

@description('OAuth connection name for Graph API')
param botOAuthConnectionName string = 'graph-connection'

@description('Application Insights connection string (optional)')
param appInsightsConnectionString string = ''

// App Service Plan
resource appServicePlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${name}-plan'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: sku
  }
  properties: {
    reserved: true // Required for Linux
  }
}

// App Service
resource appService 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  tags: union(tags, {
    'azd-service-name': 'api'
  })
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityId}': {}
    }
  }
  properties: {
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|9.0'
      alwaysOn: sku != 'B1' // AlwaysOn not available on Basic tier
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      healthCheckPath: '/health'
      appSettings: [
        // Managed Identity configuration
        {
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentityClientId
        }
        // MAF Agent configuration
        {
          name: 'MafAgent__FoundryEndpoint'
          value: foundryEndpoint
        }
        {
          name: 'MafAgent__ModelDeploymentName'
          value: modelDeploymentName
        }
        // General settings
        {
          name: 'ASPNETCORE_ENVIRONMENT'
          value: 'Production'
        }
        {
          name: 'ASPNETCORE_URLS'
          value: 'http://0.0.0.0:8080'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        // Bot Framework configuration (M365 Agents SDK)
        {
          name: 'Bot__MicrosoftAppId'
          value: botMicrosoftAppId
        }
        {
          name: 'Bot__MicrosoftAppTenantId'
          value: tenantId
        }
        {
          name: 'Bot__OAuthConnectionName'
          value: botOAuthConnectionName
        }
        // M365 Agents SDK Connection settings
        {
          name: 'Connections__BotServiceConnection__Assembly'
          value: 'Microsoft.Agents.Authentication.Msal'
        }
        {
          name: 'Connections__BotServiceConnection__Type'
          value: 'MsalAuth'
        }
        {
          name: 'Connections__BotServiceConnection__Settings__AuthType'
          value: 'FederatedCredentials'
        }
        {
          name: 'Connections__BotServiceConnection__Settings__ClientId'
          value: agentIdentityClientId  // Bot App ID
        }
        {
          name: 'Connections__BotServiceConnection__Settings__FederatedClientId'
          value: userAssignedIdentityClientId  // Managed Identity Client ID
        }
        {
          name: 'Connections__BotServiceConnection__Settings__ManagedIdentityClientId'
          value: userAssignedIdentityClientId  // Managed Identity Client ID (for FIC auth)
        }
        {
          name: 'Connections__BotServiceConnection__Settings__TenantId'
          value: tenantId
        }
        {
          name: 'Connections__BotServiceConnection__Settings__Authority'
          value: 'https://login.microsoftonline.com/${tenantId}'
        }
        // Application Insights (if configured)
        ...(empty(appInsightsConnectionString) ? [] : [
          {
            name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
            value: appInsightsConnectionString
          }
        ])
      ]
    }
  }
}

// Diagnostic settings (optional but recommended)
resource appServiceLogs 'Microsoft.Web/sites/config@2023-12-01' = {
  parent: appService
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Information'
      }
    }
    httpLogs: {
      fileSystem: {
        enabled: true
        retentionInDays: 7
        retentionInMb: 35
      }
    }
    detailedErrorMessages: {
      enabled: true
    }
    failedRequestsTracing: {
      enabled: true
    }
  }
}

output id string = appService.id
output name string = appService.name
output hostname string = appService.properties.defaultHostName
output url string = 'https://${appService.properties.defaultHostName}'
