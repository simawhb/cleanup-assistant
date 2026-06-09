# =====================================================
#         驷马C盘清理助手 v4.0
#         Safe version - preserves shortcuts & critical files
# =====================================================
# Run:       powershell -ExecutionPolicy Bypass -File cleanup-cache.ps1
# Dry run:   powershell -ExecutionPolicy Bypass -File cleanup-cache.ps1 -DryRun
# JSON:      powershell -ExecutionPolicy Bypass -File cleanup-cache.ps1 -JsonOutput
# Filter:    powershell -ExecutionPolicy Bypass -File cleanup-cache.ps1 -Categories temp,dev

param(
    [switch]$DryRun,
    [switch]$JsonOutput,
    [string[]]$Categories = @()
)

$ErrorActionPreference = "SilentlyContinue"

# --- Category filter helper ---
$ALL_CATEGORIES = @("temp","dev","browser","wupdate","prefetch","logs","recycle","thumbnails","delivery","installer")
function Test-CatEnabled {
    param([string]$Cat)
    if ($Categories.Count -eq 0) { return $true }
    return $Categories -contains $Cat
}

# --- Use ArrayList for O(1) append ---
[System.Collections.ArrayList]$results = @()

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $JsonOutput) {
    Write-Host ""
    Write-Host "=== 驷马C盘清理助手 v4.0 ===" -ForegroundColor Cyan
    Write-Host "  Safe mode: shortcuts, .lnk, .url files are PRESERVED" -ForegroundColor DarkGray
    if ($DryRun) { Write-Host "  *** DRY RUN MODE - no files will be deleted ***" -ForegroundColor Magenta }
    if (-not $isAdmin) { Write-Host "  Not running as admin - some items will be skipped" -ForegroundColor DarkGray }
    if ($Categories.Count -gt 0) { Write-Host "  Filtering: $($Categories -join ', ')" -ForegroundColor DarkGray }
    Write-Host ""
}

$before = (Get-PSDrive C).Free / 1GB

function Get-FolderSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $size) { return 0 }
        return [math]::Round($size / 1MB, 2)
    } catch { return 0 }
}

function Add-Result {
    param([string]$Category, [string]$Item, [double]$SizeMB, [string]$Status)
    if ($SizeMB -le 0) { return }
    [void]$results.Add([PSCustomObject]@{
        Category = $Category
        Item     = $Item
        SizeMB   = $SizeMB
        Status   = $Status
    })
    if (-not $JsonOutput) {
        $tag = switch ($Status) { "dry-run" { "[DRY RUN]" } "cleaned" { "[OK]" } "skipped" { "[SKIP]" } default { "[$_]" } }
        $color = switch ($Status) { "dry-run" { "Magenta" } "cleaned" { "DarkGray" } "skipped" { "DarkYellow" } default { "Gray" } }
        Write-Host "  $tag $Item : ${SizeMB} MB" -ForegroundColor $color
    }
}

function Remove-SafeItem {
    param([string]$Path, [string]$Category, [string]$Label)
    $size = Get-FolderSize $Path
    if ($size -gt 0) {
        if (-not $DryRun) {
            $null = Remove-Item "$Path\*" -Recurse -Force -ErrorAction SilentlyContinue 2>&1
        }
        Add-Result $Category $Label $size $(if ($DryRun) { "dry-run" } else { "cleaned" })
    }
}

# =====================================================
# [1/10] System Temp
# =====================================================
if (Test-CatEnabled "temp") {
    if (-not $JsonOutput) { Write-Host "[1/10] Cleaning system temp files..." -ForegroundColor Yellow }
    Remove-SafeItem $env:TEMP "System Temp" "User Temp"
    Remove-SafeItem "C:\Windows\Temp" "System Temp" "Windows Temp"
    Remove-SafeItem "$env:LOCALAPPDATA\CrashDumps" "System Temp" "Crash Dumps"
}

# =====================================================
# [2/10] Dev caches (measure BEFORE clean)
# =====================================================
if (Test-CatEnabled "dev") {
    if (-not $JsonOutput) { Write-Host "[2/10] Cleaning dev caches..." -ForegroundColor Yellow }

    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $npmCacheSize = Get-FolderSize "$env:APPDATA\npm-cache"
        if ($npmCacheSize -gt 0) {
            if (-not $DryRun) { $null = npm cache clean --force 2>&1 }
            Add-Result "Dev Cache" "npm cache" $npmCacheSize $(if ($DryRun) { "dry-run" } else { "cleaned" })
        }
    }

    if (Get-Command pip -ErrorAction SilentlyContinue) {
        $pipCachePath = "$env:LOCALAPPDATA\pip\cache"
        $pipCacheSize = Get-FolderSize $pipCachePath
        if ($pipCacheSize -gt 0) {
            if (-not $DryRun) { $null = pip cache purge 2>&1 }
            Add-Result "Dev Cache" "pip cache" $pipCacheSize $(if ($DryRun) { "dry-run" } else { "cleaned" })
        }
    }

    if (Get-Command uv -ErrorAction SilentlyContinue) {
        $uvCachePath = "$env:LOCALAPPDATA\uv\cache"
        if (-not $uvCachePath -or -not (Test-Path $uvCachePath)) { $uvCachePath = "$env:APPDATA\uv\cache" }
        $uvCacheSize = Get-FolderSize $uvCachePath
        if ($uvCacheSize -gt 0) {
            if (-not $DryRun) { $null = uv cache clean 2>&1 }
            Add-Result "Dev Cache" "uv cache" $uvCacheSize $(if ($DryRun) { "dry-run" } else { "cleaned" })
        }
    }
}

# =====================================================
# [3/10] Browser caches (auto-detect profiles, check running)
# =====================================================
if (Test-CatEnabled "browser") {
    if (-not $JsonOutput) { Write-Host "[3/10] Cleaning browser caches..." -ForegroundColor Yellow }

    $browserDefs = @(
        @{ Name = "Edge";   Base = "$env:LOCALAPPDATA\Microsoft\Edge\User Data";   Proc = "msedge" },
        @{ Name = "Chrome"; Base = "$env:LOCALAPPDATA\Google\Chrome\User Data";    Proc = "chrome" },
        @{ Name = "Brave";  Base = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Proc = "brave" }
    )

    foreach ($browser in $browserDefs) {
        if (-not (Test-Path $browser.Base)) { continue }

        # Check if browser is running
        $running = Get-Process -Name $browser.Proc -ErrorAction SilentlyContinue
        if ($running) {
            if (-not $JsonOutput) {
                Write-Host "  [WARN] $($browser.Name) is running - cache files may be locked" -ForegroundColor Yellow
            }
            Add-Result "Browser Cache" "$($browser.Name) (running)" 0 "skipped"
            continue
        }

        $profiles = Get-ChildItem $browser.Base -Directory | Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
        foreach ($profile in $profiles) {
            foreach ($cacheDir in @("Cache", "Code Cache", "GPUCache", "Service Worker\CacheStorage")) {
                $cachePath = Join-Path $profile.FullName $cacheDir
                Remove-SafeItem $cachePath "Browser Cache" "$($browser.Name) $($profile.Name) $cacheDir"
            }
        }
    }
}

# =====================================================
# [4/10] Windows Update cache (needs admin)
# =====================================================
if (Test-CatEnabled "wupdate") {
    if (-not $JsonOutput) { Write-Host "[4/10] Cleaning Windows Update cache..." -ForegroundColor Yellow }
    if ($isAdmin) {
        $wuBefore = Get-FolderSize "C:\Windows\SoftwareDistribution\Download"
        if ($wuBefore -gt 0) {
            if (-not $DryRun) {
                $svc = Get-Service wuauserv -ErrorAction SilentlyContinue
                $wasRunning = $svc -and $svc.Status -eq 'Running'
                if ($wasRunning) { $null = Stop-Service wuauserv -Force -ErrorAction SilentlyContinue 2>&1 }
                $null = Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue 2>&1
                if ($wasRunning) { $null = Start-Service wuauserv -ErrorAction SilentlyContinue 2>&1 }
            }
            Add-Result "Windows Update" "SoftwareDistribution" $wuBefore $(if ($DryRun) { "dry-run" } else { "cleaned" })
        }
    } else {
        if (-not $JsonOutput) { Write-Host "  Skipped (need admin)" -ForegroundColor DarkGray }
    }
}

# =====================================================
# [5/10] Prefetch (keep files < 7 days old)
# =====================================================
if (Test-CatEnabled "prefetch") {
    if (-not $JsonOutput) { Write-Host "[5/10] Cleaning old prefetch files (>7 days)..." -ForegroundColor Yellow }
    $prefetchPath = "C:\Windows\Prefetch"
    if (Test-Path $prefetchPath) {
        $oldFiles = @(Get-ChildItem $prefetchPath -File | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) })
        $oldSize = [math]::Round(($oldFiles | Measure-Object -Property Length -Sum).Sum / 1MB, 2)
        if ($oldSize -gt 0) {
            if (-not $DryRun) {
                $null = $oldFiles | Remove-Item -Force -ErrorAction SilentlyContinue 2>&1
            }
            Add-Result "Prefetch" "Old prefetch (>7d)" $oldSize $(if ($DryRun) { "dry-run" } else { "cleaned" })
            if (-not $JsonOutput) { Write-Host "    ($($oldFiles.Count) files)" -ForegroundColor DarkGray }
        }
    }
}

# =====================================================
# [6/10] Old Windows log files
# =====================================================
if (Test-CatEnabled "logs") {
    if (-not $JsonOutput) { Write-Host "[6/10] Cleaning old log files..." -ForegroundColor Yellow }
    Remove-SafeItem "C:\Windows\Logs\CBS" "Log Files" "CBS Logs"
    Remove-SafeItem "C:\Windows\Logs\DISM" "Log Files" "DISM Logs"
    Remove-SafeItem "$env:LOCALAPPDATA\Microsoft\Windows\INetCache" "Log Files" "INetCache"
}

# =====================================================
# [7/10] Thumbnail cache
# =====================================================
if (Test-CatEnabled "thumbnails") {
    if (-not $JsonOutput) { Write-Host "[7/10] Cleaning thumbnail cache..." -ForegroundColor Yellow }
    Remove-SafeItem "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" "Thumbnails" "Thumbnail Cache"
    $iconDb = "$env:LOCALAPPDATA\IconCache.db"
    if (Test-Path $iconDb) {
        $iconSize = [math]::Round((Get-Item $iconDb).Length / 1MB, 2)
        if ($iconSize -gt 0) {
            if (-not $DryRun) { $null = Remove-Item $iconDb -Force -ErrorAction SilentlyContinue 2>&1 }
            Add-Result "Thumbnails" "IconCache.db" $iconSize $(if ($DryRun) { "dry-run" } else { "cleaned" })
        }
    }
}

# =====================================================
# [8/10] Delivery Optimization cache
# =====================================================
if (Test-CatEnabled "delivery") {
    if (-not $JsonOutput) { Write-Host "[8/10] Cleaning Delivery Optimization..." -ForegroundColor Yellow }
    if ($isAdmin) {
        Remove-SafeItem "C:\Windows\SoftwareDistribution\DeliveryOptimization" "Delivery Optimization" "DeliveryOptimization"
    } else {
        if (-not $JsonOutput) { Write-Host "  Skipped (need admin)" -ForegroundColor DarkGray }
    }
}

# =====================================================
# [9/10] Windows Installer cache (safe subset)
# =====================================================
if (Test-CatEnabled "installer") {
    if (-not $JsonOutput) { Write-Host "[9/10] Cleaning installer patch cache..." -ForegroundColor Yellow }
    if ($isAdmin) {
        Remove-SafeItem "C:\Windows\Installer\PatchCache" "Installer Cache" "PatchCache"
    } else {
        if (-not $JsonOutput) { Write-Host "  Skipped (need admin)" -ForegroundColor DarkGray }
    }
}

# =====================================================
# [10/10] Recycle Bin
# =====================================================
if (Test-CatEnabled "recycle") {
    if (-not $JsonOutput) { Write-Host "[10/10] Recycle Bin check..." -ForegroundColor Yellow }
    try {
        $shell = New-Object -ComObject Shell.Application
        $rb = $shell.NameSpace(0x0a)
        $rbCount = $rb.Items().Count
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($shell) | Out-Null

        if ($rbCount -gt 0) {
            if (-not $JsonOutput) {
                Write-Host "  Recycle Bin has $rbCount items" -ForegroundColor Yellow
            }
            if (-not $DryRun) {
                if (-not $JsonOutput) {
                    $confirm = Read-Host "  Empty Recycle Bin? (y/N)"
                    if ($confirm -eq "y" -or $confirm -eq "Y") {
                        $null = Clear-RecycleBin -Force -ErrorAction SilentlyContinue 2>&1
                        Add-Result "Recycle Bin" "Recycle Bin" 0 "emptied"
                        Write-Host "  Recycle Bin emptied" -ForegroundColor Green
                    } else {
                        Write-Host "  Recycle Bin preserved" -ForegroundColor DarkGray
                    }
                } else {
                    $null = Clear-RecycleBin -Force -ErrorAction SilentlyContinue 2>&1
                    Add-Result "Recycle Bin" "Recycle Bin" 0 "emptied"
                }
            } else {
                Add-Result "Recycle Bin" "Recycle Bin" 0 "dry-run"
            }
        } else {
            if (-not $JsonOutput) { Write-Host "  Recycle Bin is empty" -ForegroundColor DarkGray }
        }
    } catch {
        if (-not $JsonOutput) { Write-Host "  Recycle Bin check failed" -ForegroundColor DarkGray }
    }
}

# =====================================================
# Summary
# =====================================================
$after = (Get-PSDrive C).Free / 1GB
$saved = [math]::Max(0, $after - $before)

if ($JsonOutput) {
    $output = @{
        dryRun    = $DryRun.IsPresent
        beforeGB  = [math]::Round($before, 2)
        afterGB   = [math]::Round($after, 2)
        savedGB   = [math]::Round($saved, 2)
        items     = @($results)
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $output | ConvertTo-Json -Depth 3
} else {
    Write-Host ""
    Write-Host "=== Done! ===" -ForegroundColor Green
    Write-Host ("  Before: {0:N2} GB free" -f $before)
    Write-Host ("  After:  {0:N2} GB free" -f $after)
    Write-Host ("  Saved:  {0:N2} GB" -f $saved) -ForegroundColor Green
    Write-Host ""
    Write-Host "TIP: If shortcuts are broken, check D:\Users\$env:USERNAME\Desktop" -ForegroundColor Cyan
    Write-Host "     for .lnk files, and copy them back to C:\Users\$env:USERNAME\Desktop" -ForegroundColor Cyan
    Write-Host ""
}
