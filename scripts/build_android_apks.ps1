# Builds both Android APKs and copies them with the correct names.
# Run from anywhere:  .\scripts\build_android_apks.ps1

$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

$envFile = ".env.release"
if (-not (Test-Path $envFile)) {
  Write-Error "Missing $envFile. Copy .env.example to .env.release and fill in the Supabase values."
}

$dist = "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

Write-Host "Building Sales Rep..."
flutter build apk --release --dart-define-from-file=$envFile --dart-define=SELLO_RELEASE_APP=sales_rep
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$dist\sello-sales-rep.apk" -Force

Write-Host "Building Owner/Manager..."
flutter build apk --release --dart-define-from-file=$envFile --dart-define=SELLO_RELEASE_APP=owner_manager
Copy-Item "build\app\outputs\flutter-apk\app-release.apk" "$dist\sello-owner-manager.apk" -Force

Write-Host ""
Write-Host "Done. Your files are here:"
Write-Host "  $((Resolve-Path $dist).Path)\sello-sales-rep.apk"
Write-Host "  $((Resolve-Path $dist).Path)\sello-owner-manager.apk"
