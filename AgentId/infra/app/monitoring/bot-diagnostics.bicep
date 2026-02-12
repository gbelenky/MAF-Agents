@description('Name for the diagnostic settings')
param name string

@description('Bot Service resource ID')
param botServiceId string

@description('Log Analytics Workspace ID')
param logAnalyticsWorkspaceId string

// Diagnostic Settings for Bot Service
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: name
  scope: botService
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'BotRequest'
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

// Reference to existing Bot Service
resource botService 'Microsoft.BotService/botServices@2022-09-15' existing = {
  name: last(split(botServiceId, '/'))
}
