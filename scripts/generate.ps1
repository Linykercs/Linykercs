# Renders the neofetch-style profile card (dark.svg / light.svg) from
# profile.json, the ASCII portrait in assets/ and live GitHub stats.
# Runs on Windows PowerShell 5.1 and PowerShell 7 (used by the workflow).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$utf8 = New-Object System.Text.UTF8Encoding $false

$profile_ = [System.IO.File]::ReadAllText((Join-Path $root 'profile.json'), $utf8) | ConvertFrom-Json

# --- Layout -----------------------------------------------------------------
$width = 1000
$lineChars = 58          # characters per info line
$infoX = 405
$infoFont = 16
$infoLine = 20
$infoWidth = 575         # every info line is stretched to exactly this width
$artX = 20
$artFont = 10
$artLine = 10
$artCharWidth = 6.02

$themes = @{
    dark  = @{ bg = '#161b22'; text = '#c9d1d9'; key = '#ffa657'; value = '#a5d6ff'; dim = '#616e7f' }
    light = @{ bg = '#f6f8fa'; text = '#24292f'; key = '#953800'; value = '#0a3069'; dim = '#afb8c1' }
}

# --- Data -------------------------------------------------------------------
function Get-Uptime([datetime] $from, [datetime] $to) {
    $years = $to.Year - $from.Year
    $months = $to.Month - $from.Month
    $days = $to.Day - $from.Day
    if ($days -lt 0) {
        $months--
        $days += [datetime]::DaysInMonth($to.AddMonths(-1).Year, $to.AddMonths(-1).Month)
    }
    if ($months -lt 0) { $years--; $months += 12 }
    "$years years, $months months, $days days"
}

function Invoke-GitHub([string] $path) {
    $headers = @{ 'User-Agent' = 'profile-card'; 'Accept' = 'application/vnd.github+json' }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = "Bearer $($env:GITHUB_TOKEN)" }
    Invoke-RestMethod -Uri "https://api.github.com/$path" -Headers $headers
}

$login = $profile_.user
$account = Invoke-GitHub "users/$login"
$repos = @(Invoke-GitHub "users/$login/repos?per_page=100&type=owner" | ForEach-Object { $_ })
$stars = ($repos | Measure-Object -Property stargazers_count -Sum).Sum
$commits = (Invoke-GitHub "search/commits?q=author:$login&per_page=1").total_count
$uptime = Get-Uptime ([datetime]$profile_.birthday) ([datetime]::UtcNow.Date)

# --- Line builders ----------------------------------------------------------
function Escape([string] $s) { $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;') }

function New-Pair([string] $key, [string] $value, [int] $chars) {
    # ". Key: ........ Value" padded with dots to exactly $chars characters
    $dots = $chars - 2 - $key.Length - 1 - 2 - $value.Length
    if ($dots -lt 1) { throw "Line too long: $key" }
    $k = Escape $key
    $k = $k.Replace('.', '</tspan>.<tspan class="key">')
    '<tspan class="dim">. </tspan><tspan class="key">{0}</tspan>:<tspan class="dim"> {1} </tspan><tspan class="value">{2}</tspan>' -f `
        $k, ('.' * $dots), (Escape $value)
}

function New-Ruler([string] $label, [bool] $isTitle) {
    $rule = ([string][char]0x2500) * ($lineChars - $label.Length - $(if ($isTitle) { 1 } else { 3 }))
    if ($isTitle) { '<tspan class="key">{0}</tspan> {1}' -f (Escape $label), $rule }
    else { '- {0} {1}' -f (Escape $label), $rule }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add((New-Ruler $profile_.title $true))
foreach ($section in $profile_.sections) {
    foreach ($pair in $section) {
        $lines.Add((New-Pair $pair[0] ($pair[1].Replace('{uptime}', $uptime)) $lineChars))
    }
    $lines.Add('<tspan class="dim">.</tspan>')
}
$lines.RemoveAt($lines.Count - 1)
$lines.Add('')
$lines.Add((New-Ruler 'Contact' $false))
foreach ($pair in $profile_.contact) { $lines.Add((New-Pair $pair[0] $pair[1] $lineChars)) }
$lines.Add('')
$lines.Add((New-Ruler 'GitHub Stats' $false))
$half = [int](($lineChars - 3) / 2)
$sep = '<tspan class="dim"> | </tspan>'
$lines.Add((New-Pair 'Repos' "$($account.public_repos)" $half) + $sep + (New-Pair 'Stars' "$stars" ($lineChars - 3 - $half)).Substring('<tspan class="dim">. </tspan>'.Length).Insert(0, '<tspan class="dim">  </tspan>'))
$lines.Add((New-Pair 'Commits' "$commits" $half) + $sep + (New-Pair 'Followers' "$($account.followers)" ($lineChars - 3 - $half)).Substring('<tspan class="dim">. </tspan>'.Length).Insert(0, '<tspan class="dim">  </tspan>'))

# --- Render -----------------------------------------------------------------
foreach ($name in $themes.Keys) {
    $t = $themes[$name]
    $art = [System.IO.File]::ReadAllText((Join-Path $root "assets/ascii-$name.txt"), $utf8) -split "`n"
    $infoHeight = $lines.Count * $infoLine
    $artHeight = $art.Count * $artLine
    $height = [Math]::Max($infoHeight, $artHeight) + 50
    $infoY = [int](($height - $infoHeight) / 2) + $infoFont
    $artY = [int](($height - $artHeight) / 2) + $artFont

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" font-family=`"Consolas, 'SFMono-Regular', 'DejaVu Sans Mono', Menlo, monospace`">")
    [void]$sb.AppendLine("<style>text{white-space:pre;fill:$($t.text)}.key{fill:$($t.key)}.value{fill:$($t.value)}.dim{fill:$($t.dim)}</style>")
    [void]$sb.AppendLine("<rect width=`"$width`" height=`"$height`" rx=`"15`" fill=`"$($t.bg)`"/>")
    [void]$sb.AppendLine("<g font-size=`"$artFont`" xml:space=`"preserve`">")
    for ($i = 0; $i -lt $art.Count; $i++) {
        $row = $art[$i].TrimEnd()
        if (-not $row) { continue }
        $len = [Math]::Round($row.Length * $artCharWidth, 1).ToString([cultureinfo]::InvariantCulture)
        [void]$sb.AppendLine("<text x=`"$artX`" y=`"$($artY + $i * $artLine)`" textLength=`"$len`" lengthAdjust=`"spacingAndGlyphs`">$(Escape $row)</text>")
    }
    [void]$sb.AppendLine('</g>')
    [void]$sb.AppendLine("<g font-size=`"$infoFont`" xml:space=`"preserve`">")
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if (-not $lines[$i]) { continue }
        $y = $infoY + $i * $infoLine
        $fit = if ($lines[$i] -eq '<tspan class="dim">.</tspan>') { '' } else { " textLength=`"$infoWidth`" lengthAdjust=`"spacingAndGlyphs`"" }
        [void]$sb.AppendLine("<text x=`"$infoX`" y=`"$y`"$fit>$($lines[$i])</text>")
    }
    [void]$sb.AppendLine('</g>')
    [void]$sb.AppendLine('</svg>')
    [System.IO.File]::WriteAllText((Join-Path $root "$name.svg"), $sb.ToString().Replace("`r`n", "`n"), $utf8)
}
Write-Host "Rendered dark.svg and light.svg (repos=$($account.public_repos) stars=$stars commits=$commits followers=$($account.followers))"
