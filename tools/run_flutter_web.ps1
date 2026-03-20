param(
  [int]$Port = 8080,
  [string]$Device = 'chrome'
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubCachePath = Join-Path $projectRoot '.pub-cache'

if (!(Test-Path $pubCachePath)) {
  New-Item -ItemType Directory -Path $pubCachePath | Out-Null
}

$env:PUB_CACHE = $pubCachePath

Write-Host "Using PUB_CACHE=$env:PUB_CACHE"
Write-Host "Starting Flutter web on device '$Device' at http://localhost:$Port ..."

Push-Location $projectRoot
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter pub get failed'
  }

  flutter run -d $Device --web-hostname 0.0.0.0 --web-port $Port
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter run failed'
  }
}
finally {
  Pop-Location
}