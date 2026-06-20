#Requires -Version 5.1
<#
  MailGuard - One-Click sign-in app setup (Microsoft 365)

  Registers the sign-in app that lets your admins connect to MailGuard just by
  signing in (Connect > One-Click OAuth). Safe to re-run - it reuses the same app.

  What this does:
    1. Installs the PowerShell modules it needs (first run only)
    2. Signs you in to Microsoft 365 with a device code (works on Windows and Mac,
       and avoids the sign-in broker errors seen with the interactive browser flow)
    3. Registers a sign-in app with the MailGuard localhost callback and the
       delegated permissions the consent flow needs, then creates a client secret
    4. Prints your Tenant ID / Client ID / Client Secret and SAVES them to a file

  Then: paste those three values into MailGuard (Connect > One-Click OAuth) and connect.

  HOW TO RUN (run as a FILE - do not paste the lines one by one):
    Windows:  right-click the file > "Run with PowerShell"   (nothing to install)
    Mac:      install PowerShell once:  brew install --cask powershell
              then run:  pwsh ./MailGuard-OAuth-Setup.ps1
    Linux:    install PowerShell 7, then run:  pwsh ./MailGuard-OAuth-Setup.ps1
#>

$ErrorActionPreference = 'Stop'
$AppName     = 'MailGuard Sign-In'
$RedirectUri = 'http://localhost:8000/api/auth/callback'

function Fail($msg) { Write-Host ''; Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# PS 5.1 has no $IsWindows and only runs on Windows; PS 7 defines it.
$onWindows = ($null -eq $IsWindows) -or $IsWindows

Write-Host ''
Write-Host '=========================================================='
Write-Host '  MailGuard - One-Click sign-in app setup'
Write-Host '=========================================================='

# 1. Modules ----------------------------------------------------------------
Write-Host ''
Write-Host '[1/4] Installing the components MailGuard needs (first run only)...' -ForegroundColor Cyan
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
  Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Scope CurrentUser -Force -ErrorAction SilentlyContinue | Out-Null
}
if ((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue).InstallationPolicy -ne 'Trusted') {
  try { Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue } catch {}
}
foreach ($m in 'Microsoft.Graph.Authentication','Microsoft.Graph.Applications','ExchangeOnlineManagement') {
  if (Get-Module -ListAvailable -Name $m) { continue }
  Write-Host "      adding $m..." -ForegroundColor DarkGray
  try {
    Install-Module $m -Scope CurrentUser -Force -AllowClobber -Repository PSGallery -ErrorAction Stop | Out-Null
  } catch {
    Fail "Could not install '$m'. Close all other PowerShell windows, open a fresh one, and run this script again. ($($_.Exception.Message))"
  }
}
Write-Host '      all components ready.' -ForegroundColor DarkGray

# 2. Sign in (device code: no broker, cross-platform) -----------------------
Write-Host ''
Write-Host '[2/4] Sign in to Microsoft 365...' -ForegroundColor Cyan
Write-Host '      A URL and a one-time code will appear below. Open the URL in a browser,'
Write-Host '      enter the code, and sign in as a Global Administrator.'
Import-Module Microsoft.Graph.Authentication
try {
  # Do NOT capture this into a variable - that suppresses the device-code prompt.
  Connect-MgGraph -Scopes 'Application.ReadWrite.All','Directory.Read.All' -UseDeviceAuthentication -NoWelcome
} catch {
  Fail "Sign-in failed or was cancelled. ($($_.Exception.Message))"
}
$TenantId = (Get-MgContext).TenantId
if (-not $TenantId) { Fail 'Could not read the tenant after sign-in.' }

# 3. Register / update the sign-in app --------------------------------------
Write-Host ''
Write-Host '[3/4] Registering the sign-in app...' -ForegroundColor Cyan
Import-Module Microsoft.Graph.Applications
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$delegated = 'Directory.Read.All','Policy.Read.All','AppRoleAssignment.ReadWrite.All','Application.ReadWrite.All'
$scopes = @()
foreach ($n in $delegated) {
  $s = $graphSp.Oauth2PermissionScopes | Where-Object { $_.Value -eq $n } | Select-Object -First 1
  if ($s) { $scopes += @{ Id = $s.Id; Type = 'Scope' } }
}
$rra = @( @{ ResourceAppId = $graphSp.AppId; ResourceAccess = $scopes } )
$web = @{ RedirectUris = @($RedirectUri) }
$app = Get-MgApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($app) {
  Update-MgApplication -ApplicationId $app.Id -Web $web -RequiredResourceAccess $rra
} else {
  $app = New-MgApplication -DisplayName $AppName -SignInAudience 'AzureADMyOrg' -Web $web -RequiredResourceAccess $rra
}
$ClientId = $app.AppId
Start-Sleep 5
$sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'" -ErrorAction SilentlyContinue
if (-not $sp) { $sp = New-MgServicePrincipal -AppId $ClientId; Start-Sleep 5 }

# 4. Create a client secret -------------------------------------------------
Write-Host ''
Write-Host '[4/4] Creating a client secret (valid 24 months)...' -ForegroundColor Cyan
$secret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{ DisplayName = 'MailGuard'; EndDateTime = (Get-Date).AddMonths(24) }
$ClientSecret = $secret.SecretText
$expiry = (Get-Date).AddMonths(24).ToString('yyyy-MM-dd')

# Save to a file ------------------------------------------------------------
$outFile = Join-Path (Get-Location) 'mailguard-signin-credentials.txt'
@"
MailGuard One-Click sign-in app credentials
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')

Tenant ID:      $TenantId
Client ID:      $ClientId
Client Secret:  $ClientSecret
Secret expires: $expiry
Redirect URI:   $RedirectUri

# Used by the Exchange role step (MailGuard-OAuth-ExchangeRole.ps1) - do not edit:
SP_OBJECT_ID:   $($sp.Id)
APP_NAME:       $AppName
"@ | Set-Content -Path $outFile -Encoding UTF8

# Lock the file down to the current user (best effort)
try {
  if ($onWindows) { icacls $outFile /inheritance:r /grant:r "$($env:USERNAME):F" | Out-Null }
  else            { chmod 600 $outFile }
} catch {}

Write-Host ''
Write-Host '=====================  COPY THESE INTO MAILGUARD  =====================' -ForegroundColor Green
Write-Host ('Tenant ID:      ' + $TenantId)
Write-Host ('Client ID:      ' + $ClientId)
Write-Host ('Client Secret:  ' + $ClientSecret)
Write-Host '======================================================================' -ForegroundColor Green
Write-Host ''
Write-Host "Saved to: $outFile" -ForegroundColor Cyan
Write-Host ('Redirect URI is preset to ' + $RedirectUri) -ForegroundColor DarkGray
Write-Host 'The client secret is shown only once. Paste these into MailGuard now, then' -ForegroundColor Yellow
Write-Host 'delete the file above once MailGuard shows the tenant connected.'          -ForegroundColor Yellow
exit 0
