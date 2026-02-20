// App Service for Fabric Data Agent Teams Bot (Python)

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

// Bot configuration
@description('Azure AD Tenant ID')
param tenantId string

@description('Bot App Client ID')
param botClientId string

// Fabric Data Agent configuration
@description('Fabric Workspace ID')
param fabricWorkspaceId string

@description('Fabric Data Agent Item ID')
param fabricAgentItemId string

// Bot Framework configuration
@description('Microsoft App ID for the bot')
param botMicrosoftAppId string = ''

@description('OAuth connection name for Fabric API')
param botOAuthConnectionName string = 'fabric-connection'

@description('Application Insights connection string (optional)')
param appInsightsConnectionString string = ''

// App Service Plan (Linux for Python)
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
      linuxFxVersion: 'PYTHON|3.11'
      alwaysOn: sku != 'B1' // AlwaysOn not available on Basic tier
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      healthCheckPath: '/health'
      appCommandLine: 'python main.py'
      appSettings: [
        // Managed Identity configuration
        {
          name: 'AZURE_CLIENT_ID'
          value: userAssignedIdentityClientId
        }
        // Fabric Data Agent configuration
        {
          name: 'FABRIC_WORKSPACE_ID'
          value: fabricWorkspaceId
        }
        {
          name: 'FABRIC_AGENT_ITEM_ID'
          value: fabricAgentItemId
        }
        // Server configuration
        {
          name: 'PORT'
          value: '8080'
        }
        {
          name: 'WEBSITES_PORT'
          value: '8080'
        }
        // Bot Framework configuration
        {
          name: 'BOT_MICROSOFT_APP_ID'
          value: botMicrosoftAppId
        }
        {
          name: 'BOT_MICROSOFT_APP_TENANT_ID'
          value: tenantId
        }
        {
          name: 'BOT_OAUTH_CONNECTION_NAME'
          value: botOAuthConnectionName
        }
        // Bot Framework authentication (SingleTenant with client secret)
        // Note: MicrosoftAppPassword is set via CLI in Step 3 for security
        {
          name: 'MicrosoftAppType'
          value: 'SingleTenant'
        }
        {
          name: 'MicrosoftAppId'
          value: botClientId
        }
        {
          name: 'MicrosoftAppTenantId'
          value: tenantId
        }
        // Application Insights
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
        // Python environment
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
      ]
    }
  }
}

// Diagnostic settings for logging
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
output url string = 'https://${appService.properties.defaultHostName}'
output hostname string = appService.properties.defaultHostName
