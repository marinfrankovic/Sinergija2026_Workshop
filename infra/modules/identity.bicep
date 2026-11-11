// User-assigned managed identities.
//  - id-ledgerly-<env>        : used by web/api/batch (AcrPull, Key Vault secrets, MySQL Entra user)
//  - id-ledgerly-mysql-<env>  : assigned to the MySQL server itself; required for Microsoft Entra auth on
//                               Flexible Server (needs Microsoft Graph read permissions – see README "Known gaps")
param location string
param tags object
param appIdentityName string
param mysqlIdentityName string

resource appId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: appIdentityName
  location: location
  tags: tags
}

resource mysqlId 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: mysqlIdentityName
  location: location
  tags: tags
}

output appIdentityId string = appId.id
output appIdentityName string = appId.name
output appIdentityClientId string = appId.properties.clientId
output appIdentityPrincipalId string = appId.properties.principalId
output mysqlIdentityId string = mysqlId.id
output mysqlIdentityPrincipalId string = mysqlId.properties.principalId
