// Azure Database for MySQL – Flexible Server 8.0.21, Burstable B2s, 32 GB.
// Public access + firewall (workshop simplicity). Production: VNet integration or private endpoint.
// Child resources are chained with dependsOn because Flexible Server rejects
// concurrent configuration operations ("ServerBusy").
param location string
param tags object
param name string
param administratorLogin string
@secure()
param administratorPassword string
param databaseName string
param presenterIp string = ''
param serverIdentityId string
param entraAdminLogin string = ''
param entraAdminObjectId string = ''
param logAnalyticsWorkspaceId string

resource server 'Microsoft.DBforMySQL/flexibleServers@2023-12-30' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard_B2s'
    tier: 'Burstable'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${serverIdentityId}': {}
    }
  }
  properties: {
    version: '8.0.21'
    administratorLogin: administratorLogin
    administratorLoginPassword: administratorPassword // password auth stays enabled (batch job + migration)
    storage: {
      storageSizeGB: 32
      autoGrow: 'Enabled'
    }
    backup: {
      backupRetentionDays: 7
      geoRedundantBackup: 'Disabled'
    }
    highAvailability: {
      mode: 'Disabled'
    }
    network: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

resource db 'Microsoft.DBforMySQL/flexibleServers/databases@2023-12-30' = {
  parent: server
  name: databaseName
  properties: {
    charset: 'utf8mb4'
    collation: 'utf8mb4_0900_ai_ci'
  }
}

// 0.0.0.0 - 0.0.0.0 = "Allow public access from any Azure service within Azure to this server".
// Fault 2 deletes exactly this rule.
resource fwAzure 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-12-30' = {
  parent: server
  name: 'AllowAllAzureServices'
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
  dependsOn: [
    db
  ]
}

resource fwPresenter 'Microsoft.DBforMySQL/flexibleServers/firewallRules@2023-12-30' = if (!empty(presenterIp)) {
  parent: server
  name: 'AllowPresenterIp'
  properties: {
    startIpAddress: presenterIp
    endIpAddress: presenterIp
  }
  dependsOn: [
    fwAzure
  ]
}

resource cfgSlowLog 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-30' = {
  parent: server
  name: 'slow_query_log'
  properties: {
    value: 'ON'
    source: 'user-override'
  }
  dependsOn: [
    fwPresenter
  ]
}

resource cfgLongQuery 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-30' = {
  parent: server
  name: 'long_query_time'
  properties: {
    value: '2'
    source: 'user-override'
  }
  dependsOn: [
    cfgSlowLog
  ]
}

// Also log full scans that are individually < 2 s (the N+1 report queries) – makes fault 3 evidence reliable.
resource cfgNoIndex 'Microsoft.DBforMySQL/flexibleServers/configurations@2023-12-30' = {
  parent: server
  name: 'log_queries_not_using_indexes'
  properties: {
    value: 'ON'
    source: 'user-override'
  }
  dependsOn: [
    cfgLongQuery
  ]
}

resource entraAdmin 'Microsoft.DBforMySQL/flexibleServers/administrators@2023-12-30' = if (!empty(entraAdminLogin) && !empty(entraAdminObjectId)) {
  parent: server
  name: 'ActiveDirectory'
  properties: {
    administratorType: 'ActiveDirectory'
    login: entraAdminLogin
    sid: entraAdminObjectId
    tenantId: subscription().tenantId
    identityResourceId: serverIdentityId
  }
  dependsOn: [
    cfgNoIndex
  ]
}

resource diag 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'diag-mysql-to-log'
  scope: server
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      {
        category: 'MySqlSlowLogs'
        enabled: true
      }
    ]
  }
}

output name string = server.name
output fqdn string = server.properties.fullyQualifiedDomainName
