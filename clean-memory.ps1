# =====================================================
#         Memory Cleaner v1.0
#         Monitors and optimizes system memory
# =====================================================
# Usage: powershell -ExecutionPolicy Bypass -File clean-memory.ps1
# Dry run: powershell -ExecutionPolicy Bypass -File clean-memory.ps1 -DryRun
# JSON: powershell -ExecutionPolicy Bypass -File clean-memory.ps1 -JsonOutput

param(
    [switch]$DryRun,
    [switch]$JsonOutput,
    [switch]$Aggressive
)

$ErrorActionPreference = "SilentlyContinue"

# --- Helper functions ---
function Get-MemoryInfo {
    $os = Get-CimInstance Win32_OperatingSystem
    $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 2)
    $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
    $usedGB = [math]::Round($totalGB - $freeGB, 2)
    $usedPct = [math]::Round(($usedGB / $totalGB) * 100, 1)
    return @{
        TotalGB = $totalGB
        FreeGB = $freeGB
        UsedGB = $usedGB
        UsedPct = $usedPct
    }
}

function Write-JsonOutput {
    param($data)
    $data | ConvertTo-Json -Depth 3
}

# Get initial memory state
$before = Get-MemoryInfo

[System.Collections.ArrayList]$actions = @()

if (-not $JsonOutput) {
    Write-Host ""
    Write-Host "=== Memory Cleaner v1.0 ===" -ForegroundColor Cyan
    Write-Host ("  Before: {0} GB / {1} GB ({2}%)" -f $before.UsedGB, $before.TotalGB, $before.UsedPct) -ForegroundColor Yellow
    if ($DryRun) { Write-Host "  *** DRY RUN MODE ***" -ForegroundColor Magenta }
    Write-Host ""
}

# =====================================================
# [1/5] Clear system working sets + file cache
# =====================================================
if (-not $JsonOutput) { Write-Host "[1/4] Clearing system working sets + file cache..." -ForegroundColor Yellow }

if (-not $DryRun) {
    # ProcessIdleTasks triggers Windows memory management:
    # flushes standby list, modified page list, and file system buffers
    $null = & rundll32.exe advapi32.dll,ProcessIdleTasks 2>&1
    [void]$actions.Add(@{
        Action = "System Working Sets + File Cache"
        Status = "done"
        Detail = "ProcessIdleTasks executed (flushes working sets and file buffers)"
    })
    if (-not $JsonOutput) { Write-Host "  [OK] System working sets + file cache cleared" -ForegroundColor DarkGray }
} else {
    [void]$actions.Add(@{ Action = "System Working Sets + File Cache"; Status = "dry-run"; Detail = "Would clear working sets and file cache" })
    if (-not $JsonOutput) { Write-Host "  [DRY RUN] Would clear system working sets + file cache" -ForegroundColor Magenta }
}

# =====================================================
# [3/5] Clear DNS cache
# =====================================================
if (-not $JsonOutput) { Write-Host "[2/4] Clearing DNS cache..." -ForegroundColor Yellow }

if (-not $DryRun) {
    $dnsResult = & ipconfig /flushdns 2>&1
    [void]$actions.Add(@{
        Action = "DNS Cache"
        Status = "done"
        Detail = ($dnsResult | Select-String "Successfully" | ForEach-Object { $_.ToString().Trim() }) -join "; "
    })
    if (-not $JsonOutput) { Write-Host "  [OK] DNS cache flushed" -ForegroundColor DarkGray }
} else {
    [void]$actions.Add(@{ Action = "DNS Cache"; Status = "dry-run"; Detail = "Would flush DNS cache" })
    if (-not $JsonOutput) { Write-Host "  [DRY RUN] Would flush DNS cache" -ForegroundColor Magenta }
}

# =====================================================
# [4/5] Clean up memory-intensive processes
# =====================================================
if (-not $JsonOutput) { Write-Host "[3/4] Checking memory-intensive processes..." -ForegroundColor Yellow }

$processes = Get-Process | Where-Object {
    $_.WorkingSet64 -gt 200MB -and
    $_.ProcessName -notin @("System", "Idle", "svchost", "csrss", "lsass", "services", "smss", "wininit", "winlogon")
} | Sort-Object WorkingSet64 -Descending | Select-Object -First 10

foreach ($proc in $processes) {
    $memMB = [math]::Round($proc.WorkingSet64 / 1MB, 0)
    [void]$actions.Add(@{
        Action = "Process: $($proc.ProcessName)"
        Status = "info"
        Detail = "${memMB} MB (PID: $($proc.Id))"
    })
    if (-not $JsonOutput) {
        Write-Host ("  [INFO] {0}: {1} MB" -f $proc.ProcessName, $memMB) -ForegroundColor DarkGray
    }
}

# =====================================================
# [5/5] Aggressive memory cleanup (optional)
# =====================================================
if ($Aggressive -and -not $DryRun) {
    if (-not $JsonOutput) { Write-Host "[4/4] Aggressive cleanup..." -ForegroundColor Yellow }

    # Clear Windows standby memory using EmptyWorkingSet API
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    public class MemoryHelper {
        [DllImport("psapi.dll")]
        public static extern int EmptyWorkingSet(IntPtr hwProc);
    }
"@

    $cleared = 0
    $failed = 0
    Get-Process | Where-Object { $_.Id -ne 0 -and $_.Id -ne 4 } | ForEach-Object {
        try {
            $handle = $_.Handle
            [void][MemoryHelper]::EmptyWorkingSet($handle)
            $cleared++
        } catch {
            $failed++
        }
    }

    [void]$actions.Add(@{
        Action = "Aggressive Memory Cleanup"
        Status = "done"
        Detail = "Cleared $cleared processes, failed $failed"
    })
    if (-not $JsonOutput) {
        Write-Host "  [OK] Cleared working sets for $cleared processes" -ForegroundColor DarkGray
        if ($failed -gt 0) {
            Write-Host "  [WARN] Failed for $failed processes (likely protected)" -ForegroundColor DarkYellow
        }
    }
} elseif ($Aggressive -and $DryRun) {
    [void]$actions.Add(@{ Action = "Aggressive Memory Cleanup"; Status = "dry-run"; Detail = "Would clear working sets" })
    if (-not $JsonOutput) { Write-Host "  [DRY RUN] Would run aggressive cleanup" -ForegroundColor Magenta }
}

# =====================================================
# Summary
# =====================================================
$after = Get-MemoryInfo
$freedGB = [math]::Max(0, $after.FreeGB - $before.FreeGB)
$freedPct = $before.UsedPct - $after.UsedPct

if ($JsonOutput) {
    $output = @{
        dryRun = $DryRun.IsPresent
        aggressive = $Aggressive.IsPresent
        before = $before
        after = $after
        freedGB = [math]::Round($freedGB, 2)
        freedPct = [math]::Round($freedPct, 1)
        actions = @($actions)
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    Write-JsonOutput $output
} else {
    Write-Host ""
    Write-Host "=== Done! ===" -ForegroundColor Green
    Write-Host ("  Before: {0} GB / {1} GB ({2}%)" -f $before.UsedGB, $before.TotalGB, $before.UsedPct)
    Write-Host ("  After:  {0} GB / {1} GB ({2}%)" -f $after.UsedGB, $after.TotalGB, $after.UsedPct)
    Write-Host ("  Freed:  {0} GB ({1}%)" -f $freedGB, $freedPct) -ForegroundColor Green
    Write-Host ""
    if ($before.UsedPct -gt 80) {
        Write-Host "TIP: Memory usage was high (>80%). Consider:" -ForegroundColor Cyan
        Write-Host "     - Closing unused applications" -ForegroundColor Cyan
        Write-Host "     - Checking for memory leaks in running apps" -ForegroundColor Cyan
        Write-Host "     - Running with -Aggressive for deeper cleanup" -ForegroundColor Cyan
    }
}
