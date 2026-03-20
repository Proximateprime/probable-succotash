param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$TestArgs
)

$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$pubCachePath = Join-Path $projectRoot '.pub-cache'

if (!(Test-Path $pubCachePath)) {
  New-Item -ItemType Directory -Path $pubCachePath | Out-Null
}

$env:PUB_CACHE = $pubCachePath

Write-Host "Using PUB_CACHE=$env:PUB_CACHE"
Write-Host 'Running flutter test with local cache to avoid Windows path-space issues...'

Push-Location $projectRoot
try {
  flutter pub get
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter pub get failed'
  }

  if ($TestArgs -and $TestArgs.Count -gt 0) {
    flutter test @TestArgs
  }
  else {
    flutter test
  }
  if ($LASTEXITCODE -ne 0) {
    throw 'flutter test failed'
  }
}
finally {
  Pop-Location
}
