# -----------------------------------------------------------------------------
# WinBreathe - Modern Native GUI Engine (v1.1.0 - Hardened Production)
# Zero-dependency, lightweight WinForms architecture (<15 MB footprint)
# Designed for Windows 11 8GB RAM & Mechanical HDD / Budget Systems
# -----------------------------------------------------------------------------

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# High-DPI Awareness (Per-Monitor v2)
try {
    $shcore = Add-Type -MemberDefinition @"
[DllImport("user32.dll")]
public static extern bool SetProcessDpiAwarenessContext(int dpiContext);
"@ -Name "DpiAware" -Namespace "WinBreathe" -PassThru -ErrorAction SilentlyContinue
    if ($shcore) { [WinBreathe.DpiAware]::SetProcessDpiAwarenessContext(-4) | Out-Null }
} catch {}

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# Fast Win32 Kernel Memory API (Zero CPU/Disk Overhead)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
[StructLayout(LayoutKind.Sequential)]
public struct MEMORYSTATUSEX {
    public uint dwLength;
    public uint dwMemoryLoad;
    public ulong ullTotalPhys;
    public ulong ullAvailPhys;
    public ulong ullTotalPageFile;
    public ulong ullAvailPageFile;
    public ulong ullTotalVirtual;
    public ulong ullAvailVirtual;
    public ulong ullAvailExtendedVirtual;
}
public class Win32KernelMem {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);
}
"@ -ErrorAction SilentlyContinue

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $scriptDir) { $scriptDir = $PSScriptRoot }
$engineScript = Join-Path $scriptDir "Win11LowRamOptimizer.ps1"

# Check Administrator Privileges
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# State Tracker
$global:ActiveEngineProcess = $null
$global:IsWorkerActive = $false

# Create Main Form
$form = New-Object System.Windows.Forms.Form
$form.Text = "WinBreathe - Windows 11 Memory and Latency Optimizer"
$form.Size = New-Object System.Drawing.Size(760, 640)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.Color]::FromArgb(24, 24, 37)
$form.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

# Allocate Fonts (Tracked for explicit disposal)
$fontTitle = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
$fontSubtitle = New-Object System.Drawing.Font("Segoe UI", 9.5)
$fontBold = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$fontRegular = New-Object System.Drawing.Font("Segoe UI", 9)
$fontConsole = New-Object System.Drawing.Font("Consolas", 9)

# Header Title
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "WinBreathe"
$lblTitle.Font = $fontTitle
$lblTitle.ForeColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
$lblTitle.Location = New-Object System.Drawing.Point(25, 18)
$lblTitle.AutoSize = $true
$form.Controls.Add($lblTitle)

# Help Button (Top Right)
$btnHelp = New-Object System.Windows.Forms.Button
$btnHelp.Text = "? Help"
$btnHelp.Font = $fontRegular
$btnHelp.BackColor = [System.Drawing.Color]::FromArgb(49, 50, 68)
$btnHelp.ForeColor = [System.Drawing.Color]::FromArgb(186, 194, 222)
$btnHelp.FlatStyle = "Flat"
$btnHelp.Location = New-Object System.Drawing.Point(620, 20)
$btnHelp.Size = New-Object System.Drawing.Size(100, 30)
$form.Controls.Add($btnHelp)

# Subtitle / Hardware badge
$diskType = "Unknown"
try {
    $phys = Get-PhysicalDisk -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($phys -and $phys.MediaType) { $diskType = $phys.MediaType }
} catch {}

$totalRamMB = 0
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    if ($os) { $totalRamMB = [math]::Round($os.TotalVisibleMemorySize / 1024, 0) }
} catch {}

$adminStatus = if ($isAdmin) { "Administrator" } else { "NON-ELEVATED" }
$badgeText = "OS Build: $($os.BuildNumber) | RAM: $totalRamMB MB | Disk: $diskType | Privilege: $adminStatus"

$lblBadge = New-Object System.Windows.Forms.Label
$lblBadge.Text = $badgeText
$lblBadge.Font = $fontSubtitle
$lblBadge.ForeColor = if ($isAdmin) { [System.Drawing.Color]::FromArgb(166, 173, 200) } else { [System.Drawing.Color]::FromArgb(243, 139, 168) }
$lblBadge.Location = New-Object System.Drawing.Point(28, 52)
$lblBadge.AutoSize = $true
$form.Controls.Add($lblBadge)

# Live Memory Status Panel
$grpMem = New-Object System.Windows.Forms.GroupBox
$grpMem.Text = " Real-Time Physical Memory Status "
$grpMem.Font = $fontBold
$grpMem.ForeColor = [System.Drawing.Color]::FromArgb(186, 194, 222)
$grpMem.Location = New-Object System.Drawing.Point(25, 82)
$grpMem.Size = New-Object System.Drawing.Size(695, 100)
$form.Controls.Add($grpMem)

# RAM Progress Bar
$progressBar = New-Object System.Windows.Forms.ProgressBar
$progressBar.Location = New-Object System.Drawing.Point(20, 28)
$progressBar.Size = New-Object System.Drawing.Size(655, 24)
$progressBar.Style = "Continuous"
$grpMem.Controls.Add($progressBar)

# RAM Stats Label
$lblStats = New-Object System.Windows.Forms.Label
$lblStats.Text = "Calculating live memory metrics..."
$lblStats.Font = $fontRegular
$lblStats.ForeColor = [System.Drawing.Color]::FromArgb(245, 224, 220)
$lblStats.Location = New-Object System.Drawing.Point(20, 60)
$lblStats.Size = New-Object System.Drawing.Size(655, 25)
$grpMem.Controls.Add($lblStats)

# Functions for Log and Metrics
function Append-Console([string]$text, [string]$colorHex = "#cdd6f4") {
    if ($form.IsDisposed -or $txtConsole.IsDisposed) { return }
    if ($txtConsole.InvokeRequired) {
        $txtConsole.Invoke([Action[string, string]]{
            param($t, $c)
            Append-Console $t $c
        }, @($text, $colorHex))
        return
    }
    $txtConsole.SelectionStart = $txtConsole.TextLength
    $txtConsole.SelectionLength = 0
    $txtConsole.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml($colorHex)
    $txtConsole.AppendText("[$((Get-Date).ToString('HH:mm:ss'))] $text`r`n")
    $txtConsole.ScrollToCaret()
}

function Refresh-Metrics {
    if ($form.IsDisposed -or $lblStats.IsDisposed) { return }
    $stat = New-Object MEMORYSTATUSEX
    $stat.dwLength = [System.Runtime.InteropServices.Marshal]::SizeOf($stat)
    if ([Win32KernelMem]::GlobalMemoryStatusEx([ref]$stat)) {
        $totMB = [math]::Round($stat.ullTotalPhys / 1MB, 0)
        $availMB = [math]::Round($stat.ullAvailPhys / 1MB, 0)
        $usedMB = $totMB - $availMB
        $pct = [int]$stat.dwMemoryLoad
        $pfTotMB = [math]::Round($stat.ullTotalPageFile / 1MB, 0)

        $progressBar.Value = [math]::Min(100, [math]::Max(0, $pct))
        $lblStats.Text = "Memory Load: $usedMB MB ($pct%)  |  Available: $availMB MB  |  Total RAM: $totMB MB  |  Pagefile: $pfTotMB MB"
        
        if ($pct -gt 80) {
            $lblStats.ForeColor = [System.Drawing.Color]::FromArgb(243, 139, 168)
        } elseif ($pct -gt 65) {
            $lblStats.ForeColor = [System.Drawing.Color]::FromArgb(250, 179, 135)
        } else {
            $lblStats.ForeColor = [System.Drawing.Color]::FromArgb(166, 227, 161)
        }
    }
}

# Action Buttons Panel
$btnOptimize = New-Object System.Windows.Forms.Button
$btnOptimize.Text = "Safe Optimize"
$btnOptimize.Font = $fontBold
$btnOptimize.BackColor = [System.Drawing.Color]::FromArgb(137, 180, 250)
$btnOptimize.ForeColor = [System.Drawing.Color]::FromArgb(17, 17, 27)
$btnOptimize.FlatStyle = "Flat"
$btnOptimize.Location = New-Object System.Drawing.Point(25, 195)
$btnOptimize.Size = New-Object System.Drawing.Size(165, 42)
$form.Controls.Add($btnOptimize)

$btnGuard = New-Object System.Windows.Forms.Button
$btnGuard.Text = "Update Guard"
$btnGuard.Font = $fontBold
$btnGuard.BackColor = [System.Drawing.Color]::FromArgb(166, 227, 161)
$btnGuard.ForeColor = [System.Drawing.Color]::FromArgb(17, 17, 27)
$btnGuard.FlatStyle = "Flat"
$btnGuard.Location = New-Object System.Drawing.Point(200, 195)
$btnGuard.Size = New-Object System.Drawing.Size(165, 42)
$form.Controls.Add($btnGuard)

$btnFlush = New-Object System.Windows.Forms.Button
$btnFlush.Text = "Flush WebViews"
$btnFlush.Font = $fontBold
$btnFlush.BackColor = [System.Drawing.Color]::FromArgb(203, 166, 247)
$btnFlush.ForeColor = [System.Drawing.Color]::FromArgb(17, 17, 27)
$btnFlush.FlatStyle = "Flat"
$btnFlush.Location = New-Object System.Drawing.Point(375, 195)
$btnFlush.Size = New-Object System.Drawing.Size(165, 42)
$form.Controls.Add($btnFlush)

$btnRestore = New-Object System.Windows.Forms.Button
$btnRestore.Text = "Restore Defaults"
$btnRestore.Font = $fontBold
$btnRestore.BackColor = [System.Drawing.Color]::FromArgb(243, 139, 168)
$btnRestore.ForeColor = [System.Drawing.Color]::FromArgb(17, 17, 27)
$btnRestore.FlatStyle = "Flat"
$btnRestore.Location = New-Object System.Drawing.Point(550, 195)
$btnRestore.Size = New-Object System.Drawing.Size(170, 42)
$form.Controls.Add($btnRestore)

# Console Log Area
$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Text = " Optimization Activity Console (Live Non-Blocking Stream) "
$grpLog.Font = $fontBold
$grpLog.ForeColor = [System.Drawing.Color]::FromArgb(186, 194, 222)
$grpLog.Location = New-Object System.Drawing.Point(25, 250)
$grpLog.Size = New-Object System.Drawing.Size(695, 330)
$form.Controls.Add($grpLog)

$txtConsole = New-Object System.Windows.Forms.RichTextBox
$txtConsole.Location = New-Object System.Drawing.Point(15, 25)
$txtConsole.Size = New-Object System.Drawing.Size(665, 290)
$txtConsole.BackColor = [System.Drawing.Color]::FromArgb(17, 17, 27)
$txtConsole.ForeColor = [System.Drawing.Color]::FromArgb(205, 214, 244)
$txtConsole.Font = $fontConsole
$txtConsole.ReadOnly = $true
$txtConsole.BorderStyle = "None"
$grpLog.Controls.Add($txtConsole)

function Set-ControlsEnabled([bool]$enabled) {
    $btnOptimize.Enabled = $enabled
    $btnGuard.Enabled    = $enabled
    $btnFlush.Enabled    = $enabled
    $btnRestore.Enabled  = $enabled
}

# Asynchronous Background Worker with Pipe-Deadlock Immunity
function Run-AsyncEngine([string]$engineArg, [string]$startMessage) {
    if (-not $isAdmin) {
        [System.Windows.Forms.MessageBox]::Show(
            "Administrator elevation is required to modify system memory and services.`nPlease restart WinBreathe as Administrator.",
            "Elevation Required",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning
        ) | Out-Null
        return
    }

    if ($global:IsWorkerActive) { return }
    $global:IsWorkerActive = $true
    Set-ControlsEnabled $false

    Append-Console $startMessage "#89b4fa"

    $worker = New-Object System.ComponentModel.BackgroundWorker
    $worker.WorkerReportsProgress = $true
    $worker.WorkerSupportsCancellation = $true

    $worker.DoWork += {
        param($sender, $e)
        $arg = $e.Argument
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "powershell.exe"
        # Merge stderr into stdout (2>&1) to eliminate 4KB pipe buffer deadlocks completely
        $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"$engineScript $arg 2>&1`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $false
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true

        $proc = [System.Diagnostics.Process]::Start($psi)
        $global:ActiveEngineProcess = $proc

        try {
            while (-not $proc.StandardOutput.EndOfStream) {
                if ($sender.CancellationPending) {
                    try { $proc.Kill() } catch {}
                    $e.Cancel = $true
                    return
                }
                $line = $proc.StandardOutput.ReadLine()
                if ($line) {
                    $sender.ReportProgress(0, $line)
                }
            }
            $proc.WaitForExit()
            $e.Result = $proc.ExitCode
        } finally {
            $global:ActiveEngineProcess = $null
            $proc.Dispose()
        }
    }

    $worker.ProgressChanged += {
        param($sender, $e)
        if ($e.UserState -and -not $form.IsDisposed) {
            $color = if ($e.UserState -match "ERROR|Failed|Exception") { "#f38ba8" }
                     elseif ($e.UserState -match "SUCCESS|Reclaimed|active") { "#a6e3a1" }
                     elseif ($e.UserState -match "WARNING|Notice") { "#f9e2af" }
                     else { "#cdd6f4" }
            Append-Console $e.UserState $color
        }
    }

    $worker.RunWorkerCompleted += {
        param($sender, $e)
        $global:IsWorkerActive = $false
        if ($form.IsDisposed) { return }

        Refresh-Metrics
        Set-ControlsEnabled $true

        if ($e.Cancelled) {
            Append-Console "Operation was cancelled by user." "#f9e2af"
        } elseif ($e.Error) {
            Append-Console "Execution error: $($e.Error.Message)" "#f38ba8"
        } elseif ($e.Result -ne 0) {
            Append-Console "Engine exited with code $($e.Result)." "#f38ba8"
        } else {
            Append-Console "Task finished successfully!" "#a6e3a1"
        }
    }

    $worker.RunWorkerAsync($engineArg)
}

# Event Handlers
$btnOptimize.Add_Click({
    Run-AsyncEngine "-Silent" "Starting 1-Click Safe Memory Optimization..."
})

$btnGuard.Add_Click({
    Run-AsyncEngine "-InstallPersistence" "Registering Hardened Windows Update Persistence Guard..."
})

$btnFlush.Add_Click({
    Run-AsyncEngine "-FlushTransientOnly" "Executing Intelligent Process and WebView Flush..."
})

$btnRestore.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Are you sure you want to revert all optimizations and restore Windows defaults?",
        "WinBreathe - Confirm Rollback",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Run-AsyncEngine "-RestoreDefaults" "Restoring default Windows and browser settings..."
    }
})

$btnHelp.Add_Click({
    Append-Console "=== WINBREATHE HELP GUIDE ===" "#89b4fa"
    Append-Console "[Safe Optimize] Applies Tier 2 zero-damage cuts: Caps Chromium renderers (3-8 based on RAM), enables 30s tab sleep and efficiency mode, disables WSearch and DiagTrack disk thrashing, allocates adaptive contiguous pagefile, and enables In-RAM compression (zRAM)." "#cdd6f4"
    Append-Console "[Update Guard] Registers Task Scheduler persistence task under SYSTEM with language-independent SIDs and 90s boot delay, ensuring Windows Update does not wipe optimizations on reboot." "#a6e3a1"
    Append-Console "[Flush WebViews] Safely terminates orphaned WebViews and SearchHost while using parent-PID inspection to strictly protect Antigravity, Claude, VS Code, and active dev stacks." "#cba6f7"
    Append-Console "[Restore Defaults] Complete 1-click rollback: Removes scheduled task, deletes all Edge/Chrome policy limits, re-enables Windows Search & Telemetry, and restores Windows automatic pagefile." "#f38ba8"
    Append-Console "=================================================" "#89b4fa"
})

# Auto-Refresh Timer
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 3000
$timer.Add_Tick({ Refresh-Metrics })
$timer.Start()

# Lifecycle Management: Handle Form Closing cleanly
$form.Add_FormClosing({
    param($sender, $e)
    if ($global:IsWorkerActive -and $global:ActiveEngineProcess) {
        try {
            $global:ActiveEngineProcess.Kill()
        } catch {}
    }
})

$form.Add_FormClosed({
    # Stop & Dispose Timer
    try { $timer.Stop(); $timer.Dispose() } catch {}

    # Explicitly dispose all allocated GDI fonts
    try {
        $fontTitle.Dispose()
        $fontSubtitle.Dispose()
        $fontBold.Dispose()
        $fontRegular.Dispose()
        $fontConsole.Dispose()
    } catch {}
})

# Initial Load
Refresh-Metrics
Append-Console "WinBreathe v1.1.0 initialized. Ready for optimization." "#89b4fa"
Append-Console "Hardware: $badgeText" "#a6adc8"
if (-not $isAdmin) {
    Append-Console "WARNING: Running in non-elevated mode. System modifications disabled." "#f38ba8"
} else {
    Append-Console "Tier 1 Untouchable protections active (Kernel, Defender, VPN, Active AI Stacks)." "#cdd6f4"
}

# Run Application Dialog
try {
    $form.ShowDialog() | Out-Null
} finally {
    $form.Dispose()
}
