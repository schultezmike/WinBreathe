#Requires -Version 5.1
# ==============================================================================
# WinBreathe.GUI.ps1 - Native 6-Tab Dark Graphical Dashboard (v2.1.2)
# Features:
#   - Custom GDI+ Circular RAM Gauge + Live 60-Point Memory History Chart
#   - Per-Tweak Interactive Checklist with Profile Selector & Preview (-WhatIf)
#   - Top Memory Consumers Inspector with Tier-1 Safety Protection
#   - Non-Destructive Startup Apps Manager (Enable / Disable)
#   - Live Drift Detection, Update Guard Manager & True Snapshot Undo
#   - Leak-free GDI+ resource management & non-blocking async execution
# ==============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$scriptDir  = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir    = Split-Path -Parent $scriptDir
$modulePath = Join-Path $scriptDir "WinBreathe.Engine.psm1"
$cliScript  = Join-Path $scriptDir "WinBreathe.ps1"
$assetsDir  = Join-Path $rootDir "assets"

Import-Module $modulePath -Force -ErrorAction Stop
if (-not ('WBProcessOutput' -as [type])) { Add-Type -Path (Join-Path $scriptDir 'WinBreathe.ProcessOutput.cs') -ErrorAction Stop }

# ------------------------------------------------------------------------------
# Catppuccin Mocha Color Palette & GDI+ Resource Registry (WB-05 Leak Prevention)
# ------------------------------------------------------------------------------
$cBase     = [System.Drawing.ColorTranslator]::FromHtml("#1e1e2e")
$cMantle   = [System.Drawing.ColorTranslator]::FromHtml("#181825")
$cCrust    = [System.Drawing.ColorTranslator]::FromHtml("#11111b")
$cSurface0 = [System.Drawing.ColorTranslator]::FromHtml("#313244")
$cSurface1 = [System.Drawing.ColorTranslator]::FromHtml("#45475a")
$cText     = [System.Drawing.ColorTranslator]::FromHtml("#cdd6f4")
$cSubtext  = [System.Drawing.ColorTranslator]::FromHtml("#a6adc8")
$cBlue     = [System.Drawing.ColorTranslator]::FromHtml("#89b4fa")
$cTeal     = [System.Drawing.ColorTranslator]::FromHtml("#94e2d5")
$cGreen    = [System.Drawing.ColorTranslator]::FromHtml("#a6e3a1")
$cYellow   = [System.Drawing.ColorTranslator]::FromHtml("#f9e2af")
$cPeach    = [System.Drawing.ColorTranslator]::FromHtml("#fab387")
$cRed      = [System.Drawing.ColorTranslator]::FromHtml("#f38ba8")
$cMauve    = [System.Drawing.ColorTranslator]::FromHtml("#cba6f7")

$script:GdiDisposables = New-Object System.Collections.Generic.List[System.IDisposable]
function Register-Gdi {
    param([System.IDisposable]$Obj)
    if ($null -ne $Obj) { $script:GdiDisposables.Add($Obj) }
    return $Obj
}

$fTitle   = Register-Gdi (New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold))
$fH2      = Register-Gdi (New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold))
$fBody    = Register-Gdi (New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Regular))
$fBold    = Register-Gdi (New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold))
$fSmall   = Register-Gdi (New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Regular))
$fMono    = Register-Gdi (New-Object System.Drawing.Font("Consolas", 9.5, [System.Drawing.FontStyle]::Regular))
$fGaugeLg = Register-Gdi (New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Bold))

# ------------------------------------------------------------------------------
# State & Telemetry History Buffer (60 samples = 3 minutes at 3s interval)
# ------------------------------------------------------------------------------
$sysProfile = Get-WBSystemProfile
$isAdmin    = Test-WBAdmin
$script:RamHistory  = New-Object System.Collections.Generic.List[int]
$script:UsedHistory = New-Object System.Collections.Generic.List[int]
for ($i = 0; $i -lt 30; $i++) {
    $script:RamHistory.Add([int]$sysProfile.LoadPercent)
    $script:UsedHistory.Add([int]$sysProfile.UsedRAMMB)
}
$script:LastSnap = Get-WBMemorySnapshot

# ------------------------------------------------------------------------------
# Main Form Setup
# ------------------------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = "WinBreathe v2.1.2 - Universal Windows Memory & Latency Optimizer"
$form.Size = New-Object System.Drawing.Size(1020, 720)
$form.MinimumSize = New-Object System.Drawing.Size(960, 680)
$form.StartPosition = "CenterScreen"
$form.BackColor = $cBase
$form.ForeColor = $cText
$form.Font = $fBody

$icoPath = Join-Path $assetsDir "icon.ico"
if (Test-Path $icoPath) {
    try {
        $formIcon = Register-Gdi (New-Object System.Drawing.Icon($icoPath))
        $form.Icon = $formIcon
    } catch {}
}

# ------------------------------------------------------------------------------
# Top Brand & Action Header
# ------------------------------------------------------------------------------
$headerPanel = New-Object System.Windows.Forms.Panel
$headerPanel.Dock = "Top"
$headerPanel.Height = 94
$headerPanel.BackColor = $cMantle
$form.Controls.Add($headerPanel)

$logoBox = New-Object System.Windows.Forms.PictureBox
$logoBox.Location = New-Object System.Drawing.Point(16, 11)
$logoBox.Size = New-Object System.Drawing.Size(52, 52)
$logoBox.SizeMode = "StretchImage"
$logoPath = Join-Path $assetsDir "logo.png"
if (Test-Path $logoPath) {
    try {
        $logoImg = Register-Gdi ([System.Drawing.Image]::FromFile($logoPath))
        $logoBox.Image = $logoImg
    } catch {}
}
$headerPanel.Controls.Add($logoBox)

$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Text = "WinBreathe v2.1.2"
$lblTitle.Font = $fTitle
$lblTitle.ForeColor = $cBlue
$lblTitle.Location = New-Object System.Drawing.Point(78, 10)
$lblTitle.AutoSize = $true
$headerPanel.Controls.Add($lblTitle)

$adminTag = if ($isAdmin) { "ADMIN" } else { "READ-ONLY (Run WinBreathe.bat as Admin to apply)" }
$lblSub = New-Object System.Windows.Forms.Label
$lblSub.Text = "OS: $($sysProfile.OSCaption) [$($sysProfile.OSFamily)]  |  $($sysProfile.TotalRAMMB) MB RAM  |  $($sysProfile.DiskMediaType) ($($sysProfile.FreeDiskGB) GB Free)  |  $adminTag"
$lblSub.Font = $fSmall
$lblSub.ForeColor = if ($isAdmin) { $cTeal } else { $cYellow }
$lblSub.Location = New-Object System.Drawing.Point(80, 62)
$lblSub.Size = New-Object System.Drawing.Size(904, 24)
$lblSub.Anchor = "Top,Left,Right"
$lblSub.AutoSize = $false
$lblSub.AutoEllipsis = $true
$headerPanel.Controls.Add($lblSub)

function New-WBButton {
    param(
        [string]$Text,
        [int]$X,
        [int]$Y,
        [int]$W,
        [int]$H,
        [System.Drawing.Color]$BgColor,
        [System.Drawing.Color]$FgColor
    )
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $Text
    $btn.Location = New-Object System.Drawing.Point($X, $Y)
    $btn.Size = New-Object System.Drawing.Size($W, $H)
    $btn.FlatStyle = "Flat"
    $btn.FlatAppearance.BorderSize = 1
    $btn.FlatAppearance.BorderColor = $cSurface1
    $btn.BackColor = $BgColor
    $btn.ForeColor = $FgColor
    $btn.Font = $fBold
    $btn.Cursor = [System.Windows.Forms.Cursors]::Hand
    return $btn
}

$btnQuickOpt   = New-WBButton -Text "Click Optimization" -X 540 -Y 18 -W 148 -H 38 -BgColor $cBlue     -FgColor $cCrust
$btnQuickFlush = New-WBButton -Text "Memory Check"   -X 698 -Y 18 -W 138 -H 38 -BgColor $cSurface0 -FgColor $cTeal
$btnQuickRep   = New-WBButton -Text "Export Report"    -X 846 -Y 18 -W 138 -H 38 -BgColor $cSurface0 -FgColor $cText
$headerPanel.Controls.AddRange(@($btnQuickOpt, $btnQuickFlush, $btnQuickRep))

# ------------------------------------------------------------------------------
# Custom Dark Owner-Drawn TabControl (6 Tabs)
# ------------------------------------------------------------------------------
$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(12, 102)
$tabs.Size = New-Object System.Drawing.Size(982, 568)
$tabs.Anchor = "Top,Bottom,Left,Right"
$tabs.Font = $fBold
$tabs.ItemSize = New-Object System.Drawing.Size(156, 34)
$tabs.SizeMode = "Fixed"
$tabs.DrawMode = "OwnerDrawFixed"

$tabs.Add_DrawItem({
    param($sender, $e)
    $g = $e.Graphics
    $tabPage = $sender.TabPages[$e.Index]
    $bounds  = $e.Bounds
    $isSelected = ($sender.SelectedIndex -eq $e.Index)
    $bgColor = if ($isSelected) { $cSurface0 } else { $cMantle }
    $fgColor = if ($isSelected) { $cBlue } else { $cSubtext }

    $bgBrush = New-Object System.Drawing.SolidBrush($bgColor)
    $g.FillRectangle($bgBrush, $bounds)
    $bgBrush.Dispose()

    if ($isSelected) {
        $accentPen = New-Object System.Drawing.Pen($cBlue, 3)
        $g.DrawLine($accentPen, $bounds.Left + 6, $bounds.Bottom - 2, $bounds.Right - 6, $bounds.Bottom - 2)
        $accentPen.Dispose()
    }

    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = "Center"
    $sf.LineAlignment = "Center"
    $fgBrush = New-Object System.Drawing.SolidBrush($fgColor)
    $g.DrawString($tabPage.Text, $fBold, $fgBrush, [System.Drawing.RectangleF]$bounds, $sf)
    $fgBrush.Dispose()
    $sf.Dispose()
})
$form.Controls.Add($tabs)

$tabDash    = New-Object System.Windows.Forms.TabPage("Dashboard")
$tabOpt     = New-Object System.Windows.Forms.TabPage("Optimize Tweaks")
$tabProcs   = New-Object System.Windows.Forms.TabPage("Processes (RAM)")
$tabStartup = New-Object System.Windows.Forms.TabPage("Startup Apps")
$tabStatus  = New-Object System.Windows.Forms.TabPage("Status & Guard")
$tabHelp    = New-Object System.Windows.Forms.TabPage("Help & Guide")

foreach ($tp in @($tabDash, $tabOpt, $tabProcs, $tabStartup, $tabStatus, $tabHelp)) {
    $tp.BackColor = $cBase
    $tp.ForeColor = $cText
    $tabs.TabPages.Add($tp)
}

# ==============================================================================
# TAB 1: DASHBOARD (Circular RAM Gauge + Live 60s Line Chart + Console)
# ==============================================================================
$gaugeCanvas = New-Object System.Windows.Forms.PictureBox
$gaugeCanvas.Location = New-Object System.Drawing.Point(14, 14)
$gaugeCanvas.Size = New-Object System.Drawing.Size(360, 250)
$gaugeCanvas.BackColor = $cMantle
$tabDash.Controls.Add($gaugeCanvas)

$chartCanvas = New-Object System.Windows.Forms.PictureBox
$chartCanvas.Location = New-Object System.Drawing.Point(388, 14)
$chartCanvas.Size = New-Object System.Drawing.Size(570, 250)
$chartCanvas.BackColor = $cMantle
$tabDash.Controls.Add($chartCanvas)

# Custom GDI+ Paint: Circular RAM Gauge + Commit/Disk Bars
$gaugeCanvas.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $snap = $script:LastSnap
    $pct  = $snap.LoadPercent

    $borderPen = New-Object System.Drawing.Pen($cSurface0, 1)
    $g.DrawRectangle($borderPen, 0, 0, $sender.Width - 1, $sender.Height - 1)
    $borderPen.Dispose()

    $titleBrush = New-Object System.Drawing.SolidBrush($cSubtext)
    $g.DrawString("PHYSICAL MEMORY LOAD", $fBold, $titleBrush, 16, 12)
    $titleBrush.Dispose()

    # Circular gauge on left half
    $rect = New-Object System.Drawing.Rectangle(24, 44, 150, 150)
    $trackPen = New-Object System.Drawing.Pen($cSurface0, 14)
    $trackPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $trackPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $g.DrawArc($trackPen, $rect, 135, 270)
    $trackPen.Dispose()

    $arcColor = if ($pct -ge 85) { $cRed } elseif ($pct -ge 70) { $cYellow } else { $cGreen }
    $sweep = [int][math]::Round(($pct / 100.0) * 270)
    $valPen = New-Object System.Drawing.Pen($arcColor, 14)
    $valPen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $valPen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    if ($sweep -gt 0) {
        $g.DrawArc($valPen, $rect, 135, $sweep)
    }
    $valPen.Dispose()

    # Center text inside gauge
    $sf = New-Object System.Drawing.StringFormat
    $sf.Alignment = "Center"
    $sf.LineAlignment = "Center"
    $valBrush = New-Object System.Drawing.SolidBrush($arcColor)
    $g.DrawString("$pct%", $fGaugeLg, $valBrush, [System.Drawing.RectangleF]::new(24, 38, 150, 140), $sf)
    $valBrush.Dispose()

    $subBrush = New-Object System.Drawing.SolidBrush($cSubtext)
    $g.DrawString("$($snap.AvailRAMMB) MB Free", $fSmall, $subBrush, [System.Drawing.RectangleF]::new(24, 130, 150, 30), $sf)

    # Right-side metric breakdowns
    $textBrush = New-Object System.Drawing.SolidBrush($cText)
    $g.DrawString("Used RAM:", $fSmall, $subBrush, 194, 50)
    $g.DrawString("$($snap.UsedRAMMB) / $($snap.TotalRAMMB) MB", $fBold, $textBrush, 194, 68)

    $g.DrawString("Commit Charge:", $fSmall, $subBrush, 194, 102)
    $g.DrawString("$($snap.CommitUsedMB) / $($snap.CommitTotalMB) MB", $fBold, $textBrush, 194, 120)

    # Commit mini bar
    $commitPct = if ($snap.CommitTotalMB -gt 0) { [math]::Min(1.0, $snap.CommitUsedMB / [double]$snap.CommitTotalMB) } else { 0.5 }
    $barBg = New-Object System.Drawing.SolidBrush($cSurface0)
    $barFg = New-Object System.Drawing.SolidBrush($cBlue)
    $g.FillRectangle($barBg, 194, 144, 146, 8)
    $g.FillRectangle($barFg, 194, 144, [int](146 * $commitPct), 8)
    $barBg.Dispose()
    $barFg.Dispose()

    $g.DrawString("Recommended Profile:", $fSmall, $subBrush, 194, 166)
    $recBrush = New-Object System.Drawing.SolidBrush($cTeal)
    $g.DrawString("$($sysProfile.RecommendedProfile) ($($sysProfile.DiskMediaType))", $fBold, $recBrush, 194, 184)

    $g.DrawString("Kernel API: GlobalMemoryStatusEx (<0.01ms)", $fSmall, $subBrush, 16, 222)

    $recBrush.Dispose()
    $textBrush.Dispose()
    $subBrush.Dispose()
    $sf.Dispose()
})

# Custom GDI+ Paint: Live 60-Point Memory History Line & Area Chart
$chartCanvas.Add_Paint({
    param($sender, $e)
    $g = $e.Graphics
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

    $w = $sender.Width
    $h = $sender.Height

    $borderPen = New-Object System.Drawing.Pen($cSurface0, 1)
    $g.DrawRectangle($borderPen, 0, 0, $w - 1, $h - 1)

    $subBrush  = New-Object System.Drawing.SolidBrush($cSubtext)
    $blueBrush = New-Object System.Drawing.SolidBrush($cBlue)
    $g.DrawString("LIVE MEMORY HISTORY (LAST 60 SAMPLES)", $fBold, $subBrush, 16, 12)

    $snap = $script:LastSnap
    $g.DrawString("Current: $($snap.UsedRAMMB) MB ($($snap.LoadPercent)%)", $fBold, $blueBrush, $w - 210, 12)

    $plotLeft   = 46
    $plotTop    = 44
    $plotWidth  = $w - 64
    $plotHeight = $h - 72
    $plotBottom = $plotTop + $plotHeight

    # Draw horizontal grid lines (100%, 75%, 50%, 25%, 0%)
    $gridPen = New-Object System.Drawing.Pen($cSurface0, 1)
    $gridPen.DashStyle = [System.Drawing.Drawing2D.DashStyle]::Dot
    foreach ($lvl in @(0, 25, 50, 75, 100)) {
        $y = [int]($plotBottom - ($lvl / 100.0) * $plotHeight)
        $g.DrawLine($gridPen, $plotLeft, $y, $plotLeft + $plotWidth, $y)
        $g.DrawString("$lvl%", $fSmall, $subBrush, 8, $y - 8)
    }
    $gridPen.Dispose()

    $count = $script:RamHistory.Count
    if ($count -ge 2) {
        $pts = New-Object System.Drawing.PointF[] $count
        for ($i = 0; $i -lt $count; $i++) {
            $x = $plotLeft + ($i / [double]($count - 1)) * $plotWidth
            $val = [math]::Max(0, [math]::Min(100, $script:RamHistory[$i]))
            $y = $plotBottom - ($val / 100.0) * $plotHeight
            $pts[$i] = New-Object System.Drawing.PointF([float]$x, [float]$y)
        }

        # Area polygon under curve
        $polyPts = New-Object System.Drawing.PointF[] ($count + 2)
        for ($i = 0; $i -lt $count; $i++) { $polyPts[$i] = $pts[$i] }
        $polyPts[$count]     = New-Object System.Drawing.PointF([float]($plotLeft + $plotWidth), [float]$plotBottom)
        $polyPts[$count + 1] = New-Object System.Drawing.PointF([float]$plotLeft, [float]$plotBottom)

        $fillColor = [System.Drawing.Color]::FromArgb(55, $cBlue.R, $cBlue.G, $cBlue.B)
        $fillBrush = New-Object System.Drawing.SolidBrush($fillColor)
        $g.FillPolygon($fillBrush, $polyPts)
        $fillBrush.Dispose()

        $linePen = New-Object System.Drawing.Pen($cBlue, 2.5)
        $g.DrawLines($linePen, $pts)
        $linePen.Dispose()
    }

    $g.DrawString("3-second sampling interval | Zero disk I/O | Tier-1 AI & VPN Processes Protected", $fSmall, $subBrush, $plotLeft, $plotBottom + 8)

    $blueBrush.Dispose()
    $subBrush.Dispose()
    $borderPen.Dispose()
})

# Dashboard Console Output Box
$lblConsole = New-Object System.Windows.Forms.Label
$lblConsole.Text = "LIVE ENGINE & TELEMETRY CONSOLE"
$lblConsole.Font = $fBold
$lblConsole.ForeColor = $cSubtext
$lblConsole.Location = New-Object System.Drawing.Point(14, 274)
$lblConsole.AutoSize = $true
$tabDash.Controls.Add($lblConsole)

$consoleBox = New-Object System.Windows.Forms.RichTextBox
$consoleBox.Location = New-Object System.Drawing.Point(14, 296)
$consoleBox.Size = New-Object System.Drawing.Size(944, 244)
$consoleBox.BackColor = $cCrust
$consoleBox.ForeColor = $cText
$consoleBox.Font = $fMono
$consoleBox.ReadOnly = $true
$consoleBox.BorderStyle = "None"
$tabDash.Controls.Add($consoleBox)

function Write-GuiConsole {
    param([string]$Text, [string]$HexColor = "#cdd6f4")
    if ($consoleBox.IsDisposed) { return }
    $consoleBox.SelectionStart = $consoleBox.TextLength
    $consoleBox.SelectionLength = 0
    $consoleBox.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml($HexColor)
    $consoleBox.AppendText("$Text`r`n")
    $consoleBox.ScrollToCaret()
}

# ==============================================================================
# TAB 2: OPTIMIZE TWEAKS (Profile Selector + Per-Tweak Checkboxes + Preview)
# ==============================================================================
$optTopBar = New-Object System.Windows.Forms.Panel
$optTopBar.Location = New-Object System.Drawing.Point(14, 12)
$optTopBar.Size = New-Object System.Drawing.Size(944, 48)
$optTopBar.BackColor = $cMantle
$tabOpt.Controls.Add($optTopBar)

$lblProf = New-Object System.Windows.Forms.Label
$lblProf.Text = "Profile:"
$lblProf.Font = $fBold
$lblProf.Location = New-Object System.Drawing.Point(10, 14)
$lblProf.AutoSize = $true
$optTopBar.Controls.Add($lblProf)

$cmbProfile = New-Object System.Windows.Forms.ComboBox
$cmbProfile.Location = New-Object System.Drawing.Point(62, 10)
$cmbProfile.Size = New-Object System.Drawing.Size(120, 28)
$cmbProfile.DropDownStyle = "DropDownList"
$cmbProfile.BackColor = $cSurface0
$cmbProfile.ForeColor = $cText
$cmbProfile.Font = $fBold
[void]$cmbProfile.Items.AddRange(@("Conservative", "Balanced", "Aggressive"))
$cmbProfile.SelectedItem = $sysProfile.RecommendedProfile
$optTopBar.Controls.Add($cmbProfile)

$lblOS = New-Object System.Windows.Forms.Label
$lblOS.Text = "OS View:"
$lblOS.Font = $fBold
$lblOS.Location = New-Object System.Drawing.Point(192, 14)
$lblOS.AutoSize = $true
$optTopBar.Controls.Add($lblOS)

$cmbOS = New-Object System.Windows.Forms.ComboBox
$cmbOS.Location = New-Object System.Drawing.Point(254, 10)
$cmbOS.Size = New-Object System.Drawing.Size(195, 28)
$cmbOS.DropDownStyle = "DropDownList"
$cmbOS.BackColor = $cSurface0
$cmbOS.ForeColor = $cTeal
$cmbOS.Font = $fBold
[void]$cmbOS.Items.AddRange(@(
    "Detected ($($sysProfile.OSFamily))",
    "Windows 11",
    "Windows 10",
    "Windows 8.1",
    "Windows 7"
))
$cmbOS.SelectedIndex = 0
$optTopBar.Controls.Add($cmbOS)

$btnPreviewSel = New-WBButton -Text "Preview Selected (-WhatIf)" -X 465 -Y 7 -W 230 -H 34 -BgColor $cSurface0 -FgColor $cMauve
$btnApplySel   = New-WBButton -Text "Apply Selected Tweaks"      -X 705 -Y 7 -W 230 -H 34 -BgColor $cGreen    -FgColor $cCrust
$optTopBar.Controls.AddRange(@($btnPreviewSel, $btnApplySel))

$gridTweaks = New-Object System.Windows.Forms.DataGridView
$gridTweaks.Location = New-Object System.Drawing.Point(14, 68)
$gridTweaks.Size = New-Object System.Drawing.Size(944, 385)
$gridTweaks.BackgroundColor = $cMantle
$gridTweaks.BorderStyle = "None"
$gridTweaks.AllowUserToAddRows = $false
$gridTweaks.AllowUserToDeleteRows = $false
$gridTweaks.AllowUserToResizeRows = $false
$gridTweaks.RowHeadersVisible = $false
$gridTweaks.SelectionMode = "FullRowSelect"
$gridTweaks.MultiSelect = $false
$gridTweaks.EnableHeadersVisualStyles = $false
$gridTweaks.ColumnHeadersDefaultCellStyle.BackColor = $cSurface0
$gridTweaks.ColumnHeadersDefaultCellStyle.ForeColor = $cBlue
$gridTweaks.ColumnHeadersDefaultCellStyle.Font = $fBold
$gridTweaks.ColumnHeadersHeight = 32
$gridTweaks.DefaultCellStyle.BackColor = $cMantle
$gridTweaks.DefaultCellStyle.ForeColor = $cText
$gridTweaks.DefaultCellStyle.SelectionBackColor = $cSurface1
$gridTweaks.DefaultCellStyle.SelectionForeColor = $cText
$gridTweaks.GridColor = $cSurface0
$gridTweaks.RowTemplate.Height = 28

$colChk = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
$colChk.Name = "Apply"
$colChk.HeaderText = "Select"
$colChk.Width = 58
[void]$gridTweaks.Columns.Add($colChk)

foreach ($colSpec in @(
    @{ Name = "Id";       Header = "Tweak ID";    Width = 150; ReadOnly = $true },
    @{ Name = "Category"; Header = "Category";    Width = 85;  ReadOnly = $true },
    @{ Name = "Title";    Header = "Description"; Width = 360; ReadOnly = $true },
    @{ Name = "Risk";     Header = "Risk Tier";   Width = 95;  ReadOnly = $true },
    @{ Name = "State";    Header = "Live State";  Width = 110; ReadOnly = $true },
    @{ Name = "Current";  Header = "Current OS";  Width = 80;  ReadOnly = $true }
)) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $colSpec.Name
    $c.HeaderText = $colSpec.Header
    $c.Width = $colSpec.Width
    $c.ReadOnly = $colSpec.ReadOnly
    [void]$gridTweaks.Columns.Add($c)
}
$tabOpt.Controls.Add($gridTweaks)

$lblTweakDetail = New-Object System.Windows.Forms.Label
$lblTweakDetail.Location = New-Object System.Drawing.Point(14, 462)
$lblTweakDetail.Size = New-Object System.Drawing.Size(944, 76)
$lblTweakDetail.BackColor = $cMantle
$lblTweakDetail.ForeColor = $cText
$lblTweakDetail.Font = $fBody
$lblTweakDetail.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 8)
$lblTweakDetail.Text = "Select any tweak above to inspect its exact registry/service target, memory impact, and safety notes."
$tabOpt.Controls.Add($lblTweakDetail)

function Get-SelectedTargetOS {
    $sel = [string]$cmbOS.SelectedItem
    if ($sel -match "Windows 7")  { return "Win7" }
    if ($sel -match "Windows 8")  { return "Win8" }
    if ($sel -match "Windows 10") { return "Win10" }
    if ($sel -match "Windows 11") { return "Win11" }
    return ""
}

$script:TweakStateCache = @()
function Refresh-TweaksGrid {
    $prof = [string]$cmbProfile.SelectedItem
    if ([string]::IsNullOrEmpty($prof)) { $prof = "Balanced" }
    $targetOS = Get-SelectedTargetOS
    $script:TweakStateCache = Test-WBTweakState -ProfileName $prof -TargetOS $targetOS
    $gridTweaks.Rows.Clear()

    foreach ($t in $script:TweakStateCache) {
        $checked = ($t.InProfile -and $t.Applicable)
        $rowIdx = $gridTweaks.Rows.Add($checked, $t.Id, $t.Category, $t.Title, $t.Risk, $t.State, $t.CurrentValue)
        $row = $gridTweaks.Rows[$rowIdx]
        $row.Cells["Risk"].Style.ForeColor = switch ($t.Risk) {
            "Safe"     { $cGreen }
            "Moderate" { $cYellow }
            default    { $cPeach }
        }
        $row.Cells["State"].Style.ForeColor = switch ($t.State) {
            "Applied"       { $cGreen }
            "NotApplicable" { $cSubtext }
            "Unknown"       { $cPeach }
            default         { $cYellow }
        }
    }
}

$cmbProfile.Add_SelectedIndexChanged({ Refresh-TweaksGrid })
$cmbOS.Add_SelectedIndexChanged({ Refresh-TweaksGrid })
$gridTweaks.Add_SelectionChanged({
    if ($gridTweaks.SelectedRows.Count -gt 0) {
        $id = $gridTweaks.SelectedRows[0].Cells["Id"].Value
        $item = $script:TweakStateCache | Where-Object { $_.Id -eq $id } | Select-Object -First 1
        if ($item) {
            $lblTweakDetail.Text = "[$($item.Id)] $($item.Description)`r`nImpact: $($item.Impact)   |   Target: $($item.TargetValue)   |   Current: $($item.CurrentValue)"
        }
    }
})

# ==============================================================================
# TAB 3: PROCESSES (TOP MEMORY CONSUMERS + SAFE TERMINATION)
# ==============================================================================
$procTopBar = New-Object System.Windows.Forms.Panel
$procTopBar.Location = New-Object System.Drawing.Point(14, 12)
$procTopBar.Size = New-Object System.Drawing.Size(944, 48)
$procTopBar.BackColor = $cMantle
$tabProcs.Controls.Add($procTopBar)

$lblProcNote = New-Object System.Windows.Forms.Label
$lblProcNote.Text = "Top Memory Consumers (Grouped by App). Protected OS, VPN & AI Dev processes are locked from termination."
$lblProcNote.Font = $fBody
$lblProcNote.ForeColor = $cSubtext
$lblProcNote.Location = New-Object System.Drawing.Point(12, 14)
$lblProcNote.AutoSize = $true
$procTopBar.Controls.Add($lblProcNote)

$btnRefreshProcs = New-WBButton -Text "Refresh List"     -X 620 -Y 7 -W 145 -H 34 -BgColor $cSurface0 -FgColor $cText
$btnKillProc     = New-WBButton -Text "End Selected App" -X 775 -Y 7 -W 155 -H 34 -BgColor $cRed      -FgColor $cCrust
$procTopBar.Controls.AddRange(@($btnRefreshProcs, $btnKillProc))

$gridProcs = New-Object System.Windows.Forms.DataGridView
$gridProcs.Location = New-Object System.Drawing.Point(14, 68)
$gridProcs.Size = New-Object System.Drawing.Size(944, 470)
$gridProcs.BackgroundColor = $cMantle
$gridProcs.BorderStyle = "None"
$gridProcs.AllowUserToAddRows = $false
$gridProcs.ReadOnly = $true
$gridProcs.RowHeadersVisible = $false
$gridProcs.SelectionMode = "FullRowSelect"
$gridProcs.MultiSelect = $false
$gridProcs.EnableHeadersVisualStyles = $false
$gridProcs.ColumnHeadersDefaultCellStyle.BackColor = $cSurface0
$gridProcs.ColumnHeadersDefaultCellStyle.ForeColor = $cBlue
$gridProcs.ColumnHeadersDefaultCellStyle.Font = $fBold
$gridProcs.ColumnHeadersHeight = 32
$gridProcs.DefaultCellStyle.BackColor = $cMantle
$gridProcs.DefaultCellStyle.ForeColor = $cText
$gridProcs.DefaultCellStyle.SelectionBackColor = $cSurface1
$gridProcs.GridColor = $cSurface0
$gridProcs.RowTemplate.Height = 28

foreach ($colSpec in @(
    @{ Name = "AppName";      Header = "Application / Process"; Width = 280 },
    @{ Name = "ProcessCount"; Header = "Instances";             Width = 120 },
    @{ Name = "MemoryMB";     Header = "Working Set (MB)";      Width = 180 },
    @{ Name = "SafetyStatus"; Header = "Safety Tier";           Width = 340 }
)) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $colSpec.Name
    $c.HeaderText = $colSpec.Header
    $c.Width = $colSpec.Width
    [void]$gridProcs.Columns.Add($c)
}
$tabProcs.Controls.Add($gridProcs)

function Refresh-ProcsGrid {
    $top = Get-WBTopProcesses -Top 18
    $gridProcs.Rows.Clear()
    foreach ($p in $top) {
        $idx = $gridProcs.Rows.Add($p.AppName, $p.ProcessCount, "$($p.MemoryMB) MB", $p.SafetyStatus)
        $gridProcs.Rows[$idx].Cells["SafetyStatus"].Style.ForeColor = if ($p.IsProtected) { $cBlue } else { $cGreen }
    }
}

$btnRefreshProcs.Add_Click({ Refresh-ProcsGrid })
$btnKillProc.Add_Click({
    if ($gridProcs.SelectedRows.Count -eq 0) { return }
    $appName = [string]$gridProcs.SelectedRows[0].Cells["AppName"].Value
    $safety  = [string]$gridProcs.SelectedRows[0].Cells["SafetyStatus"].Value
    if ($safety -match "Protected") {
        [System.Windows.Forms.MessageBox]::Show(
            "'$appName' is a Protected System / VPN / AI Developer process and cannot be terminated by WinBreathe.",
            "WinBreathe - Protected Process",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
        return
    }
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Close all running instances of '$appName'? Unsaved work in that app may be lost.",
        "WinBreathe - Confirm End App",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Stop-WBAppGroup -AppName $appName | Out-Null
        Write-GuiConsole "[OK] Terminated application group: $appName" "#a6e3a1"
        Refresh-ProcsGrid
    }
})

# ==============================================================================
# TAB 4: STARTUP APPS MANAGER
# ==============================================================================
$startTopBar = New-Object System.Windows.Forms.Panel
$startTopBar.Location = New-Object System.Drawing.Point(14, 12)
$startTopBar.Size = New-Object System.Drawing.Size(944, 48)
$startTopBar.BackColor = $cMantle
$tabStartup.Controls.Add($startTopBar)

$lblStartNote = New-Object System.Windows.Forms.Label
$lblStartNote.Text = "Manage Windows Sign-In Startup Apps (Disabled items are safely backed up for 1-click re-enable)."
$lblStartNote.Font = $fBody
$lblStartNote.ForeColor = $cSubtext
$lblStartNote.Location = New-Object System.Drawing.Point(12, 14)
$lblStartNote.AutoSize = $true
$startTopBar.Controls.Add($lblStartNote)

$btnRefreshStart = New-WBButton -Text "Refresh"                -X 620 -Y 7 -W 125 -H 34 -BgColor $cSurface0 -FgColor $cText
$btnToggleStart  = New-WBButton -Text "Enable / Disable Item"  -X 755 -Y 7 -W 175 -H 34 -BgColor $cBlue     -FgColor $cCrust
$startTopBar.Controls.AddRange(@($btnRefreshStart, $btnToggleStart))

$gridStart = New-Object System.Windows.Forms.DataGridView
$gridStart.Location = New-Object System.Drawing.Point(14, 68)
$gridStart.Size = New-Object System.Drawing.Size(944, 470)
$gridStart.BackgroundColor = $cMantle
$gridStart.BorderStyle = "None"
$gridStart.AllowUserToAddRows = $false
$gridStart.ReadOnly = $true
$gridStart.RowHeadersVisible = $false
$gridStart.SelectionMode = "FullRowSelect"
$gridStart.MultiSelect = $false
$gridStart.EnableHeadersVisualStyles = $false
$gridStart.ColumnHeadersDefaultCellStyle.BackColor = $cSurface0
$gridStart.ColumnHeadersDefaultCellStyle.ForeColor = $cBlue
$gridStart.ColumnHeadersDefaultCellStyle.Font = $fBold
$gridStart.ColumnHeadersHeight = 32
$gridStart.DefaultCellStyle.BackColor = $cMantle
$gridStart.DefaultCellStyle.ForeColor = $cText
$gridStart.DefaultCellStyle.SelectionBackColor = $cSurface1
$gridStart.GridColor = $cSurface0
$gridStart.RowTemplate.Height = 28

foreach ($colSpec in @(
    @{ Name = "Name";    Header = "Startup Program"; Width = 220 },
    @{ Name = "State";   Header = "Status";          Width = 110 },
    @{ Name = "Scope";   Header = "Registry Scope";  Width = 130 },
    @{ Name = "Command"; Header = "Command Line";    Width = 460 }
)) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $colSpec.Name
    $c.HeaderText = $colSpec.Header
    $c.Width = $colSpec.Width
    [void]$gridStart.Columns.Add($c)
}
$tabStartup.Controls.Add($gridStart)

function Refresh-StartupGrid {
    $items = Get-WBStartupItems
    $gridStart.Rows.Clear()
    foreach ($it in $items) {
        $idx = $gridStart.Rows.Add($it.Name, $it.State, $it.Scope, $it.Command)
        $gridStart.Rows[$idx].Cells["State"].Style.ForeColor = if ($it.State -eq "Enabled") { $cGreen } else { $cYellow }
    }
}

$btnRefreshStart.Add_Click({ Refresh-StartupGrid })
$btnToggleStart.Add_Click({
    if ($gridStart.SelectedRows.Count -eq 0) { return }
    $name  = [string]$gridStart.SelectedRows[0].Cells["Name"].Value
    $state = [string]$gridStart.SelectedRows[0].Cells["State"].Value
    $scope = [string]$gridStart.SelectedRows[0].Cells["Scope"].Value
    $targetEnable = ($state -ne "Enabled")
    if (Set-WBStartupItemState -Name $name -Scope $scope -Enable $targetEnable) {
        Write-GuiConsole "[OK] Startup item '$name' ($scope) -> Enabled=$targetEnable" "#a6e3a1"
        Refresh-StartupGrid
    }
})

# ==============================================================================
# TAB 5: STATUS, UPDATE GUARD & SNAPSHOT UNDO
# ==============================================================================
$guardCard = New-Object System.Windows.Forms.Panel
$guardCard.Location = New-Object System.Drawing.Point(14, 14)
$guardCard.Size = New-Object System.Drawing.Size(944, 118)
$guardCard.BackColor = $cMantle
$tabStatus.Controls.Add($guardCard)

$lblGuardTitle = New-Object System.Windows.Forms.Label
$lblGuardTitle.Text = "BACKUPS & UNDO (ADMIN REQUIRED) | NEW GUARD INSTALLS DISABLED"
$lblGuardTitle.Font = $fH2
$lblGuardTitle.ForeColor = $cBlue
$lblGuardTitle.Location = New-Object System.Drawing.Point(16, 12)
$lblGuardTitle.AutoSize = $true
$guardCard.Controls.Add($lblGuardTitle)

$lblGuardStatus = New-Object System.Windows.Forms.Label
$lblGuardStatus.Font = $fBody
$lblGuardStatus.ForeColor = $cText
$lblGuardStatus.Location = New-Object System.Drawing.Point(16, 40)
$lblGuardStatus.AutoSize = $true
$guardCard.Controls.Add($lblGuardStatus)

$btnInstGuard = New-WBButton -Text "Guard Unavailable"     -X 16  -Y 72 -W 170 -H 34 -BgColor $cTeal     -FgColor $cCrust
$btnRemGuard  = New-WBButton -Text "Remove Boot Guard"      -X 196 -Y 72 -W 170 -H 34 -BgColor $cSurface0 -FgColor $cText
$btnTakeSnap  = New-WBButton -Text "Save Manual Snapshot"   -X 386 -Y 72 -W 175 -H 34 -BgColor $cSurface0 -FgColor $cBlue
$btnUndoSnap  = New-WBButton -Text "Undo (Restore Backup)"  -X 571 -Y 72 -W 180 -H 34 -BgColor $cYellow   -FgColor $cCrust
$btnResetDef  = New-WBButton -Text "Reset Unavailable"   -X 761 -Y 72 -W 168 -H 34 -BgColor $cPeach    -FgColor $cCrust
$btnInstGuard.Enabled = $false
$btnResetDef.Enabled = $false
$guardCard.Controls.AddRange(@($btnInstGuard, $btnRemGuard, $btnTakeSnap, $btnUndoSnap, $btnResetDef))

$gridDrift = New-Object System.Windows.Forms.DataGridView
$gridDrift.Location = New-Object System.Drawing.Point(14, 142)
$gridDrift.Size = New-Object System.Drawing.Size(944, 396)
$gridDrift.BackgroundColor = $cMantle
$gridDrift.BorderStyle = "None"
$gridDrift.AllowUserToAddRows = $false
$gridDrift.ReadOnly = $true
$gridDrift.RowHeadersVisible = $false
$gridDrift.SelectionMode = "FullRowSelect"
$gridDrift.MultiSelect = $false
$gridDrift.EnableHeadersVisualStyles = $false
$gridDrift.ColumnHeadersDefaultCellStyle.BackColor = $cSurface0
$gridDrift.ColumnHeadersDefaultCellStyle.ForeColor = $cBlue
$gridDrift.ColumnHeadersDefaultCellStyle.Font = $fBold
$gridDrift.ColumnHeadersHeight = 32
$gridDrift.DefaultCellStyle.BackColor = $cMantle
$gridDrift.DefaultCellStyle.ForeColor = $cText
$gridDrift.DefaultCellStyle.SelectionBackColor = $cSurface1
$gridDrift.GridColor = $cSurface0
$gridDrift.RowTemplate.Height = 28

foreach ($colSpec in @(
    @{ Name = "Id";      Header = "Tweak ID";      Width = 160 },
    @{ Name = "Title";   Header = "Optimization";  Width = 340 },
    @{ Name = "State";   Header = "Drift Status";  Width = 130 },
    @{ Name = "Current"; Header = "Live OS Value"; Width = 150 },
    @{ Name = "Target";  Header = "Target Value";  Width = 140 }
)) {
    $c = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $c.Name = $colSpec.Name
    $c.HeaderText = $colSpec.Header
    $c.Width = $colSpec.Width
    [void]$gridDrift.Columns.Add($c)
}
$tabStatus.Controls.Add($gridDrift)

function Refresh-StatusTab {
    $guard = Get-WBUpdateGuardStatus
    $paths = Get-WBPaths
    $hasSnap = Test-Path $paths.LatestBackup
    $snapText = if ($hasSnap) { "Latest Backup Available" } else { "No Snapshot Yet" }
    $lblGuardStatus.Text = "Update Guard Task: $($guard.State) (Last Run: $($guard.LastRunTime))   |   Snapshot Status: $snapText"

    $states = Test-WBTweakState -ProfileName ([string]$cmbProfile.SelectedItem)
    $gridDrift.Rows.Clear()
    foreach ($s in $states) {
        $idx = $gridDrift.Rows.Add($s.Id, $s.Title, $s.State, $s.CurrentValue, $s.TargetValue)
        $gridDrift.Rows[$idx].Cells["State"].Style.ForeColor = switch ($s.State) {
            "Applied"       { $cGreen }
            "NotApplicable" { $cSubtext }
            default         { $cYellow }
        }
    }
}

# ==============================================================================
# TAB 6: HELP & DOCUMENTATION GUIDE
# ==============================================================================
$helpBox = New-Object System.Windows.Forms.RichTextBox
$helpBox.Location = New-Object System.Drawing.Point(14, 14)
$helpBox.Size = New-Object System.Drawing.Size(944, 524)
$helpBox.BackColor = $cMantle
$helpBox.ForeColor = $cText
$helpBox.Font = $fBody
$helpBox.ReadOnly = $true
$helpBox.BorderStyle = "None"
$helpBox.Text = @"
WINBREATHE v2.1.2 - UNIVERSAL WINDOWS ADAPTIVE ENGINE (7 | 8.1 | 10 | 11)

1. AUTOMATIC OS & HARDWARE DETECTION
   - WinBreathe inspects your exact Windows build and storage type at launch and tailors tweaks:
     * Windows 7  : SuperFetch & Prefetcher boot-only (fixes 100% HDD thrashing), DWM Aero glass RAM trimming, NTFS Last-Access write churn disabled, Application Experience & WER stopped, contiguous pagefile locked.
     * Windows 8.1: SuperFetch & Prefetcher boot-only, NTFS Last-Access churn disabled, Program Compatibility Assistant stopped, contiguous pagefile locked.
     * Windows 10 : In-RAM Memory Compression + Page Combining enabled, DiagTrack silenced, contiguous pagefile locked, browser background bloat cut.
     * Windows 11 : Everything in Win10 + Windows Copilot disabled, Windows 11 Widgets board WebView2 background daemon stopped, modern telemetry silenced.

2. HARDWARE-ADAPTIVE PROFILES
   - Conservative : Zero-impact browser background cuts and memory compression check. Ideal for 16 GB+ SSD PCs.
   - Balanced     : Recommended for 8-12 GB RAM laptops and HDDs. Locks Edge/Chrome background bloat, disables Widgets/Telemetry, enables Memory Compression + Page Combining (Win10/11), and locks a contiguous pagefile.
   - Aggressive   : For 4-6 GB RAM or heavy disk load. Adds Store background app restrictions and disables transparency effects.

3. TRUE SNAPSHOT UNDO vs. STOCK WINDOWS RESET
   - Before WinBreathe applies changes, it captures your exact current registry values, service startup types, MMAgent flags, and pagefile settings to:
     %ProgramFiles%\WinBreathe-State\<your SID>\latest.json (admin access required)
   - Clicking 'Undo (Restore Backup)' restores your exact prior state (including removing policy keys that did not exist before).
   - Generic factory reset and new boot guard installs are unavailable in this security patch.
   - Memory Check never terminates apps. Older snapshots require manual review; they are not automatically restored.

4. TIER-1 PROTECTED PROCESSES (NEVER TOUCHED)
   - WinBreathe never calls EmptyWorkingSet() (which forces active memory onto slow disks) and never terminates:
     * Windows Kernel, Explorer, DWM, Audio, or Windows Defender (MsMpEng)
     * VPN & Network Tunnels (OpenVPN Connect, WireGuard, Tailscale)
     * AI & Developer Stacks (Antigravity, ChatGPT, Codex, Claude, VS Code, Cursor, Node.js, Python, Git)

5. WINDOWS SEARCH INDEXER (WSearch) IS OPT-IN
   - Disabling Windows Search stops background disk indexing on mechanical HDDs, but also disables instant file search in Start and Outlook.
   - Therefore, 'svc.wsearch' is unchecked by default in all profiles. Only check it in the 'Optimize Tweaks' tab if you use an alternative file searcher such as Voidtools Everything.

6. COMMAND-LINE AUTOMATION (src\WinBreathe.ps1)
   - Preview only (Dry-Run) : .\src\WinBreathe.ps1 -Profile Balanced -WhatIf
   - Target another OS mode : .\src\WinBreathe.ps1 -PreviewOS Win7
   - Apply Balanced Profile : .\src\WinBreathe.ps1 -Profile Balanced
   - Live Drift Status      : .\src\WinBreathe.ps1 -Status
   - Undo from Snapshot     : .\src\WinBreathe.ps1 -Undo
   - Export HTML/MD Report  : .\src\WinBreathe.ps1 -ExportReport
"@
$tabHelp.Controls.Add($helpBox)

# ==============================================================================
# Runspace-Safe Non-Blocking CLI Runner (Solves B1, B2, B3, B4, WB-01)
# ==============================================================================
$script:ActiveProcess = $null
$script:ProcessOutput = $null

$procTimer = New-Object System.Windows.Forms.Timer
$procTimer.Interval = 120
$procTimer.Add_Tick({
    if ($null -eq $script:ActiveProcess) { return }
    try {
        for ($lineNumber = 0; $lineNumber -lt 200; $lineNumber++) {
            $line = $script:ProcessOutput.ReadAvailable()
            if ($null -eq $line) { break }
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                $col = "#cdd6f4"
                if ($line -match "\[ERROR\]")                { $col = "#f38ba8" }
                elseif ($line -match "\[WARN\]")              { $col = "#f9e2af" }
                elseif ($line -match "\[PREVIEW\]")           { $col = "#cba6f7" }
                elseif ($line -match "\[OK\]")                { $col = "#a6e3a1" }
                elseif ($line -match "\[HEAD\]|===")          { $col = "#89b4fa" }
                Write-GuiConsole $line $col
            }
        }
        if ($script:ProcessOutput.Complete) {
            $procTimer.Stop()
            $exitCode = $script:ActiveProcess.ExitCode
            if ($exitCode -ne 0) { Write-GuiConsole "[ERROR] Task finished with errors (exit $exitCode). Review the lines above." '#f38ba8' }
            $script:ProcessOutput.Dispose()
            $script:ProcessOutput = $null
            $script:ActiveProcess.Dispose()
            $script:ActiveProcess = $null
            $btnQuickOpt.Enabled   = $true
            $btnPreviewSel.Enabled = $true
            $btnApplySel.Enabled   = $true
            Refresh-TweaksGrid
            Refresh-StatusTab
            Update-DashboardMetrics
        }
    } catch {
        $procTimer.Stop()
        if ($null -ne $script:ActiveProcess) {
            $script:ActiveProcess.Dispose()
            $script:ActiveProcess = $null
        }
        $btnQuickOpt.Enabled   = $true
        $btnPreviewSel.Enabled = $true
        $btnApplySel.Enabled   = $true
    }
})

function Start-WBAsyncCommand {
    param(
        [string]$CliArguments,
        [string]$BannerText
    )
    if ($null -ne $script:ActiveProcess) {
        Write-GuiConsole "[WARN] Another task is currently running. Please wait..." "#f9e2af"
        return
    }

    $tabs.SelectedTab = $tabDash
    Write-GuiConsole "----------------------------------------------------------------------" "#45475a"
    Write-GuiConsole ">>> $BannerText" "#89b4fa"

    $btnQuickOpt.Enabled   = $false
    $btnPreviewSel.Enabled = $false
    $btnApplySel.Enabled   = $false

    # EncodedCommand can serialize progress to stderr as CLIXML. Suppress
    # progress and request plain text; warnings/errors still reach the console.
    $escapedScript = $cliScript.Replace("'", "''")
    $psCmd = "`$ProgressPreference='SilentlyContinue'; `$global:LASTEXITCODE=0; & '$escapedScript' $CliArguments *>&1 | ForEach-Object { `$_.ToString() }; exit `$LASTEXITCODE"

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell\v1.0\powershell.exe'
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($psCmd))
    $psi.Arguments = "-NoProfile -NonInteractive -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true

    try {
        $script:ActiveProcess = [System.Diagnostics.Process]::Start($psi)
        $script:ProcessOutput = New-Object WBProcessOutput($script:ActiveProcess)
        $procTimer.Start()
    } catch {
        Write-GuiConsole "[ERROR] Could not start the task: $($_.Exception.Message)" '#f38ba8'
        if ($null -ne $script:ActiveProcess) { $script:ActiveProcess.Dispose(); $script:ActiveProcess = $null }
        $btnQuickOpt.Enabled = $true; $btnPreviewSel.Enabled = $true; $btnApplySel.Enabled = $true
    }
}

# ==============================================================================
# Button Actions Wiring
# ==============================================================================
function Get-CheckedTweakIds {
    $ids = @()
    foreach ($row in $gridTweaks.Rows) {
        if ([bool]$row.Cells["Apply"].Value) {
            $ids += [string]$row.Cells["Id"].Value
        }
    }
    return $ids
}

$btnQuickOpt.Add_Click({
    $prof = [string]$cmbProfile.SelectedItem
    Start-WBAsyncCommand -CliArguments "-Profile $prof" -BannerText "Running Click Optimization ($prof Profile)..."
})

$btnPreviewSel.Add_Click({
    $prof = [string]$cmbProfile.SelectedItem
    $ids  = Get-CheckedTweakIds
    if ($ids.Count -eq 0) {
        Write-GuiConsole "[WARN] No tweaks are checked in the Optimize Tweaks tab." "#f9e2af"
        return
    }
    $targetOS = Get-SelectedTargetOS
    $osArg = if (-not [string]::IsNullOrEmpty($targetOS)) { "-TargetOS $targetOS" } else { "" }
    $idArg = ($ids | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ","
    Start-WBAsyncCommand -CliArguments "-Profile $prof -TweakIds @($idArg) $osArg -WhatIf" -BannerText "Previewing $($ids.Count) Selected Tweaks (-WhatIf Dry-Run for $($cmbOS.SelectedItem))..."
})

$btnApplySel.Add_Click({
    $prof = [string]$cmbProfile.SelectedItem
    $ids  = Get-CheckedTweakIds
    if ($ids.Count -eq 0) {
        Write-GuiConsole "[WARN] No tweaks are checked in the Optimize Tweaks tab." "#f9e2af"
        return
    }
    # Safety: Live apply strictly targets the host machine. Never pass simulated OS into live execution.
    $idArg = ($ids | ForEach-Object { "'$($_.Replace("'", "''"))'" }) -join ","
    Start-WBAsyncCommand -CliArguments "-Profile $prof -TweakIds @($idArg)" -BannerText "Applying $($ids.Count) Selected Tweaks to host system ($prof Profile)..."
})

$btnQuickFlush.Add_Click({
    Start-WBAsyncCommand -CliArguments "-Flush" -BannerText "Checking memory without closing apps..."
})

$btnQuickRep.Add_Click({
    $prof = [string]$cmbProfile.SelectedItem
    $rep = Export-WBReport -ProfileName $prof
    Write-GuiConsole "[OK] Exported HTML Report: $($rep.HtmlPath)" "#a6e3a1"
    Write-GuiConsole "[OK] Exported Markdown Report: $($rep.MarkdownPath)" "#a6e3a1"
    if (Test-Path $rep.HtmlPath) {
        Start-Process $rep.HtmlPath -ErrorAction SilentlyContinue
    }
})

$btnInstGuard.Add_Click({
    $prof = [string]$cmbProfile.SelectedItem
    Start-WBAsyncCommand -CliArguments "-InstallGuard -Profile $prof" -BannerText "Installing Hardened SYSTEM Update Guard ($prof)..."
})

$btnRemGuard.Add_Click({
    Start-WBAsyncCommand -CliArguments "-RemoveGuard" -BannerText "Removing Windows Update Persistence Guard..."
})

$btnTakeSnap.Add_Click({
    Start-WBAsyncCommand -CliArguments "-Snapshot" -BannerText "Capturing current system registry, service, and pagefile snapshot..."
})

$btnUndoSnap.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Restore your exact pre-optimization settings from the latest snapshot backup?",
        "WinBreathe - Confirm Snapshot Undo",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Question
    )
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-WBAsyncCommand -CliArguments "-Undo" -BannerText "Restoring exact pre-optimization state from snapshot..."
    }
})

$btnResetDef.Add_Click({
    $confirm = [System.Windows.Forms.MessageBox]::Show(
        "Reset all policies, services, and pagefile settings to Windows 11 stock factory defaults?",
        "WinBreathe - Confirm Reset to Windows Defaults",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )
    if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
        Start-WBAsyncCommand -CliArguments "-ResetDefaults" -BannerText "Resetting all tweaks to stock Windows 11 defaults..."
    }
})

# ==============================================================================
# Live Telemetry Timer (3s interval) & Deterministic Cleanup (WB-05)
# ==============================================================================
function Update-DashboardMetrics {
    $snap = Get-WBMemorySnapshot
    $script:LastSnap = $snap
    $script:RamHistory.Add([int]$snap.LoadPercent)
    $script:UsedHistory.Add([int]$snap.UsedRAMMB)
    while ($script:RamHistory.Count -gt 60) {
        $script:RamHistory.RemoveAt(0)
        $script:UsedHistory.RemoveAt(0)
    }
    if (-not $gaugeCanvas.IsDisposed) { $gaugeCanvas.Invalidate() }
    if (-not $chartCanvas.IsDisposed) { $chartCanvas.Invalidate() }
}

$telemetryTimer = New-Object System.Windows.Forms.Timer
$telemetryTimer.Interval = 3000
$telemetryTimer.Add_Tick({ Update-DashboardMetrics })
$telemetryTimer.Start()

# Initial Data Load
Refresh-TweaksGrid
Refresh-ProcsGrid
Refresh-StartupGrid
Refresh-StatusTab
Update-DashboardMetrics

Write-GuiConsole "WinBreathe v2.1.2 initialized." "#89b4fa"
Write-GuiConsole "Detected: $($sysProfile.OSCaption) | $($sysProfile.TotalRAMMB) MB RAM | $($sysProfile.DiskModel) ($($sysProfile.DiskMediaType))" "#94e2d5"
Write-GuiConsole "Recommended Profile: $($sysProfile.RecommendedProfile) | Tier-1 Protected Processes Active." "#a6e3a1"
Write-GuiConsole "Tip: Use 'Optimize Tweaks' -> 'Preview Selected (-WhatIf)' to inspect changes before applying." "#cdd6f4"

$form.Add_FormClosing({
    param($sender, $eventArgs)
    if ($null -ne $script:ActiveProcess) {
        $eventArgs.Cancel = $true
        Write-GuiConsole '[WARN] Wait for the running task to finish before closing this window.' '#f9e2af'
    }
})

try {
    [void]$form.ShowDialog()
} finally {
    $telemetryTimer.Stop()
    $telemetryTimer.Dispose()
    $procTimer.Stop()
    $procTimer.Dispose()
    if ($null -ne $script:ActiveProcess) {
        if ($null -ne $script:ProcessOutput) { $script:ProcessOutput.Dispose() }
        $script:ActiveProcess.Dispose()
    }
    foreach ($d in $script:GdiDisposables) {
        try { $d.Dispose() } catch {}
    }
    $form.Dispose()
}
