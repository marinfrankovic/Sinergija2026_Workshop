// Azure Cache for Redis Basic C0 (TLS only, port 6380). Access key -> Key Vault secret "redis-password".
// Alternative for new workloads: Azure Managed Redis (Microsoft.Cache/redisEnterprise) – supports Entra auth.
param location string
param tags object
param name string
param keyVaultName string

resource redis 'Microsoft.Cache/redis@2024-03-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'Basic'
      family: 'C'
      capacity: 0
    }
    enableNonSslPort: false
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource redisSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'redis-password'
  properties: {
    value: redis.listKeys().primaryKey
    contentType: 'text/plain'
  }
}

output name string = redis.name
output hostName string = redis.properties.hostName
output sslPort int = redis.properties.sslPort
output passwordSecretUri string = redisSecret.properties.secretUri
