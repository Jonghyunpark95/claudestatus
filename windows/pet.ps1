<#
    Claude 마스코트 — Windows 데스크톱 펫

    테두리 없는 투명 창을 바탕화면 위에 띄우고 그 안에 도트 캐릭터를 그린다.
    캐릭터 몸통 위에서만 마우스를 받고, 투명한 부분은 아래 창으로 클릭이 통과한다.
    macOS 판(ClaudeMascot.app)과 같은 동작이다.

    WebView2 안 쓴다. 브라우저 안 띄운다. 윈도우에 기본으로 들어있는
    PowerShell + WPF 만 쓰고, 캐릭터 도트는 public\sprite.js 를 읽어서 직접 그린다.
    (그래서 맥 버전과 캐릭터가 항상 같다)

    실행:  powershell -ExecutionPolicy Bypass -File windows\pet.ps1
    보통은 windows\start.cmd 로 실행한다.
#>

param(
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName System.Net.Http

# 클릭 통과(WS_EX_TRANSPARENT) 토글용
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class MascotNative {
    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TRANSPARENT = 0x20;
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);
    // 트레이 메뉴는 우리 창이 포그라운드가 아니면 딴 데를 눌러도 안 닫힌다
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    // Icon.FromHandle 은 HICON 소유권을 안 가져가므로 직접 지워야 한다
    [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr hIcon);
}
"@

# ---------------------------------------------------------------- 경로 / 설정

$Root         = Split-Path -Parent $PSScriptRoot
$SpriteFile   = Join-Path $Root 'public\sprite.js'
$SettingsDir  = Join-Path $env:APPDATA 'ClaudeMascot'
$SettingsFile = Join-Path $SettingsDir 'settings.json'

if ($Port -le 0) {
    if ($env:MASCOT_PORT) { $Port = [int]$env:MASCOT_PORT } else { $Port = 4573 }
}
$BaseUrl = "http://127.0.0.1:$Port"

$Sizes = @{
    'tiny'   = @{ w = 88;  h = 101; title = '아주 작게' }
    'small'  = @{ w = 132; h = 152; title = '작게' }
    'medium' = @{ w = 176; h = 202; title = '보통' }
    'large'  = @{ w = 232; h = 264; title = '크게' }
}
$SizeOrder = @('tiny', 'small', 'medium', 'large')

$Settings = @{ size = 'tiny'; left = $null; top = $null; onTop = $true; clickThrough = $false }
if (Test-Path $SettingsFile) {
    try {
        $loaded = Get-Content $SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($k in @('size', 'left', 'top', 'onTop', 'clickThrough')) {
            if ($null -ne $loaded.$k) { $Settings[$k] = $loaded.$k }
        }
    } catch { }   # 설정이 깨졌으면 기본값으로 간다
}
if (-not $Sizes.ContainsKey([string]$Settings.size)) { $Settings.size = 'tiny' }

function Save-Settings {
    try {
        if (-not (Test-Path $SettingsDir)) { New-Item -ItemType Directory -Path $SettingsDir -Force | Out-Null }
        ($Settings | ConvertTo-Json) | Set-Content $SettingsFile -Encoding UTF8
    } catch { }
}

# ---------------------------------------------------------------- 스프라이트 로드

if (-not (Test-Path $SpriteFile)) {
    [System.Windows.MessageBox]::Show("캐릭터 파일을 찾을 수 없습니다:`n$SpriteFile", 'Claude 마스코트') | Out-Null
    exit 1
}
$raw   = Get-Content $SpriteFile -Raw -Encoding UTF8
$anchor= $raw.IndexOf('const SPRITE')
$start = $raw.IndexOf('{', $anchor)
$end   = $raw.LastIndexOf('}')
$SP    = $raw.Substring($start, $end - $start + 1) | ConvertFrom-Json

$PXU  = [double]$SP.px
$GRID = [double]$SP.grid
$Side = $PXU * $GRID     # 140

$Brushes = @{}
foreach ($name in $SP.palette.PSObject.Properties.Name) {
    $c = [System.Windows.Media.ColorConverter]::ConvertFromString($SP.palette.$name)
    $b = New-Object System.Windows.Media.SolidColorBrush $c
    $b.Freeze()
    $Brushes[$name] = $b
}

# 몸통 색은 상태에 따라 바뀐다
$BodyBrushes = @{ 'default' = $Brushes['o'] }
foreach ($st in $SP.states.PSObject.Properties.Name) {
    $hex = $SP.states.$st.body
    if ($hex) {
        $c = [System.Windows.Media.ColorConverter]::ConvertFromString($hex)
        $b = New-Object System.Windows.Media.SolidColorBrush $c
        $b.Freeze()
        $BodyBrushes[$st] = $b
    }
}

# ---------------------------------------------------------------- 도트 → 도형

# {top, rows} 한 덩어리를 Canvas 로 그린다. 가로로 이어지는 같은 색은 한 사각형으로 합친다.
function New-DotLayer($block) {
    $layer = New-Object System.Windows.Controls.Canvas
    $layer.Width = $Side
    $layer.Height = $Side
    if ($null -eq $block) { return $layer }

    for ($r = 0; $r -lt $block.rows.Count; $r++) {
        $row = [string]$block.rows[$r]
        $y = ([double]$block.top + $r) * $PXU
        $x = 0
        while ($x -lt $row.Length) {
            $ch = [string]$row[$x]
            if ($ch -eq '.') { $x++; continue }
            $run = 1
            while (($x + $run) -lt $row.Length -and [string]$row[$x + $run] -eq $ch) { $run++ }

            $rect = New-Object System.Windows.Shapes.Rectangle
            $rect.Width  = $run * $PXU
            $rect.Height = $PXU
            $rect.Fill   = $Brushes[$ch]
            if ($ch -eq 'o') { $rect.Tag = 'body' }   # 상태별 색 교체 대상
            [System.Windows.Controls.Canvas]::SetLeft($rect, $x * $PXU)
            [System.Windows.Controls.Canvas]::SetTop($rect, $y)
            $layer.Children.Add($rect) | Out-Null
            $x += $run
        }
    }
    return $layer
}

# ---------------------------------------------------------------- 창 구성

$win = New-Object System.Windows.Window
$win.WindowStyle          = 'None'
$win.AllowsTransparency   = $true
$win.Background           = [System.Windows.Media.Brushes]::Transparent
$win.ShowInTaskbar        = $false
$win.ResizeMode           = 'NoResize'
$win.Topmost              = [bool]$Settings.onTop
$win.SizeToContent        = 'Manual'
$win.Title                = 'Claude 마스코트'

$rootGrid = New-Object System.Windows.Controls.Grid
$win.Content = $rootGrid

# 캐릭터 (Viewbox 로 창 크기에 맞춰 확대/축소)
$charCanvas = New-Object System.Windows.Controls.Canvas
$charCanvas.Width  = $Side
$charCanvas.Height = $Side

$hop = New-Object System.Windows.Controls.Canvas   # 통통 튀는 움직임을 주는 그룹
$hop.Width = $Side; $hop.Height = $Side
$hopShift = New-Object System.Windows.Media.TranslateTransform
$hop.RenderTransform = $hopShift
$charCanvas.Children.Add($hop) | Out-Null

$armsLayer = New-DotLayer $SP.armsUp
$legsALayer = New-DotLayer $SP.legsA
$legsBLayer = New-DotLayer $SP.legsB
$bodyLayer  = New-DotLayer $SP.body
$hop.Children.Add($armsLayer)  | Out-Null
$hop.Children.Add($legsALayer) | Out-Null
$hop.Children.Add($legsBLayer) | Out-Null
$hop.Children.Add($bodyLayer)  | Out-Null

$FaceLayers = @{}
foreach ($f in $SP.faces.PSObject.Properties.Name) {
    $l = New-DotLayer $SP.faces.$f
    $l.Visibility = 'Collapsed'
    $FaceLayers[$f] = $l
    $hop.Children.Add($l) | Out-Null
}

$PropLayers = @{}
foreach ($p in $SP.props.PSObject.Properties.Name) {
    $l = New-DotLayer $SP.props.$p
    $l.Visibility = 'Collapsed'
    $PropLayers[$p] = $l
    $charCanvas.Children.Add($l) | Out-Null   # 소품은 hop 밖 (같이 안 흔들리게)
}

$viewbox = New-Object System.Windows.Controls.Viewbox
$viewbox.Child = $charCanvas
$viewbox.Stretch = 'Uniform'
$viewbox.VerticalAlignment = 'Top'
$rootGrid.Children.Add($viewbox) | Out-Null

# 캡션 (어떤 바탕화면 위에서도 읽히도록 불투명 알약)
$capBorder = New-Object System.Windows.Controls.Border
$capBorder.CornerRadius     = New-Object System.Windows.CornerRadius 9
$capBorder.Padding          = New-Object System.Windows.Thickness 8, 2, 8, 2
$capBorder.BorderThickness  = New-Object System.Windows.Thickness 1
$capBorder.HorizontalAlignment = 'Center'
$capBorder.VerticalAlignment   = 'Bottom'
$capBorder.Margin           = New-Object System.Windows.Thickness 2, 0, 2, 3
$capText = New-Object System.Windows.Controls.TextBlock
$capText.FontWeight = 'SemiBold'
$capText.TextTrimming = 'CharacterEllipsis'
$capBorder.Child = $capText
$capBorder.Visibility = 'Collapsed'   # 내용이 생기기 전엔 빈 알약을 띄우지 않는다
$rootGrid.Children.Add($capBorder) | Out-Null

# 세션 개수 배지
$badgeBorder = New-Object System.Windows.Controls.Border
$badgeBorder.CornerRadius = New-Object System.Windows.CornerRadius 20
$badgeBorder.Padding      = New-Object System.Windows.Thickness 5, 0, 5, 1
$badgeBorder.HorizontalAlignment = 'Right'
$badgeBorder.VerticalAlignment   = 'Top'
$badgeBorder.Visibility   = 'Collapsed'
$badgeText = New-Object System.Windows.Controls.TextBlock
$badgeText.FontWeight = 'Bold'
$badgeText.Foreground = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString('#1a1310'))
$badgeBorder.Child = $badgeText
$rootGrid.Children.Add($badgeBorder) | Out-Null

function Set-PetSize([string]$key) {
    $s = $Sizes[$key]
    $win.Width  = $s.w
    $win.Height = $s.h
    $viewbox.Height = $s.h * 0.82
    $viewbox.Margin = New-Object System.Windows.Thickness 0, ($s.h * 0.02), 0, 0
    $f = [Math]::Max(7.5, [Math]::Min(12.0, $s.w * 0.057))
    $capText.FontSize   = $f
    $badgeText.FontSize = $f
    $Settings.size = $key
}
Set-PetSize ([string]$Settings.size)

$win.WindowStartupLocation = 'Manual'

# 위치. 저장된 값이 없으면 주 화면 오른쪽 아래.
# WorkingArea 는 실제 픽셀이고 WPF 의 Left/Top 은 DPI 독립 단위라, 배율이 100%가
# 아닌 화면에서는 그냥 쓰면 어긋난다. 창이 만들어진 뒤 변환해서 넣는다.
function Move-ToDefaultCorner {
    $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $sx = 1.0; $sy = 1.0
    try {
        $src = [System.Windows.PresentationSource]::FromVisual($win)
        if ($src -and $src.CompositionTarget) {
            $m = $src.CompositionTarget.TransformFromDevice
            $sx = $m.M11; $sy = $m.M22
        }
    } catch { }
    $win.Left = ($wa.Right  * $sx) - $win.Width  - 28
    $win.Top  = ($wa.Bottom * $sy) - $win.Height - 28
}

# ---------------------------------------------------------------- 상태 반영

$script:State        = 'idle'
$script:SessionCount = 0
$script:Caption      = ''
$script:Frame        = 0

$CapColors = @{
    'default' = @{ bg = '#E61C1814'; border = '#33FFFFFF'; fg = '#ECE4DA' }
    'waiting' = @{ bg = '#F03A2C0E'; border = '#99F2C14E'; fg = '#FFD977' }
    'done'    = @{ bg = '#F0142C1F'; border = '#8063C98D'; fg = '#9FE8BD' }
}

function Apply-State([string]$state) {
    if (-not ($SP.states.PSObject.Properties.Name -contains $state)) { $state = 'idle' }
    $def = $SP.states.$state

    foreach ($k in $FaceLayers.Keys) {
        if ($k -eq $def.face) { $FaceLayers[$k].Visibility = 'Visible' }
        else { $FaceLayers[$k].Visibility = 'Collapsed' }
    }
    $active = @($def.props)
    foreach ($k in $PropLayers.Keys) {
        if ($active -contains $k) { $PropLayers[$k].Visibility = 'Visible' }
        else { $PropLayers[$k].Visibility = 'Collapsed' }
    }
    if ($def.arms) { $armsLayer.Visibility = 'Visible' } else { $armsLayer.Visibility = 'Collapsed' }

    # 몸통 색
    $brush = $BodyBrushes['default']
    if ($BodyBrushes.ContainsKey($state)) { $brush = $BodyBrushes[$state] }
    foreach ($child in $bodyLayer.Children) { $child.Fill = $brush }
    foreach ($child in $legsALayer.Children) { $child.Fill = $brush }
    foreach ($child in $legsBLayer.Children) { $child.Fill = $brush }
    foreach ($child in $armsLayer.Children)  { $child.Fill = $brush }

    # 캡션 색
    $c = $CapColors['default']
    if ($CapColors.ContainsKey($state)) { $c = $CapColors[$state] }
    $capBorder.Background  = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($c.bg))
    $capBorder.BorderBrush = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($c.border))
    $capText.Foreground    = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($c.fg))

    $badgeHex = '#D97757'
    if ($state -eq 'waiting') { $badgeHex = '#F2C14E' }
    $badgeBorder.Background = New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($badgeHex))

    $script:State = $state
    Update-Tray
}

# ---------------------------------------------------------------- 애니메이션
# 도트 캐릭터라 부드럽게 말고 한 칸씩 툭툭 끊어 움직인다 (맥 CSS 의 steps() 와 같은 느낌)

$animTimer = New-Object System.Windows.Threading.DispatcherTimer
$animTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$animTimer.Add_Tick({
    $script:Frame++
    $f = $script:Frame
    $anim = 'breathe'
    if ($SP.states.PSObject.Properties.Name -contains $script:State) { $anim = $SP.states.($script:State).anim }
    $odd = ($f % 2) -eq 1

    switch ($anim) {
        'walk' {
            if ($odd) { $hopShift.Y = -3 } else { $hopShift.Y = 0 }
            if ($odd) {
                $legsALayer.Visibility = 'Collapsed'; $legsBLayer.Visibility = 'Visible'
            } else {
                $legsALayer.Visibility = 'Visible';   $legsBLayer.Visibility = 'Collapsed'
            }
            if ($PropLayers.ContainsKey('spark')) {
                if ($odd) { $PropLayers['spark'].Opacity = 0.15 } else { $PropLayers['spark'].Opacity = 1 }
            }
        }
        'jump' {
            if ($odd) { $hopShift.Y = -9 } else { $hopShift.Y = 0 }
            $legsALayer.Visibility = 'Visible'; $legsBLayer.Visibility = 'Collapsed'
            if ($PropLayers.ContainsKey('q')) {
                if ($odd) { $PropLayers['q'].Opacity = 0.75 } else { $PropLayers['q'].Opacity = 1 }
            }
        }
        'cheer' {
            $m = $f % 8
            if ($m -eq 0 -or $m -eq 1) { $hopShift.Y = -6 } else { $hopShift.Y = 0 }
            $legsALayer.Visibility = 'Visible'; $legsBLayer.Visibility = 'Collapsed'
        }
        default {
            # breathe — 아주 천천히 한 칸
            if (([int]($f / 10)) % 2 -eq 1) { $hopShift.Y = 2 } else { $hopShift.Y = 0 }
            $legsALayer.Visibility = 'Visible'; $legsBLayer.Visibility = 'Collapsed'
            if ($PropLayers.ContainsKey('zzz')) {
                $z = $f % 9
                if ($z -lt 3)      { $PropLayers['zzz'].Opacity = 1.0 }
                elseif ($z -lt 6)  { $PropLayers['zzz'].Opacity = 0.85 }
                else               { $PropLayers['zzz'].Opacity = 0.45 }
            }
        }
    }
})

# ---------------------------------------------------------------- 서버 폴링
# UI 를 멈추지 않도록 비동기 요청을 걸어두고 완료됐을 때만 읽는다.

$http = New-Object System.Net.Http.HttpClient
$http.Timeout = [TimeSpan]::FromSeconds(3)
$script:Pending = $null

function Update-FromSnapshot($snap) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $best = $null; $bestRank = -1
    foreach ($s in $snap.sessions) {
        $st = $s.state
        # 서버 원시 상태 보정 (맥 판의 effectiveState 와 같은 규칙)
        if (($st -eq 'working' -or $st -eq 'thinking') -and ($now - $s.updated) -gt 300000) { $st = 'stale' }
        if ($st -eq 'done' -and ($now - $s.since) -gt 180000) { $st = 'idle' }
        $rank = 0
        if ($SP.states.PSObject.Properties.Name -contains $st) { $rank = [int]$SP.states.$st.rank }
        if ($rank -gt $bestRank) { $bestRank = $rank; $best = @{ s = $s; st = $st } }
    }

    $count = 0
    if ($snap.sessions) { $count = @($snap.sessions).Count }
    $script:SessionCount = $count

    if ($null -eq $best) {
        if ($script:State -ne 'idle') { Apply-State 'idle' }
        $capText.Text = ''
        $capBorder.Visibility = 'Collapsed'
        $badgeBorder.Visibility = 'Collapsed'
        return
    }

    if ($script:State -ne $best.st) { Apply-State $best.st }

    $label = $SP.states.($best.st).label
    $cap = $label
    if ($best.st -ne 'waiting' -and $win.Width -ge 115 -and $best.s.project) {
        $cap = "$label · $($best.s.project)"
    }
    $capText.Text = $cap
    $capBorder.Visibility = 'Visible'

    if ($count -gt 1) {
        $badgeText.Text = [string]$count
        $badgeBorder.Visibility = 'Visible'
    } else {
        $badgeBorder.Visibility = 'Collapsed'
    }
}

$pollTimer = New-Object System.Windows.Threading.DispatcherTimer
$pollTimer.Interval = [TimeSpan]::FromMilliseconds(500)
$pollTimer.Add_Tick({
    if ($null -eq $script:Pending) {
        try { $script:Pending = $http.GetStringAsync("$BaseUrl/api/state") } catch { $script:Pending = $null }
        return
    }
    if (-not $script:Pending.IsCompleted) { return }

    $task = $script:Pending
    $script:Pending = $null
    if ($task.IsFaulted -or $task.IsCanceled) {
        $viewbox.Opacity = 0.4              # 서버가 끊기면 흐리게
        $capBorder.Visibility = 'Collapsed' # 빈 알약이 남지 않게
        $badgeBorder.Visibility = 'Collapsed'
        return
    }
    $viewbox.Opacity = 1.0
    try { Update-FromSnapshot ($task.Result | ConvertFrom-Json) } catch { }
})

# ---------------------------------------------------------------- 클릭 통과
# 캐릭터 몸통 위에서만 마우스를 받고 나머지는 아래 창으로 통과시킨다.
# (맥 판과 같은 방식: 커서 위치를 보고 WS_EX_TRANSPARENT 를 켰다 껐다 한다)

$script:Handle = [IntPtr]::Zero
$script:TrayHandle = [IntPtr]::Zero
$script:Dragging = $false
$script:IsThrough = $false

function Set-ClickThrough([bool]$on) {
    if ($script:Handle -eq [IntPtr]::Zero) { return }
    if ($script:IsThrough -eq $on) { return }
    $ex = [MascotNative]::GetWindowLong($script:Handle, [MascotNative]::GWL_EXSTYLE)
    if ($on) { $ex = $ex -bor [MascotNative]::WS_EX_TRANSPARENT }
    else     { $ex = $ex -band (-bnot [MascotNative]::WS_EX_TRANSPARENT) }
    [MascotNative]::SetWindowLong($script:Handle, [MascotNative]::GWL_EXSTYLE, $ex) | Out-Null
    $script:IsThrough = $on
}

$hitTimer = New-Object System.Windows.Threading.DispatcherTimer
$hitTimer.Interval = [TimeSpan]::FromMilliseconds(120)
$hitTimer.Add_Tick({
    if ($script:Dragging) { return }   # 드래그 중엔 건드리지 않는다
    if ([bool]$Settings.clickThrough) { Set-ClickThrough $true; return }
    try {
        $p = [System.Windows.Forms.Cursor]::Position
        $local = $win.PointFromScreen((New-Object System.Windows.Point $p.X, $p.Y))
        $w = $win.Width; $h = $win.Height

        # 캐릭터가 실제로 그려지는 정사각 영역
        $charTop = $h * 0.02
        $charH   = $h * 0.82
        $side    = [Math]::Min($w, $charH)
        $left    = ($w - $side) / 2
        $top     = $charTop + ($charH - $side) / 2

        # 그 안에서 몸통+다리가 차지하는 비율 (20x20 그리드의 3~16열, 8~17행)
        $bx0 = $left + $side * 0.15
        $bx1 = $left + $side * 0.85
        $by0 = $top  + $side * 0.40
        $by1 = $top  + $side * 0.90

        $onBody = ($local.X -ge $bx0 -and $local.X -le $bx1 -and $local.Y -ge $by0 -and $local.Y -le $by1)
        # 캡션 알약 위에서도 받는다 (우클릭 메뉴를 열 수 있게)
        $onCap  = ($local.Y -ge $h * 0.85 -and $local.X -ge $w * 0.1 -and $local.X -le $w * 0.9)
        Set-ClickThrough (-not ($onBody -or $onCap))
    } catch { }
})

# ---------------------------------------------------------------- 트레이 아이콘

$notify = New-Object System.Windows.Forms.NotifyIcon
$notify.Text = 'Claude 마스코트'
$notify.Visible = $true

$StateIconColor = @{
    'idle' = '#8E6350'; 'stale' = '#6D6862'; 'thinking' = '#C87E5F'
    'working' = '#C87E5F'; 'waiting' = '#F2C14E'; 'done' = '#63C98D'
}

function Update-Tray {
    try {
        $hex = $StateIconColor['idle']
        if ($StateIconColor.ContainsKey($script:State)) { $hex = $StateIconColor[$script:State] }
        $col = [System.Drawing.ColorTranslator]::FromHtml($hex)

        # 상태 색으로 작은 도트 캐릭터 아이콘을 그린다
        $bmp = New-Object System.Drawing.Bitmap 16, 16
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.Clear([System.Drawing.Color]::Transparent)
        $br = New-Object System.Drawing.SolidBrush $col
        $g.FillRectangle($br, 2, 4, 12, 7)      # 몸통
        $g.FillRectangle($br, 3, 11, 2, 3)      # 다리
        $g.FillRectangle($br, 7, 11, 2, 3)
        $g.FillRectangle($br, 11, 11, 2, 3)
        $dark = New-Object System.Drawing.SolidBrush ([System.Drawing.ColorTranslator]::FromHtml('#2B1E17'))
        $g.FillRectangle($dark, 5, 6, 2, 2)     # 눈
        $g.FillRectangle($dark, 9, 6, 2, 2)
        $g.Dispose(); $br.Dispose(); $dark.Dispose()

        $handle = $bmp.GetHicon()
        $oldIcon = $notify.Icon
        $oldHandle = $script:TrayHandle
        $notify.Icon = [System.Drawing.Icon]::FromHandle($handle)
        $script:TrayHandle = $handle
        if ($oldIcon) { $oldIcon.Dispose() }
        # Icon.FromHandle 은 HICON 을 소유하지 않아서 Dispose 로는 안 지워진다
        if ($oldHandle -and $oldHandle -ne [IntPtr]::Zero) {
            try { [MascotNative]::DestroyIcon($oldHandle) | Out-Null } catch { }
        }
        $bmp.Dispose()

        $label = ''
        if ($SP.states.PSObject.Properties.Name -contains $script:State) { $label = $SP.states.($script:State).label }
        $t = "Claude 마스코트 — $label"
        if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }   # NotifyIcon.Text 는 63자 제한
        $notify.Text = $t
    } catch { }
}

# ---------------------------------------------------------------- 메뉴

function Open-Dashboard { Start-Process $BaseUrl }

function Quit-Pet {
    $animTimer.Stop(); $pollTimer.Stop(); $hitTimer.Stop()
    Save-Settings
    $notify.Visible = $false
    $notify.Dispose()
    $win.Close()
}

function Build-Menu {
    $m = New-Object System.Windows.Forms.ContextMenuStrip

    $head = $m.Items.Add('Claude 마스코트')
    $head.Enabled = $false
    $m.Items.Add('-') | Out-Null

    $dash = $m.Items.Add('대시보드 열기')
    $dash.Add_Click({ Open-Dashboard })

    $m.Items.Add('-') | Out-Null

    $ct = $m.Items.Add('클릭 통과 고정')
    $ct.Checked = [bool]$Settings.clickThrough
    $ct.Add_Click({
        $Settings.clickThrough = -not [bool]$Settings.clickThrough
        Save-Settings
    })

    $top = $m.Items.Add('항상 맨 위')
    $top.Checked = [bool]$Settings.onTop
    $top.Add_Click({
        $Settings.onTop = -not [bool]$Settings.onTop
        $win.Topmost = [bool]$Settings.onTop
        Save-Settings
    })

    $sizeItem = New-Object System.Windows.Forms.ToolStripMenuItem '크기'
    foreach ($key in $SizeOrder) {
        $k = $key
        $sub = New-Object System.Windows.Forms.ToolStripMenuItem $Sizes[$k].title
        $sub.Checked = ($Settings.size -eq $k)
        $sub.Tag = $k
        # Tag 와 캡처변수 두 경로를 모두 둔다. PowerShell 판(5.1 vs 7)에 따라
        # 클로저 안에서의 변수/명령 해석이 다를 수 있어 어느 쪽이든 동작하게 한다.
        $sub.Add_Click({
            $key = ''
            try { $key = [string]$this.Tag } catch { }
            if (-not $key) { $key = $k }
            Set-PetSize $key
            Save-Settings
        }.GetNewClosure())
        $sizeItem.DropDownItems.Add($sub) | Out-Null
    }
    $m.Items.Add($sizeItem) | Out-Null

    $reset = $m.Items.Add('위치 초기화')
    $reset.Add_Click({
        Move-ToDefaultCorner
        $Settings.left = $win.Left; $Settings.top = $win.Top
        Save-Settings
    })

    $m.Items.Add('-') | Out-Null
    $quit = $m.Items.Add('종료')
    $quit.Add_Click({ Quit-Pet })

    return $m
}

$notify.Add_MouseUp({
    if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Right -or $_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $menu = Build-Menu
        $menu.Show([System.Windows.Forms.Cursor]::Position)
        try { [MascotNative]::SetForegroundWindow($menu.Handle) | Out-Null } catch { }
    }
})

# ---------------------------------------------------------------- 마우스 조작

$win.Add_MouseLeftButtonDown({
    if ($_.ClickCount -eq 2) { Open-Dashboard; return }
    $script:Dragging = $true
    try { $win.DragMove() } catch { }
    $script:Dragging = $false
    $Settings.left = $win.Left
    $Settings.top  = $win.Top
    Save-Settings
})

$win.Add_MouseRightButtonUp({
    $menu = Build-Menu
    $menu.Show([System.Windows.Forms.Cursor]::Position)
})

# ---------------------------------------------------------------- 서버 확인 / 실행

function Ensure-Server {
    try {
        $probe = $http.GetStringAsync("$BaseUrl/healthz")
        if ($probe.Wait(600) -and -not $probe.IsFaulted) { return }
    } catch { }

    # 안 떠 있으면 직접 띄운다
    $serverJs = Join-Path $Root 'server.js'
    if (-not (Test-Path $serverJs)) { return }
    $node = (Get-Command node -ErrorAction SilentlyContinue)
    if (-not $node) { return }
    try {
        Start-Process -FilePath $node.Source -ArgumentList "`"$serverJs`"" `
            -WorkingDirectory $Root -WindowStyle Hidden | Out-Null
        # 여기서 기다리지 않는다. 서버가 뜨는 대로 폴링 타이머가 알아서 잡는다.
    } catch { }
}

# ---------------------------------------------------------------- 시작

$win.Add_SourceInitialized({
    $script:Handle = (New-Object System.Windows.Interop.WindowInteropHelper $win).Handle
})

$win.Add_Loaded({
    # 주 모니터 왼쪽/위에 있는 모니터는 좌표가 음수라 '0 이상' 으로 판정하면 안 된다
    if ($null -ne $Settings.left -and $null -ne $Settings.top) {
        $win.Left = [double]$Settings.left
        $win.Top  = [double]$Settings.top
    } else {
        Move-ToDefaultCorner
    }
    Ensure-Server
    Apply-State 'idle'
    $animTimer.Start()
    $pollTimer.Start()
    $hitTimer.Start()
})

$win.Add_Closed({
    try { $notify.Visible = $false; $notify.Dispose() } catch { }
})

# WPF 디스패처 루프 (창을 띄우고, 닫히면 끝난다)
$app = New-Object System.Windows.Application
$app.ShutdownMode = 'OnLastWindowClose'
$app.Run($win) | Out-Null
