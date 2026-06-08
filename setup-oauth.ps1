<#
.SYNOPSIS
  MailGuard - register the One-Click sign-in app in your Microsoft 365 tenant.

.DESCRIPTION
  Registers a single-tenant Entra application with the MailGuard localhost
  callback and the delegated Microsoft Graph permissions the consent flow
  needs, creates a client secret, and prints the Client ID + Client Secret to
  paste into MailGuard (Connect -> One-Click OAuth). Safe to run more than once.

.PARAMETER AppName
  Display name for the app registration. Default: "MailGuard Sign-In".

.PARAMETER RedirectUri
  OAuth callback URL. Must match what MailGuard uses.
  Default: http://localhost:8000/api/auth/callback

.PARAMETER SecretMonths
  Client secret lifetime in months. Default: 24.

.EXAMPLE
  ./setup-oauth.ps1

.EXAMPLE
  ./setup-oauth.ps1 -RedirectUri "http://localhost:9000/api/auth/callback" -SecretMonths 12
#>
[CmdletBinding()]
param(
  [string]$AppName      = "MailGuard Sign-In",
  [string]$RedirectUri  = "http://localhost:8000/api/auth/callback",
  [int]   $SecretMonths = 24
)

$ErrorActionPreference = "Stop"
$GraphAppId = "00000003-0000-0000-c000-000000000000"

Write-Host ""
Write-Host "[1/4] Installing prerequisites (one-time)..." -ForegroundColor Cyan
foreach ($m in "Microsoft.Graph.Authentication", "Microsoft.Graph.Applications") {
  if (-not (Get-Module -ListAvailable -Name $m)) {
    Install-Module $m -Scope CurrentUser -Force -AllowClobber
  }
}

Write-Host "[2/4] Sign in to Microsoft 365 if prompted..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "Application.ReadWrite.All", "Directory.Read.All" -NoWelcome
$TenantId = (Get-MgContext).TenantId

# Resolve the delegated Graph scopes the consent flow requests.
$graphSp = Get-MgServicePrincipal -Filter "appId eq '$GraphAppId'"
$delegated = @(
  "Directory.Read.All",
  "Policy.Read.All",
  "AppRoleAssignment.ReadWrite.All",
  "Application.ReadWrite.All"
)
$scopes = @()
foreach ($n in $delegated) {
  $s = $graphSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq $n } | Select-Object -First 1
  if ($s) { $scopes += @{ Id = $s.Id; Type = "Scope" } }
}
$rra = @( @{ ResourceAppId = $graphSp.AppId; ResourceAccess = $scopes } )

Write-Host "[3/4] Registering the sign-in app..." -ForegroundColor Cyan
$web = @{ RedirectUris = @($RedirectUri) }
$app = Get-MgApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($app) {
  Update-MgApplication -ApplicationId $app.Id -Web $web -RequiredResourceAccess $rra
}
else {
  $app = New-MgApplication -DisplayName $AppName -SignInAudience "AzureADMyOrg" -Web $web -RequiredResourceAccess $rra
}
$ClientId = $app.AppId

Start-Sleep -Seconds 5
if (-not (Get-MgServicePrincipal -Filter "appId eq '$ClientId'" -ErrorAction SilentlyContinue)) {
  New-MgServicePrincipal -AppId $ClientId | Out-Null
}

Write-Host "[4/4] Creating a client secret (valid $SecretMonths months)..." -ForegroundColor Cyan
$secret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{
  DisplayName = "MailGuard"
  EndDateTime = (Get-Date).AddMonths($SecretMonths)
}
$ClientSecret = $secret.SecretText

Write-Host ""
Write-Host "=====================  COPY THESE INTO MAILGUARD  =====================" -ForegroundColor Green
Write-Host ("Tenant ID:      " + $TenantId)
Write-Host ("Client ID:      " + $ClientId)
Write-Host ("Client Secret:  " + $ClientSecret)
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host "Redirect URI: $RedirectUri" -ForegroundColor DarkGray
Write-Host "The client secret is shown only once - copy it now." -ForegroundColor Yellow
