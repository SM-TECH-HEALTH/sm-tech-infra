param location string
param environmentName string

@allowed(['dev', 'prod'])
param environmentType string

param resourceToken string

param postgresHost string
param postgresDb string
param postgresUser string

@secure()
param postgresPassword string

param serviceName string

var workspaceName = 'log-${take(resourceToken, 20)}'
var envName = 'cae-${take(resourceToken, 20)}'
var appName = 'ca-${take(resourceToken, 20)}'
var identityName = 'id-${take(resourceToken, 20)}'

var acrName = take(toLower('acr${uniqueString(subscription().id, resourceGroup().id, environmentName)}'), 50)

var bootstrapImage = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
var bootstrapPort = 80

resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
  }
}

resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: envName
  location: location
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
  }
  dependsOn: [logAnalytics]
}

resource containerRegistry 'Microsoft.ContainerRegistry/registries@2023-07-01' = {
  name: acrName
  location: location
  sku: {
    name: 'Basic'
  }
  properties: {
    adminUserEnabled: false
    publicNetworkAccess: 'Enabled'
  }
}

resource acrPullIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: identityName
  location: location
}

resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(containerRegistry.id, acrPullIdentity.id, 'AcrPull')
  scope: containerRegistry
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7dfe7d4a-4950-4f3a-9939-0f2e0f63ee17')
    principalId: acrPullIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
  dependsOn: [acrPullIdentity]
}

resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: appName
  location: location
  tags: {
    'azd-service-name': serviceName
    'azd-env-name': environmentName
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${acrPullIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironment.id
    configuration: {
      ingress: {
        external: true
        targetPort: bootstrapPort
        transport: 'http'
      }
      registries: [
        {
          server: containerRegistry.properties.loginServer
          identity: acrPullIdentity.id
        }
      ]
      secrets: [
        {
          name: 'postgres-password'
          value: postgresPassword
        }
      ]
    }
    template: {
      containers: [
        {
          name: serviceName
          image: bootstrapImage
          env: [
            { name: 'POSTGRES_HOST', value: postgresHost }
            { name: 'POSTGRES_DB', value: postgresDb }
            { name: 'POSTGRES_USER', value: postgresUser }
            { name: 'POSTGRES_PASSWORD', secretRef: 'postgres-password' }
          ]
          resources: {
            cpu: json('0.25')
            memory: '0.5Gi'
          }
        }
      ]
      scale: {
        minReplicas: 1
        maxReplicas: environmentType == 'dev' ? 1 : 3
      }
    }
  }
  dependsOn: [acrPullRole, containerAppsEnvironment, containerRegistry]
}

output containerRegistryLoginServer string = containerRegistry.properties.loginServer
output containerRegistryName string = containerRegistry.name
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
