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

@description('Nome do Container App da API.')
param containerAppName string

@description('Nome do Container Apps Environment.')
param containerAppsEnvironmentName string

@description('Nome do Log Analytics Workspace.')
param logAnalyticsWorkspaceName string

@description('Imagem inicial do Container App. O pipeline troca para ghcr.io/sm-tech-health/sm-tech-back:<sha> apos o primeiro provision.')
param initialContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@secure()
@description('Connection string PostgreSQL usada pela API.')
param postgresConnectionString string

@secure()
@description('Chave JWT usada pela API.')
param jwtSecretKey string

@description('Origem permitida para CORS.')
param corsAllowedOrigin string

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

// Container App pega imagem publica do GHCR (ghcr.io/sm-tech-health/sm-tech-back).
// Por isso nao precisa de bloco `registries` com auth nem de role AcrPull.
// Importante: marque o pacote GHCR como Public apos o primeiro push.
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
          image: initialContainerImage
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

output containerAppName string = containerApp.name
output apiUri string = 'https://${containerApp.properties.configuration.ingress.fqdn}'
