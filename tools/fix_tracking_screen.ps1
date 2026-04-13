# Fix tracking_screen.dart: move prepended methods back inside _TrackingScreenState

$file = "c:\Users\Public\lawn_softwhere\lib\screens\tracking_screen.dart"
$lines = [System.IO.File]::ReadAllLines($file)

Write-Host "Total lines: $($lines.Count)"
Write-Host "Line 1 (idx 0): $($lines[0].Substring(0, [Math]::Min(80, $lines[0].Length)))"
Write-Host "Line 354 (idx 353): $($lines[353].Substring(0, [Math]::Min(80, $lines[353].Length)))"
Write-Host "Line 355 (idx 354): $($lines[354].Substring(0, [Math]::Min(80, $lines[354].Length)))"
Write-Host "Line 356 (idx 355): [$($lines[355])]"
Write-Host "Line 357 (idx 356): $($lines[356].Substring(0, [Math]::Min(80, $lines[356].Length)))"

# The prepended methods are at lines 1-354 (indices 0-353)
# Line 355 (idx 354) is // ignore_for_file:
# Line 356 (idx 355) is empty
# Line 357 (idx 356) is the first real import

# Extract the 3 prepended methods (lines 1-354, indices 0-353)
$methodLines = $lines[0..353]

# Extract actual file content starting from line 357 (index 356)
$actualLines = $lines[356..($lines.Count - 1)]

Write-Host "Method lines count: $($methodLines.Count)"
Write-Host "Actual file lines count: $($actualLines.Count)"

# Find where _TrackingScreenState closes: look for "class _SpecialZoneOverlay"
$insertIdx = -1
for ($i = 0; $i -lt $actualLines.Count; $i++) {
    if ($actualLines[$i] -match '^class _SpecialZoneOverlay') {
        $insertIdx = $i
        Write-Host "Found _SpecialZoneOverlay at actual index: $i"
        Write-Host "Line before (idx $($i-1)): [$($actualLines[$i-1])]"
        Write-Host "Line before that (idx $($i-2)): [$($actualLines[$i-2])]"
        Write-Host "Line before that (idx $($i-3)): [$($actualLines[$i-3])]"
        break
    }
}

if ($insertIdx -eq -1) {
    Write-Host "ERROR: Could not find _SpecialZoneOverlay class"
    exit 1
}

# Build the new file:
# - actual lines up to and including "  }" (closes build method) = index insertIdx-3
# - blank line
# - the 3 methods
# - "" (blank line)
# - "}" (closes _TrackingScreenState) = index insertIdx-2
# - "" (blank line) = index insertIdx-1
# - class _SpecialZoneOverlay ... = index insertIdx onwards

$newLines = [System.Collections.Generic.List[string]]::new()

# Add everything up to and including the build() closing brace (insertIdx - 3)
for ($i = 0; $i -le ($insertIdx - 3); $i++) {
    $newLines.Add($actualLines[$i])
}

# Add blank line separator
$newLines.Add("")

# Add the 3 prepended methods
foreach ($ml in $methodLines) {
    $newLines.Add($ml)
}

# Add blank line before closing brace
$newLines.Add("")

# Add "}" (closes _TrackingScreenState) and rest of file
for ($i = ($insertIdx - 2); $i -lt $actualLines.Count; $i++) {
    $newLines.Add($actualLines[$i])
}

Write-Host "New file lines count: $($newLines.Count)"

# Write without BOM
$encoding = [System.Text.UTF8Encoding]::new($false)
[System.IO.File]::WriteAllLines($file, $newLines, $encoding)

Write-Host "SUCCESS: File rewritten."
