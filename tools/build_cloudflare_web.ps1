$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubCachePath = Join-Path $projectRoot '.pub-cache'
$webDir = Join-Path $projectRoot 'web'
$buildDir = Join-Path $projectRoot 'build\web'

if (!(Test-Path $pubCachePath)) {
  New-Item -ItemType Directory -Path $pubCachePath | Out-Null
}

$env:PUB_CACHE = $pubCachePath

Write-Host "Using PUB_CACHE=$env:PUB_CACHE"
Write-Host 'Building Cloudflare-ready Flutter web bundle...'

Push-Location $projectRoot
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter pub get failed'
  }

  flutter build web --release --no-wasm-dry-run
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter build web failed'
  }

  $headersPath = Join-Path $webDir '_headers'
  $redirectsPath = Join-Path $webDir '_redirects'

  if (Test-Path $headersPath) {
    Copy-Item $headersPath (Join-Path $buildDir '_headers') -Force
  }

  if (Test-Path $redirectsPath) {
    Copy-Item $redirectsPath (Join-Path $buildDir '_redirects') -Force
  }

  Write-Host "Build ready at $buildDir"
}
finally {
  Pop-Location
}