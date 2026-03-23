param(
  [string]$BaseHref = '/'
)

Write-Warning 'build_cloudflare_web.ps1 is deprecated. Use tools/build_github_web.ps1 instead.'
& "$PSScriptRoot\build_github_web.ps1" -BaseHref $BaseHref
