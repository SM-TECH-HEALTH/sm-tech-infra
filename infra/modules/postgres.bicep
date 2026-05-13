param location string
param environmentName string

@allowed(['dev', 'prod'])
param environmentType string

param databaseName string
param administratorLogin string

@secure()
param administratorLoginPassword string

var isDev = environmentType == 'dev'
var haMode = 'Disabled'
var storageSizeGB = isDev ? 32 : 128

var serverName = 'pgsql-${take(toLower(uniqueString(subscription().id, resourceGroup().id, environmentName, location)), 18)}'

resource flexibleServer 'Microsoft.DBforPostgreSQL/flexibleServers@2024-08-01' = {
  name: serverName
  location: location
  sku: {
    name: 'Standard_B1ms'
    tier: 'Burstable'
  }
  properties: {
    version: '16'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorLoginPassword
    storage: {
      storageSizeGB: storageSizeGB
    }
    highAvailability: {
      mode: haMode
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
    authConfig: {
      activeDirectoryAuth: 'Disabled'
      passwordAuth: 'Enabled'
    }
    backup: {
      backupRetentionDays: isDev ? 7 : 14
      geoRedundantBackup: 'Disabled'
    }
  }
}

resource firewallAllowAzure 'Microsoft.DBforPostgreSQL/flexibleServers/firewallRules@2024-08-01' = {
  parent: flexibleServer
  name: 'AllowAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}

resource database 'Microsoft.DBforPostgreSQL/flexibleServers/databases@2024-08-01' = {
  parent: flexibleServer
  name: databaseName
  properties: {
    charset: 'UTF8'
    collation: 'en_US.utf8'
  }
}

output postgresHost string = flexibleServer.properties.fullyQualifiedDomainName
output postgresDatabaseName string = database.name
output postgresAdminUser string = administratorLogin
