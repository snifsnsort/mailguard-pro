<#
================================================================
  MailGuard - automatic Microsoft 365 setup
================================================================
  WHAT THIS DOES
    Registers a READ-ONLY application in your Microsoft 365 tenant
    so MailGuard can scan your security configuration. It:
      1. Installs the PowerShell modules it needs (one-time)
      2. Signs you in to Microsoft 365
      3. Registers the app and its service principal
      4. Grants admin consent for read-only Graph + Exchange permissions
      5. Creates a client secret (valid 24 months)
      6. Assigns the "View-Only Organization Management" Exchange role
    Then it prints three values to paste into MailGuard:
      Tenant ID, Client ID, Client Secret

  HOW TO RUN (easiest)
    1. Open Azure Cloud Shell:  https://shell.azure.com
    2. If asked, choose "PowerShell"
    3. Upload this file (or paste its contents) and run:
         ./setup-m365.ps1
    You can also run it from a local PowerShell 7 prompt.

  NOTES
    - You must sign in as a Global Administrator.
    - The Exchange step may prompt a second sign-in.
    - Safe to run more than once (it updates the existing app).
    - This script only READS your tenant configuration. It never
      changes mail flow, users, or policies.
================================================================
#>

[CmdletBinding()]
param(
    [string]$AppName = 'MailGuard Scanner',
    [int]$SecretMonths = 24
)

$ErrorActionPreference = 'Stop'

function Write-Step($n, $msg) { Write-Host ""; Write-Host "[$n/6] $msg" -ForegroundColor Cyan }

# --- 1. Prerequisites -------------------------------------------------------
Write-Step 1 "Installing prerequisites (one-time)..."
$modules = 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Applications', 'ExchangeOnlineManagement'
foreach ($m in $modules) {
    if (-not (Get-Module -ListAvailable -Name $m)) {
        Write-Host "      Installing $m ..." -ForegroundColor DarkGray
        Install-Module $m -Scope CurrentUser -Force -AllowClobber
    }
}
Import-Module Microsoft.Graph.Authentication -ErrorAction SilentlyContinue
Import-Module Microsoft.Graph.Applications  -ErrorAction SilentlyContinue

# --- 2. Sign in to Graph ----------------------------------------------------
Write-Step 2 "Sign in to Microsoft 365 when prompted..."
Connect-MgGraph -Scopes 'Application.ReadWrite.All', 'AppRoleAssignment.ReadWrite.All', 'Directory.Read.All' -NoWelcome
$TenantId = (Get-MgContext).TenantId
Write-Host "      Tenant: $TenantId" -ForegroundColor DarkGray

# --- Permissions the scanner needs (application roles, all read-only) -------
$graphPerms = @(
    'Directory.Read.All',
    'Policy.Read.All',
    'SecurityEvents.Read.All',
    'InformationProtectionPolicy.Read.All',
    'MailboxSettings.Read',
    'Reports.Read.All',
    'Organization.Read.All'
)
$exoPerms = @('Exchange.ManageAsApp')

$graphSp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"   # Microsoft Graph
$exoSp   = Get-MgServicePrincipal -Filter "appId eq '00000002-0000-0ff1-ce00-000000000000'"   # Office 365 Exchange Online

function Get-RoleIds($sp, $names) {
    $ids = @()
    foreach ($n in $names) {
        $r = $sp.AppRoles | Where-Object { $_.Value -eq $n -and $_.AllowedMemberTypes -contains 'Application' } | Select-Object -First 1
        if ($r) { $ids += $r.Id }
        else { Write-Host "      (skipping unknown permission: $n)" -ForegroundColor DarkYellow }
    }
    , $ids
}
$gIds = Get-RoleIds $graphSp $graphPerms
$eIds = Get-RoleIds $exoSp   $exoPerms

$rra = @(
    @{ ResourceAppId = $graphSp.AppId; ResourceAccess = @($gIds | ForEach-Object { @{ Id = $_; Type = 'Role' } }) },
    @{ ResourceAppId = $exoSp.AppId;   ResourceAccess = @($eIds | ForEach-Object { @{ Id = $_; Type = 'Role' } }) }
)

# --- 3. Register / update the app ------------------------------------------
Write-Step 3 "Registering the read-only app '$AppName'..."
$app = Get-MgApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($app) {
    Update-MgApplication -ApplicationId $app.Id -RequiredResourceAccess $rra
    Write-Host "      Updated existing app." -ForegroundColor DarkGray
}
else {
    $app = New-MgApplication -DisplayName $AppName -SignInAudience 'AzureADMyOrg' -RequiredResourceAccess $rra
    Write-Host "      Created new app." -ForegroundColor DarkGray
}
$ClientId = $app.AppId
Start-Sleep -Seconds 10   # let the app propagate

$sp = Get-MgServicePrincipal -Filter "appId eq '$ClientId'" -ErrorAction SilentlyContinue
if (-not $sp) { $sp = New-MgServicePrincipal -AppId $ClientId; Start-Sleep -Seconds 5 }

# --- 4. Grant admin consent -------------------------------------------------
Write-Step 4 "Granting admin consent..."
foreach ($id in $gIds) {
    try { New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $graphSp.Id -AppRoleId $id -ErrorAction Stop | Out-Null } catch {}
}
foreach ($id in $eIds) {
    try { New-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $sp.Id -PrincipalId $sp.Id -ResourceId $exoSp.Id -AppRoleId $id -ErrorAction Stop | Out-Null } catch {}
}

# --- 5. Client secret -------------------------------------------------------
Write-Step 5 "Creating a client secret (valid $SecretMonths months)..."
$secret = Add-MgApplicationPassword -ApplicationId $app.Id -PasswordCredential @{
    DisplayName = 'MailGuard'
    EndDateTime = (Get-Date).AddMonths($SecretMonths)
}
$ClientSecret = $secret.SecretText

# --- 6. Exchange role -------------------------------------------------------
Write-Step 6 "Assigning the Exchange read-only role (sign in again if asked)..."
Import-Module ExchangeOnlineManagement
Connect-ExchangeOnline -ShowBanner:$false | Out-Null
if (-not (Get-ServicePrincipal -Identity $AppName -ErrorAction SilentlyContinue)) {
    New-ServicePrincipal -AppId $ClientId -ObjectId $sp.Id -DisplayName $AppName | Out-Null
}
$exoSpObj = Get-ServicePrincipal -Identity $AppName
try {
    Add-RoleGroupMember -Identity 'View-Only Organization Management' -Member $exoSpObj.Identity -ErrorAction Stop
    Write-Host "      Role assigned." -ForegroundColor DarkGray
}
catch {
    Write-Host "      (role may already be assigned: $($_.Exception.Message))" -ForegroundColor DarkYellow
}

# --- Output -----------------------------------------------------------------
Write-Host ""
Write-Host "=====================  COPY THESE INTO MAILGUARD  =====================" -ForegroundColor Green
Write-Host ("Tenant ID:      " + $TenantId)
Write-Host ("Client ID:      " + $ClientId)
Write-Host ("Client Secret:  " + $ClientSecret)
Write-Host "=======================================================================" -ForegroundColor Green
Write-Host "The client secret is shown only once - copy it now." -ForegroundColor Yellow
Write-Host "Exchange role propagation can take up to 30 minutes to fully activate." -ForegroundColor DarkGray
