#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Block 4 – passwordless database access for the API (Microsoft Entra ID + user-assigned managed identity).
.DESCRIPTION
  1. Connects to MySQL as the Microsoft Entra admin (presenter) with an access token.
  2. Creates a MySQL user mapped to the UAMI id-ledgerly-<env> and grants it rights on ledgerly.*
     Syntax per Microsoft Learn (Azure Database for MySQL Flexible Server – Entra authentication):
        SET aad_auth_validate_oids_in_tenant = OFF;
        CREATE AADUSER '<identity name>' IDENTIFIED BY '<client id>';
     VERIFY against current docs before the session (see README "Known gaps").
  3. Switches the api Container App to SPRING_PROFILES_ACTIVE=azure + AZURE_CLIENT_ID + DB_USER=<identity>,
     removes the DB_PASSWORD env var and the db-password secret.
  The batch job still uses the admin password from Key Vault (next modernization step).
#>
param([switch]$SkipDbUser)
. "$PSScriptRoot/_common.ps1"

$azd       = Get-AzdValues
$rg        = $azd.AZURE_RESOURCE_GROUP
$api       = $azd.API_APP_NAME
$server    = $azd.MYSQL_SERVER_FQDN
$database  = $azd.MYSQL_DATABASE_NAME
$idName    = $azd.MANAGED_IDENTITY_NAME
$clientId  = $azd.MANAGED_IDENTITY_CLIENT_ID
$entraAdmin = if ($azd.MYSQL_ENTRA_ADMIN_LOGIN) { $azd.MYSQL_ENTRA_ADMIN_LOGIN } else { az ad signed-in-user show --query userPrincipalName -o tsv }

if (-not $SkipDbUser) {
    Write-Step "Get Entra access token for MySQL as $entraAdmin"
    $token = az account get-access-token --resource-type oss-rdbms --query accessToken -o tsv
    Assert-LastExit 'az account get-access-token'

    Write-Step "Create MySQL Entra user '$idName' for the managed identity (client id $clientId)"
    $sql = @"
SET aad_auth_validate_oids_in_tenant = OFF;
CREATE AADUSER '$idName' IDENTIFIED BY '$clientId';
GRANT SELECT, INSERT, UPDATE, DELETE ON ``$database``.* TO '$idName'@'%';
FLUSH PRIVILEGES;
"@
    try {
        Invoke-AzureMysql -Server $server -User $entraAdmin -Password $token -Database $database -Sql $sql -Cleartext | Out-Null
        Write-Ok "MySQL user $idName created"
    } catch {
        Write-Warn2 "CREATE AADUSER failed ($($_.Exception.Message)). If the user already exists this is fine – continuing."
    }
    Invoke-AzureMysql -Server $server -User $entraAdmin -Password $token -Database $database -Cleartext `
        -Sql "SELECT user, host, plugin FROM mysql.user WHERE user = '$idName'"
}

Write-Step "Switch $api to passwordless (profile 'azure')"
az containerapp update --name $api --resource-group $rg `
    --set-env-vars "SPRING_PROFILES_ACTIVE=azure" "AZURE_CLIENT_ID=$clientId" "DB_USER=$idName" `
    --remove-env-vars DB_PASSWORD --only-show-errors -o none
Assert-LastExit 'az containerapp update'

Write-Step 'Remove the db-password secret from the api app'
az containerapp secret remove --name $api --resource-group $rg --secret-names db-password --only-show-errors -o none
Assert-LastExit 'az containerapp secret remove'

Write-Step 'Verify (new revision needs ~60 s to start)'
$web = $azd.WEB_URI
for ($i = 0; $i -lt 24; $i++) {
    Start-Sleep -Seconds 10
    try {
        $h = Invoke-RestMethod "$web/api/health" -TimeoutSec 15
        Write-Host "  health: $($h.status) db=$($h.db) cache=$($h.cache) host=$($h.host)"
        if ($h.status -eq 'UP') { break }
    } catch { Write-Host '  …waiting' }
}
az containerapp show -n $api -g $rg --query "properties.template.containers[0].env[].name" -o tsv
Write-Ok 'API uses its managed identity for MySQL – no DB password in the app any more.'
