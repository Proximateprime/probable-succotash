param(
  [string]$BaseHref = '/'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubCachePath = Join-Path $projectRoot '.pub-cache'
$buildDir = Join-Path $projectRoot 'build\web'

if (!(Test-Path $pubCachePath)) {
  New-Item -ItemType Directory -Path $pubCachePath | Out-Null
}

$env:PUB_CACHE = $pubCachePath

Write-Host "Using PUB_CACHE=$env:PUB_CACHE"
Write-Host "Building GitHub Pages Flutter web bundle (base-href: $BaseHref)..."

Push-Location $projectRoot
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter pub get failed'
  }

  flutter build web --release --base-href $BaseHref --pwa-strategy offline-first
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter build web failed'
  }

  Write-Host "Build ready at $buildDir"
}
finally {
  Pop-Location
}
