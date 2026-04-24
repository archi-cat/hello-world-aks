<#
.SYNOPSIS
    Grants the API's Workload Identity (UAMI) least-privilege access to the SQL database.

.DESCRIPTION
    Connects to the SQL database using an Azure AD access token obtained from
    the Azure CLI and:
      1. Creates an external user mapped to the UAMI
      2. Grants db_datareader — allows SELECT on all tables
      3. Grants db_datawriter — allows INSERT, UPDATE, DELETE on all tables

    This script is idempotent — safe to run multiple times.

.NOTES
    The UAMI is identified by its display name in Entra ID, which matches
    the name given to the azurerm_user_assigned_identity resource in Terraform.
    Requires the runner to be authenticated via azure/login before running.
#>

param (
    [Parameter(Mandatory)] [string] $SqlServerFqdn,
    [Parameter(Mandatory)] [string] $SqlDatabaseName,
    [Parameter(Mandatory)] [string] $WorkloadIdentityName
)

# Install SqlServer module if not already present
if (-not (Get-Module -ListAvailable -Name SqlServer)) {
    Write-Host "Installing SqlServer module..."
    Install-Module -Name SqlServer -Force -AllowClobber -Scope CurrentUser
}

Import-Module SqlServer

# Obtain an Azure AD access token for the SQL Database resource
Write-Host "Obtaining Azure AD access token for SQL Database..."
$response    = az account get-access-token --resource https://database.windows.net/
$accessToken = ($response | ConvertFrom-Json).accessToken

if (-not $accessToken) {
    Write-Error "Failed to obtain Azure AD access token. Ensure azure/login step has run."
    exit 1
}

$connectionString = "Server=$SqlServerFqdn;Database=$SqlDatabaseName;" +
                    "Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

Write-Host "Connecting to $SqlServerFqdn / $SqlDatabaseName via Azure AD token..."

try {
    $connection              = New-Object System.Data.SqlClient.SqlConnection $connectionString
    $connection.AccessToken  = $accessToken
    $connection.Open()
    Write-Host "Connected successfully."

    # Check if the user already exists
    $checkCmd   = New-Object System.Data.SqlClient.SqlCommand `
        "SELECT COUNT(*) FROM sys.database_principals WHERE name = '$WorkloadIdentityName'", `
        $connection
    $userExists = $checkCmd.ExecuteScalar()

    if ($userExists -eq 0) {
        Write-Host "Creating external user for Workload Identity: $WorkloadIdentityName"
        $createCmd = New-Object System.Data.SqlClient.SqlCommand `
            "CREATE USER [$WorkloadIdentityName] FROM EXTERNAL PROVIDER", $connection
        $createCmd.ExecuteNonQuery() | Out-Null
        Write-Host "User created."
    } else {
        Write-Host "User $WorkloadIdentityName already exists — skipping CREATE USER."
    }

    Write-Host "Granting db_datareader to $WorkloadIdentityName..."
    $readerCmd = New-Object System.Data.SqlClient.SqlCommand `
        "ALTER ROLE db_datareader ADD MEMBER [$WorkloadIdentityName]", $connection
    $readerCmd.ExecuteNonQuery() | Out-Null

    Write-Host "Granting db_datawriter to $WorkloadIdentityName..."
    $writerCmd = New-Object System.Data.SqlClient.SqlCommand `
        "ALTER ROLE db_datawriter ADD MEMBER [$WorkloadIdentityName]", $connection
    $writerCmd.ExecuteNonQuery() | Out-Null

    Write-Host "Done. $WorkloadIdentityName has been granted db_datareader and db_datawriter."

} catch {
    Write-Error "Script failed: $_"
    exit 1
} finally {
    if ($connection.State -eq 'Open') {
        $connection.Close()
    }
}