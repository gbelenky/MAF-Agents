@description('Name for the AI Services resource')
param name string

@description('Location for the resource')
param location string

@description('Chat model name to deploy')
param chatModelName string

@description('Version of the chat model')
param chatModelVersion string

@description('Capacity for the chat model')
param chatModelCapacity int

@description('Log Analytics Workspace ID for diagnostics (optional)')
param logAnalyticsWorkspaceId string = ''

// AI Services account with Foundry capabilities
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    allowProjectManagement: true
    networkAcls: {
      defaultAction: 'Allow'
    }
  }
}

// Foundry Project
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiServices
  name: 'prj-${name}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {}
}

// Chat model deployment
resource chatModelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: chatModelName
  sku: {
    name: 'Standard'
    capacity: chatModelCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: chatModelName
      version: chatModelVersion
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
  }
}

// Diagnostic settings to send AI Services logs to Log Analytics
resource aiDiagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (!empty(logAnalyticsWorkspaceId)) {
  name: 'ai-to-log-analytics'
  scope: aiServices
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'RequestResponse'
        enabled: true
      }
      {
        category: 'Audit'
        enabled: true
      }
      {
        category: 'Trace'
        enabled: true
      }
    ]
    metrics: [
      {
        category: 'AllMetrics'
        enabled: true
      }
    ]
  }
}

output aiServicesName string = aiServices.name
output aiServicesEndpoint string = aiServices.properties.endpoint
output projectName string = project.name
output projectEndpoint string = '${aiServices.properties.endpoint}api/projects/${project.name}'
output chatModelDeploymentName string = chatModelDeployment.name
