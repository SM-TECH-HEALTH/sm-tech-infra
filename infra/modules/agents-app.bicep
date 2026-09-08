@description('Regiao do Container App dos agentes.')
param location string

@description('Nome do ambiente azd.')
param environmentName string

@allowed([
  'dev'
  'prod'
])
param environmentType string = 'dev'

@description('Nome do Container App dos agentes.')
param containerAppName string

@description('Id do Container Apps Environment ja provisionado.')
param containerAppsEnvironmentId string

@description('Imagem inicial. O pipeline troca para ghcr.io/sm-tech-health/sm-tech-agents.')
param initialContainerImage string = 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'

@secure()
param jwtSecretKey string

@description('Issuer JWT do sm-tech-back.')
param jwtIssuer string = 'smtech-hospital-api'

@description('Audience JWT do SPA.')
param jwtAudience string = 'smtech-hospital-frontend'

@description('Origem CORS do SPA.')
param corsAllowedOrigin string

@description('Endpoint Azure OpenAI (https://....openai.azure.com/).')
param azureOpenAiEndpoint string

@description('Nome da conta Cognitive Services (OpenAI) ja provisionada, no mesmo resource group. A chave e lida daqui via listKeys() para nao precisar passar um output secure atraves de um modulo condicional (BCP426).')
param azureOpenAiAccountName string

@description('Nome do deployment no Foundry.')
param azureOpenAiDeployment string = 'gpt-4o'

resource openAiAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: azureOpenAiAccountName
}

resource agentsApp 'Microsoft.App/containerApps@2023-05-01' = {
  name: containerAppName
  location: location
  tags: {
    'azd-env-name': environmentName
    'azd-service-name': 'agents'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    managedEnvironmentId: containerAppsEnvironmentId
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
          name: 'jwt-secret-key'
          value: jwtSecretKey
        }
        {
          name: 'azure-openai-key'
          value: openAiAccount.listKeys().key1
        }
      ]
    }
    template: {
      containers: [
        {
          name: 'agents'
          image: initialContainerImage
          env: [
            {
              name: 'ENVIRONMENT'
              value: environmentType == 'prod' ? 'production' : 'staging'
            }
            {
              name: 'LLM_PROVIDER'
              value: 'azure'
            }
            {
              name: 'FONTE_DADOS'
              value: 'mock'
            }
            {
              name: 'AZURE_OPENAI_ENDPOINT'
              value: azureOpenAiEndpoint
            }
            {
              name: 'AZURE_OPENAI_API_KEY'
              secretRef: 'azure-openai-key'
            }
            {
              name: 'AZURE_OPENAI_DEPLOYMENT'
              value: azureOpenAiDeployment
            }
            {
              name: 'AZURE_OPENAI_API_VERSION'
              value: '2024-10-21'
            }
            {
              name: 'JWT_SECRET'
              secretRef: 'jwt-secret-key'
            }
            {
              name: 'JWT_ISSUER'
              value: jwtIssuer
            }
            {
              name: 'JWT_AUDIENCE'
              value: jwtAudience
            }
            {
              name: 'CORS_ORIGINS'
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
        minReplicas: 0
        maxReplicas: environmentType == 'prod' ? 2 : 1
      }
    }
  }
}

output containerAppName string = agentsApp.name
output agentsUri string = 'https://${agentsApp.properties.configuration.ingress.fqdn}'
