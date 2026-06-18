#Requires -Version 5.1
<#
  MailGuard - Step 1 of 2: register the read-only sign-in app (Microsoft 365)

  What this does (safe to re-run - it reuses the same app):
    1. Installs the PowerShell modules needed for BOTH MailGuard setup steps
    2. Signs you in to Microsoft 365 with a device code (works on Windows and Mac,
       and avoids the sign-in broker errors seen with the interactive browser flow)
    3. Registers a read-only app, grants admin consent, and creates a client secret
    4. Prints your Tenant ID / Client ID / Client Secret and SAVES them to a file

  Then: paste those three values into MailGuard, and run
        MailGuard-2-ExchangeRole.ps1 to finish the Exchange permission.

  HOW TO RUN (run as a FILE - do not paste the lines one by one):
    Windows:  right-click the file > "Run with PowerShell"   (nothing to install)
    Mac:      install PowerShell once:  brew install --cask powershell
              then run:  pwsh ./MailGuard-1-Setup.ps1
    Linux:    install PowerShell 7, then run:  pwsh ./MailGuard-1-Setup.ps1
#>

$ErrorActionPreference = 'Stop'
$AppName = 'MailGuard Scanner'

function Fail($msg) { Write-Host ''; Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# PS 5.1 has no $IsWindows and only runs on Windows; PS 7 defines it.
$onWindows = ($null -eq $IsWindows) -or $IsWindows

Write-Host ''
Write-Host '=========================================================='
Write-Host '  MailGuard - Step 1 of 2: register the sign-in app'
Write-Host '=========================================================='

# 1. Modules for BOTH steps -------------------------------------------------
Write-Host ''
Write-Host '[1/5] Checking required PowerShell modules...' -ForegroundColor Cyan
foreach ($m in 'Microsoft.Graph.Authentication','Microsoft.Graph.Applications','ExchangeOnlineManagement') {
  if (Get-Module -ListAvailable -Name $m) {
    Write-Host "      $m - already installed"
  } else {
    Write-Host "      $m - installing..."
    try {
      Install-Module $m -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
    } catch {
      Fail "Could not install '$m'. Close all other PowerShell windows, open a fresh one, and run this script again. ($($_.Exception.Message))"
    }
  }
}

# 2. Sign in (device code: no broker, cross-platform) -----------------------
Write-Host ''
Write-Host '[2/5] Sign in to Microsoft 365...' -ForegroundColor Cyan
Write-Host '      A URL and a one-time code will appear below. Open the URL in a browser,'
Write-Host '      enter the code, and sign in as a Global Administrator.'
Import-Module Microsoft.Graph.Authentication
try {
  # Do NOT capture this into a variable - that suppresses the device-code prompt.
  Connect-MgGraph -Scopes 'Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','Directory.Read.All' -UseDeviceAuthentication -NoWelcome
} catch {
  Fail "Sign-in failed or was cancelled. ($($_.Exception.Message))"
}
$TenantId = (Get-MgContext).TenantId
if (-not $TenantId) { Fail 'Could not read the tenant after sign-in.' }

# 3. Register / update the read-only app ------------------------------------
Write-Host ''
Write-Host '[3/5] Registering the read-only app...' -ForegroundColor Cyan
Import-Module Microsoft.Graph.Applications
$graphPerms = 'Directory.Read.All','Policy.Read.All','SecurityEvents.Read.All','InformationProtectionPolicy.Read.All','MailboxSettings.Read','Reports.Read.All','Organization.Read.All'
$exoPerms   = 'Exchange.ManageAsApp'
$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$exoSp   = Get-MgServicePrincipal -Filter "appId eq '00000002-0000-0ff1-ce00-000000000000'"
function Get-RoleIds($sp,$names){ $ids=@(); foreach($n in $names){ $r=$sp.AppRoles | Where-Object { $_.Value -eq $n -and $_.AllowedMemberTypes -contains 'Application' } | Select-Object -First 1; if($r){ $ids += $r.Id } }; ,$ids }
$gIds = Get-RoleIds $graphSp $graphPerms
$eIds = Get-RoleIds $exoSp   $exoPerms
$rra = @(
  @{ ResourceAppId = $graphSp.AppId; ResourceAccess = @($gIds | ForEach-Object { @{ Id = $_; Type = 'Role' } }) },
  @{ ResourceAppId = $exoSp.AppId;   ResourceAccess = @($eIds | ForEach-Object { @{ Id = $_; Type = 'Role' } }) }
)
$app = Get-MgApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($app) {
  Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $rra
} else {
  $app = New-MgApplication -DisplayName $AppName -SignInAudience 'AzureADMyOrg' -RequiredResourceAccess $rra
}
$ClientId = $app.AppId
Start-Sleep 10
$sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'" -ErrorAction SilentlyContinue
if (-not $sp) { $sp = New-MgServicePrincipal -AppId $ClientId; Start-Sleep 5 }

# 4. Grant admin consent ----------------------------------------------------
Write-Host ''
Write-Host '[4/5] Granting admin consent...' -ForegroundColor Cyan
foreach ($id in $gIds) { try { New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $graphSp.Id -AppRoleId $id | Out-Null } catch {} }
foreach ($id in $eIds) { try { New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $exoSp.Id   -AppRoleId $id | Out-Null } catch {} }

# 5. Create a client secret -------------------------------------------------
Write-Host ''
Write-Host '[5/5] Creating a client secret (valid 24 months)...' -ForegroundColor Cyan
$secret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{ DisplayName = 'MailGuard'; EndDateTime = (Get-Date).AddMonths(24) }
$ClientSecret = $secret.SecretText
$expiry = (Get-Date).AddMonths(24).ToString('yyyy-MM-dd')

# Save to a file (includes the SP Object ID that Step 2 needs) ---------------
$outFile = Join-Path (Get-Location) 'mailguard-credentials.txt'
@"
MailGuard Microsoft 365 credentials
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')

Tenant ID:      $TenantId
Client ID:      $ClientId
Client Secret:  $ClientSecret
Secret expires: $expiry

# Used by Step 2 (MailGuard-2-ExchangeRole.ps1) - do not edit:
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
Write-Host 'The client secret is shown only once. Paste these into MailGuard now, then' -ForegroundColor Yellow
Write-Host 'delete the file above once MailGuard shows the tenant connected.'          -ForegroundColor Yellow
Write-Host ''
Write-Host 'NEXT: run  MailGuard-2-ExchangeRole.ps1  to finish the Exchange permission.' -ForegroundColor Green
exit 0
