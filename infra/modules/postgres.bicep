@description('Regiao Azure do servidor PostgreSQL.')
param location string

@description('Nome do ambiente azd.')
param environmentName string

@description('Nome do PostgreSQL Flexible Server.')
param serverName string

@description('Nome do banco de dados da aplicacao.')
param databaseName string

@description('Login administrador do PostgreSQL.')
param administratorLogin string

@secure()
@description('Senha do administrador do PostgreSQL.')
param administratorLoginPassword string

@allowed([
  'dev'
  'prod'
])
@description('Tipo do ambiente para diferenciar armazenamento.')
param environmentType string = 'dev'

var storageSizeGB = environmentType == 'prod' ? 128 : 32

resource server 'Microsoft.DBforPostgreSQL/flexibleServers@2023-06-01-preview' = {
  name: serverName
  location: location
  tags: {
    'azd-env-name': environmentName
  }
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    publicNetworkAccess: 'Enabled'
    highAvailability: {
      mode: 'Disabled'
    }
    storage: {
      storageSizeGB: storageSizeGB
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: environmentType == 'prod' ? 14 : 7
      geoRedundantBackup: 'Disabled'
    }
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2023-06-01-preview' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

resource allowAzureServices 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2023-06-01-preview' = {
  parent: server
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

output host string = server.properties.fullyQualifiedDomainName
output databaseName string = database.name
output administratorLogin string = administratorLogin
