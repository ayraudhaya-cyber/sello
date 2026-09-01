# ============================================================================
# release_android.ps1 — One-command Sello Android release
#
# Usage:
#   .\scripts\release_android.ps1 1.0.4+5
#   .\scripts\release_android.ps1 1.0.4+5 -Notes "Bug fixes and improvements"
#   .\scripts\release_android.ps1 1.0.4+5 -Apps sales_rep
#   .\scripts\release_android.ps1 1.0.4+5 -SkipBuild
#   .\scripts\release_android.ps1 1.0.4+5 -SkipSupabase
#   .\scripts\release_android.ps1 1.0.4+5 -Upload
#
# Environment variables (secrets — never commit):
#   SUPABASE_PROJECT_REF    — e.g. pohfozsptcrnitbxgaep
#   SUPABASE_SERVICE_ROLE   — service-role key (for updating release row)
#   SELLO_FTP_HOST          — 20i FTP hostname
#   SELLO_FTP_USER          — 20i FTP username
#   SELLO_FTP_PASS          — 20i FTP password
# ============================================================================

param(
  [Parameter(Mandatory=$true, Position=0)]
  [string]$Version,

  [string]$Notes = "",

  [ValidateSet("both","sales_rep","owner_manager")]
  [string]$Apps = "both",

  [switch]$SkipBuild,
  [switch]$SkipSupabase,
  [switch]$Upload,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

# ---------------------------------------------------------------------------
# 1. Parse and validate version
# ---------------------------------------------------------------------------

if ($Version -notmatch '^(\d+\.\d+\.\d+)\+(\d+)$') {
  Write-Error "Invalid version format. Use MAJOR.MINOR.PATCH+BUILD (e.g. 1.0.4+5)"
}
$versionName = $Matches[1]
$buildNumber = [int]$Matches[2]
$today = (Get-Date).ToString("yyyy-MM-dd")

Write-Host ""
Write-Host "=== Sello Android Release ===" -ForegroundColor Cyan
Write-Host "  Version:  $versionName"
Write-Host "  Build:    $buildNumber"
Write-Host "  Date:     $today"
Write-Host "  Notes:    $(if ($Notes) { $Notes } else { '(none)' })"
Write-Host "  Apps:     $Apps"
Write-Host ""

$releaseApps = if ($Apps -eq "both") { @("sales_rep","owner_manager") } else { @($Apps) }

# ---------------------------------------------------------------------------
# 2. Update pubspec.yaml
# ---------------------------------------------------------------------------

$pubspec = Get-Content "pubspec.yaml" -Raw
$oldVersion = [regex]::Match($pubspec, 'version:\s*(.+)').Groups[1].Value.Trim()
if ($oldVersion -ne "$versionName+$buildNumber") {
  Write-Host "Updating pubspec.yaml: $oldVersion -> $versionName+$buildNumber"
  $pubspec = $pubspec -replace "version:\s*.+", "version: $versionName+$buildNumber"
  Set-Content "pubspec.yaml" $pubspec -NoNewline
} else {
  Write-Host "pubspec.yaml already at $versionName+$buildNumber"
}

# ---------------------------------------------------------------------------
# 3. Update release manifests (JSON files)
# ---------------------------------------------------------------------------

function Update-Manifests() {
  Write-Host "Updating release manifests..."
  $notesArg = if ($Notes) { $Notes } else { "" }
  dart run scripts/update_release_json.dart $versionName $buildNumber $today $notesArg $Apps
  if ($LASTEXITCODE -ne 0) { Write-Error "Failed to update release manifests" }
  Write-Host "Updated releases\sello-release.json"
  Write-Host "Updated web\sello-release.json"
}

Update-Manifests

# ---------------------------------------------------------------------------
# 4. Build APKs
# ---------------------------------------------------------------------------

$envFile = ".env.release"
if (-not (Test-Path $envFile)) {
  Write-Error "Missing $envFile. Copy .env.example and fill in Supabase values."
}

$dist = "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

if (-not $SkipBuild) {
  foreach ($app in $releaseApps) {
    $label = if ($app -eq "sales_rep") { "Sales Rep" } else { "Owner/Manager" }
    $filename = if ($app -eq "sales_rep") { "sello-sales-rep.apk" } else { "sello-owner-manager.apk" }

    Write-Host ""
    Write-Host "Building $label..." -ForegroundColor Yellow
    if ($DryRun) {
      Write-Host "  [dry-run] flutter build apk --release --dart-define-from-file=$envFile --dart-define=SELLO_RELEASE_APP=$app"
    } else {
      flutter build apk --release --dart-define-from-file=$envFile --dart-define=SELLO_RELEASE_APP=$app
      if ($LASTEXITCODE -ne 0) { Write-Error "Build failed for $label" }
      Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$dist\$filename" -Force
      Write-Host "  -> $dist\$filename" -ForegroundColor Green
    }
  }
} else {
  Write-Host "Skipping build (--SkipBuild)"
}

# ---------------------------------------------------------------------------
# 5. Update Supabase release row
# ---------------------------------------------------------------------------

if (-not $SkipSupabase) {
  $projectRef = $env:SUPABASE_PROJECT_REF
  $serviceRole = $env:SUPABASE_SERVICE_ROLE

  if (-not $projectRef -or -not $serviceRole) {
    Write-Host ""
    Write-Host "WARNING: SUPABASE_PROJECT_REF or SUPABASE_SERVICE_ROLE not set." -ForegroundColor Red
    Write-Host "Skipping Supabase update. Run this SQL manually:" -ForegroundColor Red
    Write-Host ""
    $manifestJson = Get-Content "releases\sello-release.json" -Raw
    Write-Host "update public.sello_app_release"
    Write-Host "set payload = '$($manifestJson.Replace("'","''"))'::jsonb,"
    Write-Host "    updated_at = timezone('utc', now())"
    Write-Host "where id = 1;"
    Write-Host ""
  } else {
    Write-Host ""
    Write-Host "Updating Supabase release row..." -ForegroundColor Yellow
    $manifestJson = Get-Content "releases\sello-release.json" -Raw
    $escapedJson = $manifestJson.Replace("'","''")
    $sql = "update public.sello_app_release set payload = '$escapedJson'::jsonb, updated_at = timezone('utc', now()) where id = 1;"

    $supabaseUrl = "https://$projectRef.supabase.co"
    $headers = @{
      "apikey" = $serviceRole
      "Authorization" = "Bearer $serviceRole"
      "Content-Type" = "application/json"
      "Prefer" = "return=minimal"
    }
    $body = @{ query = $sql } | ConvertTo-Json

    if ($DryRun) {
      Write-Host "  [dry-run] POST $supabaseUrl/rest/v1/rpc/... (update payload)"
    } else {
      try {
        $resp = Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/rpc" -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "  Supabase updated." -ForegroundColor Green
      } catch {
        Write-Host "  Supabase REST /rpc failed. Falling back to direct PATCH..." -ForegroundColor Yellow
        # Direct row update via PostgREST
        $patchHeaders = @{
          "apikey" = $serviceRole
          "Authorization" = "Bearer $serviceRole"
          "Content-Type" = "application/json"
          "Prefer" = "return=minimal"
        }
        $patchBody = @{ payload = ($manifestJson | ConvertFrom-Json); updated_at = (Get-Date).ToUniversalTime().ToString("o") } | ConvertTo-Json -Depth 10
        try {
          Invoke-RestMethod -Uri "$supabaseUrl/rest/v1/sello_app_release?id=eq.1" -Method PATCH -Headers $patchHeaders -Body $patchBody -ErrorAction Stop
          Write-Host "  Supabase updated via PATCH." -ForegroundColor Green
        } catch {
          Write-Host "  ERROR: Could not update Supabase. Update manually." -ForegroundColor Red
          Write-Host "  SQL:" -ForegroundColor Red
          Write-Host "  update public.sello_app_release set payload = '<json>'::jsonb, updated_at = timezone('utc', now()) where id = 1;"
        }
      }
    }
  }
} else {
  Write-Host "Skipping Supabase update (--SkipSupabase)"
}

# ---------------------------------------------------------------------------
# 6. Upload to 20i (FTP)
# ---------------------------------------------------------------------------

if ($Upload) {
  $ftpHost = $env:SELLO_FTP_HOST
  $ftpUser = $env:SELLO_FTP_USER
  $ftpPass = $env:SELLO_FTP_PASS

  if (-not $ftpHost -or -not $ftpUser -or -not $ftpPass) {
    Write-Host ""
    Write-Host "WARNING: FTP credentials not set (SELLO_FTP_HOST, SELLO_FTP_USER, SELLO_FTP_PASS)." -ForegroundColor Red
    Write-Host "Upload skipped. Manually upload from dist/ to 20i." -ForegroundColor Red
  } else {
    Write-Host ""
    Write-Host "Uploading to 20i..." -ForegroundColor Yellow

    $uploads = @{
      "sales_rep" = @{ local = "$dist\sello-sales-rep.apk"; remote = "/public-html/sello-updates/sales-rep/sello-sales-rep.apk" }
      "owner_manager" = @{ local = "$dist\sello-owner-manager.apk"; remote = "/public-html/sello-updates/owner-manager/sello-owner-manager.apk" }
    }

    foreach ($app in $releaseApps) {
      $info = $uploads[$app]
      if (-not (Test-Path $info.local)) {
        Write-Host "  File not found: $($info.local) - skipping" -ForegroundColor Red
        continue
      }

      $label = if ($app -eq "sales_rep") { "Sales Rep" } else { "Owner/Manager" }

      if ($DryRun) {
        Write-Host "  [dry-run] Upload $($info.local) -> ftp://$ftpHost$($info.remote)"
      } else {
        Write-Host "  Uploading $label..."
        try {
          $ftpUri = "ftp://$ftpHost$($info.remote)"
          $webclient = New-Object System.Net.WebClient
          $webclient.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
          $webclient.UploadFile($ftpUri, $info.local)
          Write-Host "  $label uploaded." -ForegroundColor Green
        } catch {
          Write-Host "  ERROR uploading ${label}: $_" -ForegroundColor Red
        }
      }
    }
  }
} else {
  Write-Host ""
  Write-Host "Upload skipped (use -Upload to deploy to 20i)." -ForegroundColor DarkGray
}

# ---------------------------------------------------------------------------
# 7. Summary
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "=== Release Summary ===" -ForegroundColor Cyan
Write-Host "  Version:        $versionName+$buildNumber"
Write-Host "  Released at:    $today"
Write-Host "  Apps updated:   $($releaseApps -join ', ')"
Write-Host "  Notes:          $(if ($Notes) { $Notes } else { '(none)' })"
Write-Host ""
Write-Host "  Files:" -ForegroundColor White
foreach ($app in $releaseApps) {
  $filename = if ($app -eq "sales_rep") { "sello-sales-rep.apk" } else { "sello-owner-manager.apk" }
  $filePath = "$dist\$filename"
  if (Test-Path $filePath) {
    $sizeVal = [math]::Round((Get-Item $filePath).Length / 1MB, 1)
    Write-Host "    $filename - ${sizeVal} MB"
  } else {
    Write-Host "    $filename - not built"
  }
}
Write-Host ""
Write-Host "  Manifests:" -ForegroundColor White
Write-Host "    releases\sello-release.json  (updated)"
Write-Host "    web\sello-release.json       (updated)"
Write-Host ""

if (-not $SkipSupabase -and -not $env:SUPABASE_PROJECT_REF) {
  Write-Host "  REMINDER: Update Supabase manually (SQL above)." -ForegroundColor Yellow
}
if (-not $Upload) {
  Write-Host "  REMINDER: Upload dist/*.apk to 20i manually, or re-run with -Upload." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
