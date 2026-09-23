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

@description('Dominio customizado da API (ex: api-demo.smtechsistemas.com.br). Vazio = nao expoe dominio custom, so o FQDN padrao do Container Apps.')
param apiCustomDomainName string = ''

@description('Resource ID do managed certificate (Microsoft.App/managedEnvironments/managedCertificates) do dominio customizado. Obrigatorio quando apiCustomDomainName nao esta vazio.')
param apiCustomDomainCertificateId string = ''

@description('Nome do Container App dos agentes (sm-tech-agents). Vazio = agentes desligados; a API expoe AgentesIa__Habilitado=false.')
param agentsContainerAppName string = ''

// Container Apps Environment sem Log Analytics. Para inspecionar logs no
// ambiente lab use `az containerapp logs show --follow` enquanto a app esta
// rodando. Para producao, reintroduzir o workspace.
resource containerAppsEnvironment 'Microsoft.App/managedEnvironments@2023-05-01' = {
  name: containerAppsEnvironmentName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  properties: {}
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
        // Declarado aqui para nao ser resetado a cada `azd provision`: sem isso,
        // o dominio custom some toda vez que o pipeline reprovisiona a infra
        // (ARM substitui o ingress inteiro pelo que esta no template).
        customDomains: !empty(apiCustomDomainName) ? [
          {
            name: apiCustomDomainName
            bindingType: 'SniEnabled'
            certificateId: apiCustomDomainCertificateId
          }
        ] : []
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
            // URL do sm-tech-agents montada a partir do dominio padrao do
            // Container Apps Environment (o FQDN de um Container App e sempre
            // <nome>.<defaultDomain>). A API repassa para o SPA em
            // /v1/assistentesia/config e usa para avisar recarga da base de
            // conhecimento.
            {
              name: 'AgentesIa__UrlBase'
              value: empty(agentsContainerAppName) ? '' : 'https://${agentsContainerAppName}.${containerAppsEnvironment.properties.defaultDomain}'
            }
            {
              name: 'AgentesIa__Habilitado'
              value: empty(agentsContainerAppName) ? 'false' : 'true'
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
output containerAppsEnvironmentId string = containerAppsEnvironment.id
