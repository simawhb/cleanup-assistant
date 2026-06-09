# =====================================================
#         Large File Scanner v1.0
#         Scans common directories for space hogs
# =====================================================
# Usage: powershell -ExecutionPolicy Bypass -File scan-largefiles.ps1
# Custom threshold: -MinSizeMB 200
# Custom paths: -ScanPaths "C:\Users\whb\Downloads","D:\Projects"

param(
    [int]$MinSizeMB = 100,
    [int]$MaxResults = 50,
    [string[]]$ScanPaths = @()
)

$ErrorActionPreference = "SilentlyContinue"

# Default scan paths if none provided
if ($ScanPaths.Count -eq 0) {
    $ScanPaths = @(
        "$env:USERPROFILE\Desktop",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Documents",
        "$env:LOCALAPPDATA\Temp",
        "$env:LOCALAPPDATA",
        "$env:APPDATA"
    )
}

$results = @()

foreach ($scanDir in $ScanPaths) {
    if (-not (Test-Path $scanDir)) { continue }
    try {
        $files = Get-ChildItem $scanDir -Recurse -File -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Length -ge ($MinSizeMB * 1MB) } |
            Sort-Object Length -Descending |
            Select-Object -First $MaxResults

        foreach ($f in $files) {
            $sizeMB = [math]::Round($f.Length / 1MB, 2)
            $sizeGB = [math]::Round($f.Length / 1GB, 2)
            $results += [PSCustomObject]@{
                Name     = $f.Name
                Path     = $f.FullName
                Dir      = $f.DirectoryName
                SizeMB   = $sizeMB
                SizeGB   = $sizeGB
                Modified = $f.LastWriteTime.ToString("yyyy-MM-dd HH:mm")
                Ext      = $f.Extension.ToLower()
            }
        }
    } catch {}
}

# Deduplicate by path and sort by size
$results = $results | Sort-Object SizeMB -Descending | Select-Object -First $MaxResults -Unique

# Output as JSON
$results | ConvertTo-Json -Depth 3
