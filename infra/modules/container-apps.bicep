@description('Regiao Azure dos recursos de Container Apps.')
param location string

@description('Nome do ambiente azd.')
param environmentName string

@allowed([
  'dev'
  'prod'
])
@description('Tipo do ambiente para diferenciar escala.')
param environmentType string = 'dev'

@description('Object ID do principal usado pelo pipeline. Recebe AcrPush quando informado.')
param principalId string = ''

@description('Nome do Container App da API.')
param containerAppName string

@description('Nome do Container Apps Environment.')
param containerAppsEnvironmentName string

@description('Nome do Azure Container Registry.')
param containerRegistryName string

@description('Nome do Log Analytics Workspace.')
param logAnalyticsWorkspaceName string

@secure()
@description('Connection string PostgreSQL usada pela API.')
param postgresConnectionString string

@secure()
@description('Chave JWT usada pela API.')
param jwtSecretKey string

@description('Origem permitida para CORS.')
param corsAllowedOrigin string

var acrPushRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8311e382-0749-4cb8-b61a-304f252e45ec')
var acrPullRoleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: containerRegistryName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
  }
}

resource pipelineAcrPush 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  name: guid(containerRegistry.id, principalId, 'AcrPush')
  scope: containerRegistry
  properties: {
    principalId: principalId
    roleDefinitionId: acrPushRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: logAnalyticsWorkspaceName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environmentType == 'prod' ? 30 : 7
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalyticsWorkspace.properties.customerId
        sharedKey: logAnalyticsWorkspace.listKeys().primarySharedKey
      }
    }
  }
}

resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: {
    'azd-env-name': environmentName
    'azd-service-name': 'api'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 8080
        transport: 'auto'
        allowInsecure: false
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: 'system'
        }
      ]
      secrets: [
        {
          name: 'connection-string'
          value: postgresConnectionString
        }
        {
          name: 'jwt-secret-key'
          value: jwtSecretKey
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'api'
          image: 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          env: [
            {
              name: 'ASPNETCORE_ENVIRONMENT'
              value: environmentType == 'prod' ? 'Production' : 'Development'
            }
            {
              name: 'ASPNETCORE_URLS'
              value: 'http://+:8080'
            }
            {
              name: 'ConnectionStrings__DefaultConnection'
              secretRef: 'connection-string'
            }
            {
              name: 'Jwt__SecretKey'
              secretRef: 'jwt-secret-key'
            }
            {
              name: 'Cors__AllowedOrigins__0'
              value: corsAllowedOrigin
            }
          ]
          resources: {
            cpu: json(environmentType == 'prod' ? '0.5' : '0.25')
            memory: environmentType == 'prod' ? '1Gi' : '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: environmentType == 'prod' ? 1 : 0
        maxReplicas: environmentType == 'prod' ? 3 : 1
      }
    }
  }
}

resource containerAppAcrPull 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, containerApp.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    principalId: containerApp.identity.principalId
    roleDefinitionId: acrPullRoleDefinitionId
    principalType: 'ServicePrincipal'
  }
}

output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output apiUri string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
