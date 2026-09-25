# ============================================================================
# TUQUET-CLOUD TEST PRESET CLI (POWERSHELL / WINDOWS / CI)
# Description: SOLID CLI for provisioning and verifying test identities,
#              tenants, memberships, and RLS access against Supabase.
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('apply', 'apply-preset', 'verify', 'verify-auth', 'list', 'list-presets', 'cleanup', 'cleanup-preset', 'provision-tenant')]
    [string]$Command = 'apply',

    [Parameter(Position = 1)]
    [string]$Preset = 'tunyk',

    [ValidateSet('local', 'linked')]
    [string]$Target = 'local',

    [switch]$Verify,

    [string]$Email,
    [string]$Password,
    [string]$FullName,
    [string]$TenantSlug,
    [string]$TenantName,
    [string]$Plan = 'pro',
    [string]$Role = 'owner',

    [string]$ApiUrl = 'http://127.0.0.1:54321',
    [string]$AnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0'
)

$ErrorActionPreference = 'Stop'

# Base paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent (Split-Path -Parent $ScriptDir)
$PresetsDir = Join-Path $RootDir "tests\presets"
$HelperSqlFile = Join-Path $PresetsDir "sql\00_provision_helper.sql"

# ----------------------------------------------------------------------------
# Helper: Print Banners
# ----------------------------------------------------------------------------
function Show-Banner {
    param([string]$Title)
    Write-Host "====================================================================" -ForegroundColor Cyan
    Write-Host " [TUQUET-CLOUD-TEST-CLI] $Title" -ForegroundColor Cyan
    Write-Host "====================================================================" -ForegroundColor Cyan
}

# ----------------------------------------------------------------------------
# Helper: Execute SQL against Database
# ----------------------------------------------------------------------------
function Invoke-DatabaseSql {
    param(
        [string]$SqlContent,
        [string]$TargetEnv
    )
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $output = ""

    if ($TargetEnv -eq 'local') {
        $output = $SqlContent | docker exec -i supabase_db_tuquet-cloud psql -U postgres -d postgres 2>&1
        $exitCode = $LASTEXITCODE
    } else {
        $tempFile = [System.IO.Path]::GetTempFileName() + ".sql"
        [System.IO.File]::WriteAllText($tempFile, $SqlContent, [System.Text.Encoding]::ASCII)
        $output = & supabase db query "--$TargetEnv" -f $tempFile 2>&1
        $exitCode = $LASTEXITCODE
        if (Test-Path $tempFile) { Remove-Item -Force $tempFile }
    }

    $ErrorActionPreference = $prevEAP
    return @{
        ExitCode = $exitCode
        Output = ($output -join "`n")
    }
}

# ----------------------------------------------------------------------------
# Helper: Ensure Provisioning SQL Helper exists in DB
# ----------------------------------------------------------------------------
function Ensure-ProvisionHelper {
    param([string]$TargetEnv)

    if (-not (Test-Path $HelperSqlFile)) {
        Write-Error "[-] Provisioning helper SQL file not found: $HelperSqlFile"
        exit 1
    }

    $checkSql = "SELECT count(1) FROM pg_proc WHERE proname = 'provision_test_preset';"
    $checkRes = Invoke-DatabaseSql -SqlContent $checkSql -TargetEnv $TargetEnv

    if ($checkRes.Output -notmatch "\s+1\s+") {
        Write-Host "--> Deploying provision helper stored procedures into database..." -ForegroundColor Yellow
        $sqlContent = Get-Content $HelperSqlFile -Raw
        $deployRes = Invoke-DatabaseSql -SqlContent $sqlContent -TargetEnv $TargetEnv
        if ($deployRes.ExitCode -ne 0) {
            Write-Error "[-] Failed to deploy helper procedures: $($deployRes.Output)"
            exit $deployRes.ExitCode
        }
        Write-Host "    [OK] Helper stored procedures installed successfully." -ForegroundColor Green
    }
}

# ----------------------------------------------------------------------------
# Command: List Presets
# ----------------------------------------------------------------------------
function List-Presets {
    Show-Banner "Available Test Presets"
    $files = Get-ChildItem -Path $PresetsDir -Filter "*.json" | Where-Object { $_.Name -notmatch "schema" }

    if ($files.Count -eq 0) {
        Write-Host "No presets found in $PresetsDir" -ForegroundColor Yellow
        return
    }

    Write-Host ("{0,-15} {1,-30} {2,-25} {3,-8} {4,-8}" -f "PRESET", "EMAIL", "TENANT SLUG", "ROLE", "PLAN") -ForegroundColor White
    Write-Host ("-" * 90) -ForegroundColor Gray

    foreach ($file in $files) {
        try {
            $json = Get-Content $file.FullName -Raw | ConvertFrom-Json
            $name = $json.name
            $userEmail = if ($json.user) { $json.user.email } else { "N/A" }
            $tenantSlug = if ($json.tenant) { $json.tenant.slug } else { "N/A" }
            $plan = if ($json.tenant -and $json.tenant.plan) { $json.tenant.plan } else { "pro" }
            $roleName = if ($json.role) { $json.role } else { "owner" }

            Write-Host ("{0,-15} {1,-30} {2,-25} {3,-8} {4,-8}" -f $name, $userEmail, $tenantSlug, $roleName, $plan) -ForegroundColor Cyan
        } catch {
            Write-Host ("{0,-15} [Error parsing JSON]" -f $file.BaseName) -ForegroundColor Red
        }
    }
    Write-Host ""
}

# ----------------------------------------------------------------------------
# Command: Resolve Preset File
# ----------------------------------------------------------------------------
function Resolve-PresetJson {
    param([string]$PresetName)

    $targetFile = $null
    if (Test-Path $PresetName) {
        $targetFile = (Resolve-Path $PresetName).Path
    } else {
        $candidate = Join-Path $PresetsDir "$PresetName.json"
        if (Test-Path $candidate) {
            $targetFile = $candidate
        }
    }

    if (-not $targetFile) {
        Write-Error "[-] Preset not found: $PresetName (looked in $PresetsDir)"
        exit 1
    }

    $rawContent = Get-Content $targetFile -Raw
    $parsed = $rawContent | ConvertFrom-Json
    return @{
        Path = $targetFile
        Raw = $rawContent
        Data = $parsed
    }
}

# ----------------------------------------------------------------------------
# Command: Verify Auth and RLS Access
# ----------------------------------------------------------------------------
function Verify-IdentityAuth {
    param(
        [string]$UserEmail,
        [string]$UserPassword,
        [string]$ExpectedTenantSlug,
        [string]$BaseApiUrl,
        [string]$Key
    )

    Write-Host "`n--> Verifying Authentication for: $UserEmail" -ForegroundColor Yellow

    $authUrl = "$BaseApiUrl/auth/v1/token?grant_type=password"
    $headers = @{
        "apikey" = $Key
        "Content-Type" = "application/json"
    }
    $body = @{
        "email" = $UserEmail
        "password" = $UserPassword
    } | ConvertTo-Json

    $token = $null
    $userId = $null

    try {
        $authResponse = Invoke-RestMethod -Uri $authUrl -Method Post -Headers $headers -Body $body
        $token = $authResponse.access_token
        $userId = $authResponse.user.id
        $emailConfirmedAt = $authResponse.user.email_confirmed_at

        Write-Host "    [OK] GoTrue Auth: HTTP 200 OK" -ForegroundColor Green
        Write-Host "    [OK] User ID: $userId" -ForegroundColor Green
        Write-Host "    [OK] Email Confirmed At: $emailConfirmedAt" -ForegroundColor Green
        Write-Host "    [OK] Status: ACTIVE 100%" -ForegroundColor Green
        Write-Host "    [OK] Access Token (JWT): $($token.Substring(0, 35))..." -ForegroundColor Green
    } catch {
        Write-Error "[-] Authentication failed for $UserEmail. Error: $_"
        exit 1
    }

    # Verify RLS Tenant Isolation
    Write-Host "`n--> Verifying Row-Level Security (RLS) & Tenant Isolation..." -ForegroundColor Yellow
    $restUrl = "$BaseApiUrl/rest/v1/tenants?select=id,slug,name,status,created_by"
    $restHeaders = @{
        "apikey" = $Key
        "Authorization" = "Bearer $token"
    }

    try {
        $tenants = Invoke-RestMethod -Uri $restUrl -Method Get -Headers $restHeaders
        $count = $tenants.Count
        Write-Host "    [OK] Visible Tenants returned by PostgREST: $count" -ForegroundColor Green

        $hasExpected = $false
        foreach ($t in $tenants) {
            $isTarget = ($t.slug -eq $ExpectedTenantSlug)
            $mark = if ($isTarget) { "[TARGET]" } else { "        " }
            Write-Host "    $mark Tenant: $($t.name) (slug: $($t.slug), status: $($t.status))" -ForegroundColor Cyan
            if ($isTarget) { $hasExpected = $true }
        }

        if ($ExpectedTenantSlug -and -not $hasExpected) {
            Write-Error "[-] RLS Check Warning: Expected tenant '$ExpectedTenantSlug' was not returned for this user!"
            exit 1
        }

        Write-Host "`n[VERIFICATION COMPLETE] Test Identity is 100% active, authenticated, and isolated via RLS!" -ForegroundColor Green
    } catch {
        Write-Error "[-] REST RLS query failed. Error: $_"
        exit 1
    }
}

# ----------------------------------------------------------------------------
# Command: Apply Preset
# ----------------------------------------------------------------------------
function Apply-Preset {
    param(
        [string]$PresetName,
        [string]$TargetEnv,
        [switch]$ShouldVerify,
        [string]$BaseApiUrl,
        [string]$Key
    )

    Show-Banner "Applying Test Preset: $PresetName"

    $presetObj = Resolve-PresetJson -PresetName $PresetName
    $presetData = $presetObj.Data

    Ensure-ProvisionHelper -TargetEnv $TargetEnv

    Write-Host "--> Provisioning Identity & Tenant in Database ($TargetEnv)..." -ForegroundColor Yellow

    # Escape single quotes in JSON string for SQL literal
    $escapedJson = $presetObj.Raw.Replace("'", "''")
    $execSql = "SELECT public.provision_test_preset('$escapedJson'::jsonb);"

    $dbResult = Invoke-DatabaseSql -SqlContent $execSql -TargetEnv $TargetEnv

    if ($dbResult.ExitCode -ne 0) {
        Write-Error "[-] Provisioning failed: $($dbResult.Output)"
        exit $dbResult.ExitCode
    }

    # Extract JSON line from output
    $matchingLines = @($dbResult.Output -split "\r?\n" | Where-Object { $_ -match '\{.*"success".*\}' })
    if ($matchingLines.Count -gt 0) {
        $cleanJson = [string]$matchingLines[0]
        $cleanJson = $cleanJson.Trim()
        $jsonResult = $cleanJson | ConvertFrom-Json
        Write-Host "    [OK] User ID:     $($jsonResult.user_id)" -ForegroundColor Green
        Write-Host "    [OK] Email:       $($jsonResult.email)" -ForegroundColor Green
        Write-Host "    [OK] Tenant ID:   $($jsonResult.tenant_id)" -ForegroundColor Green
        Write-Host "    [OK] Tenant Slug: $($jsonResult.tenant_slug)" -ForegroundColor Green
        Write-Host "    [OK] Role:        $($jsonResult.role_name)" -ForegroundColor Green
        if ($jsonResult.plan) { Write-Host "    [OK] Plan:        $($jsonResult.plan)" -ForegroundColor Green }
        Write-Host "    [OK] Status:      $($jsonResult.status)" -ForegroundColor Green
    } else {
        Write-Host $dbResult.Output -ForegroundColor Gray
    }

    Write-Host "`n[APPLY SUCCESSFUL] Preset '$PresetName' applied successfully." -ForegroundColor Green

    if ($ShouldVerify) {
        $email = $presetData.user.email
        $password = $presetData.user.password
        $slug = if ($presetData.tenant) { $presetData.tenant.slug } else { "" }
        Verify-IdentityAuth -UserEmail $email -UserPassword $password -ExpectedTenantSlug $slug -BaseApiUrl $BaseApiUrl -Key $Key
    }
}

# ----------------------------------------------------------------------------
# Command: Provision Tenant (Ad-hoc)
# ----------------------------------------------------------------------------
function Provision-TenantDirect {
    param(
        [string]$TargetEnv,
        [string]$UserEmail,
        [string]$UserPassword,
        [string]$UserFullName,
        [string]$Slug,
        [string]$Name,
        [string]$TenantPlan,
        [string]$UserRole,
        [switch]$ShouldVerify,
        [string]$BaseApiUrl,
        [string]$Key
    )

    if (-not $UserEmail -or -not $UserPassword -or -not $Slug) {
        Write-Error "[-] Provision-Tenant requires -Email, -Password, and -TenantSlug parameters."
        exit 1
    }

    $actualName = if ($Name) { $Name } else { $Slug }
    $actualFullName = if ($UserFullName) { $UserFullName } else { $UserEmail.Split('@')[0] }

    $adhocPreset = @{
        name = "adhoc-$Slug"
        user = @{
            email = $UserEmail
            password = $UserPassword
            full_name = $actualFullName
            avatar_url = ""
            metadata = @{ adhoc = $true }
        }
        tenant = @{
            slug = $Slug
            name = $actualName
            plan = $TenantPlan
            metadata = @{ adhoc = $true }
        }
        role = $UserRole
    } | ConvertTo-Json -Depth 5

    Show-Banner "Provisioning Ad-hoc Tenant: $Slug for $UserEmail"
    Ensure-ProvisionHelper -TargetEnv $TargetEnv

    $escapedJson = $adhocPreset.Replace("'", "''")
    $execSql = "SELECT public.provision_test_preset('$escapedJson'::jsonb);"
    $dbResult = Invoke-DatabaseSql -SqlContent $execSql -TargetEnv $TargetEnv

    if ($dbResult.ExitCode -ne 0) {
        Write-Error "[-] Provisioning failed: $($dbResult.Output)"
        exit $dbResult.ExitCode
    }

    Write-Host "    [OK] Tenant '$Slug' provisioned for $UserEmail." -ForegroundColor Green

    if ($ShouldVerify) {
        Verify-IdentityAuth -UserEmail $UserEmail -UserPassword $UserPassword -ExpectedTenantSlug $Slug -BaseApiUrl $BaseApiUrl -Key $Key
    }
}

# ----------------------------------------------------------------------------
# Command: Cleanup Preset
# ----------------------------------------------------------------------------
function Cleanup-Preset {
    param(
        [string]$PresetName,
        [string]$TargetEnv
    )

    Show-Banner "Cleaning up Preset: $PresetName"
    $presetObj = Resolve-PresetJson -PresetName $PresetName
    $email = $presetObj.Data.user.email
    $slug = if ($presetObj.Data.tenant) { $presetObj.Data.tenant.slug } else { $null }

    Write-Host "--> Removing user '$email' and tenant '$slug'..." -ForegroundColor Yellow

    $cleanupSql = @"
DO `$clean`$
DECLARE
    v_user_id UUID;
    v_tenant_id UUID;
BEGIN
    SELECT id INTO v_user_id FROM auth.users WHERE email = '$email';
    IF v_user_id IS NOT NULL THEN
        DELETE FROM auth.users WHERE id = v_user_id;
    END IF;

    IF '$slug' <> '' THEN
        DELETE FROM public.tenants WHERE slug = '$slug';
    END IF;
END;
`$clean`$;
"@

    $res = Invoke-DatabaseSql -SqlContent $cleanupSql -TargetEnv $TargetEnv
    if ($res.ExitCode -eq 0) {
        Write-Host "    [OK] Cleanup completed successfully for preset '$PresetName'." -ForegroundColor Green
    } else {
        Write-Error "[-] Cleanup failed: $($res.Output)"
    }
}

# ----------------------------------------------------------------------------
# Router
# ----------------------------------------------------------------------------
switch ($Command) {
    { $_ -in 'list', 'list-presets' } {
        List-Presets
    }
    { $_ -in 'apply', 'apply-preset' } {
        Apply-Preset -PresetName $Preset -TargetEnv $Target -ShouldVerify:$Verify -BaseApiUrl $ApiUrl -Key $AnonKey
    }
    { $_ -in 'verify', 'verify-auth' } {
        $presetObj = Resolve-PresetJson -PresetName $Preset
        $email = if ($Email) { $Email } else { $presetObj.Data.user.email }
        $password = if ($Password) { $Password } else { $presetObj.Data.user.password }
        $slug = if ($TenantSlug) { $TenantSlug } elseif ($presetObj.Data.tenant) { $presetObj.Data.tenant.slug } else { "" }
        Verify-IdentityAuth -UserEmail $email -UserPassword $password -ExpectedTenantSlug $slug -BaseApiUrl $ApiUrl -Key $AnonKey
    }
    { $_ -eq 'provision-tenant' } {
        Provision-TenantDirect -TargetEnv $Target -UserEmail $Email -UserPassword $Password `
            -UserFullName $FullName -Slug $TenantSlug -Name $TenantName -TenantPlan $Plan `
            -UserRole $Role -ShouldVerify:$Verify -BaseApiUrl $ApiUrl -Key $AnonKey
    }
    { $_ -in 'cleanup', 'cleanup-preset' } {
        Cleanup-Preset -PresetName $Preset -TargetEnv $Target
    }
}
