#Requires -Version 5.1
<#
  MailGuard - Step 2 of 2: assign the Exchange read-only role

  Run this AFTER Step 1 (MailGuard-1-Setup.ps1), and after MailGuard shows the tenant
  connected. It reads the values Step 1 saved (mailguard-credentials.txt in this same
  folder), or prompts for them, then grants the app the read-only Exchange role.

  It only verifies the required module is present (Step 1 installs it) and prints a
  single SUCCESS or ERROR line.

  HOW TO RUN (run as a FILE - do not paste the lines one by one):
    Windows:  right-click the file > "Run with PowerShell"   (nothing to install)
    Mac:      install PowerShell once:  brew install --cask powershell
              then run:  pwsh ./MailGuard-2-ExchangeRole.ps1
    Linux:    install PowerShell 7, then run:  pwsh ./MailGuard-2-ExchangeRole.ps1
#>

$ErrorActionPreference = 'Stop'
$AppName = 'MailGuard Scanner'

function Done($msg) { Write-Host ''; Write-Host "SUCCESS: $msg" -ForegroundColor Green; exit 0 }
function Fail($msg) { Write-Host ''; Write-Host "ERROR: $msg"   -ForegroundColor Red;   exit 1 }

# 1. Verify the module exists (Step 1 installs it; we only check here) -------
if (-not (Get-Module -ListAvailable -Name ExchangeOnlineManagement)) {
  Fail "ExchangeOnlineManagement module not found. Run MailGuard-1-Setup.ps1 first, then re-run this script."
}

# 2. Get the Client ID + service-principal Object ID ------------------------
$ClientId = $null; $ObjectId = $null
$credFile = Join-Path (Get-Location) 'mailguard-credentials.txt'
if (Test-Path $credFile) {
  foreach ($line in Get-Content $credFile) {
    if ($line -match '^\s*Client ID:\s*(\S+)')   { $ClientId = $Matches[1] }
    if ($line -match '^\s*SP_OBJECT_ID:\s*(\S+)') { $ObjectId = $Matches[1] }
  }
}
if (-not $ClientId) { $ClientId = (Read-Host 'Client ID (Application ID)').Trim() }
if (-not $ObjectId) { $ObjectId = (Read-Host 'Enterprise app (service principal) Object ID').Trim() }
if (-not $ClientId -or -not $ObjectId) { Fail 'Both Client ID and Object ID are required.' }

# 3. Connect to Exchange Online (device code: avoids the sign-in broker bug) -
Write-Host 'Sign in to Exchange Online when prompted (a code + URL will appear)...' -ForegroundColor Cyan
try {
  Import-Module ExchangeOnlineManagement
  Connect-ExchangeOnline -Device -ShowBanner:$false | Out-Null
} catch {
  Fail "Could not sign in to Exchange Online. ($($_.Exception.Message))"
}

# 4. Ensure the Exchange service principal exists, then assign the role ------
try {
  if (-not (Get-ServicePrincipal -Identity $AppName -ErrorAction SilentlyContinue)) {
    New-ServicePrincipal -AppId $ClientId -ObjectId $ObjectId -DisplayName $AppName | Out-Null
  }
  $svc = Get-ServicePrincipal -Identity $AppName
} catch {
  try { Disconnect-ExchangeOnline -Confirm:$false | Out-Null } catch {}
  Fail "Could not create or find the Exchange service principal. ($($_.Exception.Message))"
}

try {
  Add-RoleGroupMember -Identity 'View-Only Organization Management' -Member $svc.Identity -ErrorAction Stop
} catch {
  $m = "$($_.Exception.Message)"
  try { Disconnect-ExchangeOnline -Confirm:$false | Out-Null } catch {}
  if ($m -match 'already a member|already exists|is already') {
    Done 'The Exchange read-only role was already assigned. Nothing to do.'
  }
  Fail "Could not assign the Exchange role. ($m)"
}

try { Disconnect-ExchangeOnline -Confirm:$false | Out-Null } catch {}
Done 'Exchange read-only role assigned. MailGuard can now read mail-flow and transport data.'
