<#
  ndGUI for Spiritech - installer / updater / uninstaller (plain PowerShell, nothing to download).

  Easiest: double-click install.bat.  Or from PowerShell in this folder:
    .\install.ps1                      menu
    .\install.ps1 -Install             install / update from this folder, no questions
    .\install.ps1 -Update              download the newest release from GitHub and install it
    .\install.ps1 -Install -StockScreens   keep the game's own screens (Options, login...) stock
    .\install.ps1 -Install -KeepProviders  leave current HUD/window UI package choices alone
    .\install.ps1 -Update -KeepProviders   update from GitHub without rewriting providers
    .\install.ps1 -Uninstall           back to the stock UI
    .\install.ps1 -Install -Client "D:\Games\PRK-AO-Native\client"
    .\install.ps1 -Grid 20             snap-to-grid size in pixels (0 = off); kept across updates

  Everything it changes in the game keeps a *.stock backup first; -Uninstall puts them back.
  Works with Windows PowerShell 5.1 (built into Windows 10/11) and PowerShell 7.
#>
param(
    [string]$Client,
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$StockScreens,
    [switch]$KeepProviders,
    [switch]$Update,
    [int]$Grid = -1
)

$ErrorActionPreference = 'Stop'
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Game = Join-Path $Here 'game'
$Latin1 = [System.Text.Encoding]::GetEncoding(28591)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Interactive = -not ($Install -or $Uninstall -or $Update -or $Grid -ge 0)
$Project = 'hafthorr/ndgui-spiritech'   # public GitHub repository the updater reads releases from

$Info = @{}
$InfoFile = Join-Path $Game 'build-info.txt'
if (Test-Path $InfoFile) {
    foreach ($line in [System.IO.File]::ReadAllLines($InfoFile)) {
        $i = $line.IndexOf('=')
        if ($i -gt 0) { $Info[$line.Substring(0, $i)] = $line.Substring($i + 1) }
    }
}
$Version = $Info['version']
if (-not $Version) { $Version = '?' }

function Say([string]$Text = '') { Write-Host $Text }
function Warn([string]$Text) { Write-Host $Text -ForegroundColor Yellow }

# ---- finding the game -----------------------------------------------------------------
function Test-ClientDir([string]$Path) {
    return ($Path -and (Test-Path -LiteralPath (Join-Path $Path 'UI\Packages\Core')))
}

function Resolve-ClientDir([string]$Path) {
    if (-not $Path) { return $null }
    $Path = $Path.Trim().Trim('"')
    if (-not $Path) { return $null }
    if (Test-Path -LiteralPath $Path -PathType Leaf) { $Path = Split-Path -Parent $Path }
    foreach ($candidate in @($Path, (Join-Path $Path 'client'))) {
        if (Test-ClientDir $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
    }
    $settings = Join-Path $Path 'LauncherSettings.json'
    if (Test-Path -LiteralPath $settings) {
        try {
            $clientPath = (Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json).ClientPath
            if (Test-ClientDir $clientPath) { return $clientPath }
        } catch { }
    }
    return $null
}

function Find-ClientDir {
    $seen = New-Object System.Collections.ArrayList
    $folder = $Here
    for ($i = 0; $i -lt 4 -and $folder; $i++) {
        [void]$seen.Add($folder); [void]$seen.Add((Join-Path $folder 'PRK-AO-Native'))
        $folder = Split-Path -Parent $folder
    }
    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if ($drive.DriveType -ne 'Fixed' -or -not $drive.IsReady) { continue }
        foreach ($sub in @('Games\PRK-AO-Native', 'PRK-AO-Native', 'Program Files\PRK-AO-Native',
                           'Program Files (x86)\PRK-AO-Native', 'Games\Project Rubi-Ka', 'Project Rubi-Ka')) {
            [void]$seen.Add((Join-Path $drive.RootDirectory.FullName $sub))
        }
    }
    foreach ($base in @($env:LOCALAPPDATA, $env:USERPROFILE)) {
        if (-not $base) { continue }
        foreach ($sub in @('PRK-AO-Native', 'Games\PRK-AO-Native', 'Desktop\PRK-AO-Native',
                           'Downloads\PRK-AO-Native', 'Programs\PRK-AO-Native')) {
            [void]$seen.Add((Join-Path $base $sub))
        }
    }
    foreach ($path in $seen) {
        $found = Resolve-ClientDir $path
        if ($found) { return $found }
    }
    return $null
}

function Select-ClientDir {
    Say 'I could not find the game by myself.'
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object System.Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Pick the Spiritech game folder (the one with PRK.Client.exe)'
        Say 'Pick the game folder in the window that just opened...'
        if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
            $found = Resolve-ClientDir $dialog.SelectedPath
            if ($found) { return $found }
        }
    } catch { }
    while ($true) {
        $path = Read-Host 'Paste the game folder (the one with PRK.Client.exe), or press Enter to cancel'
        if (-not $path.Trim()) { throw 'Cancelled.' }
        $found = Resolve-ClientDir $path
        if ($found) { return $found }
        Warn '  That folder has no PRK.Client.exe / UI folder. Try again.'
    }
}

# ---- helpers ----------------------------------------------------------------------------
function Wait-GameClosed {
    if ($env:NDGUI_ASSUME_CLOSED) { return }   # tests: a fake client while the real game runs
    while (Get-Process -Name 'PRK.Client' -ErrorAction SilentlyContinue) {
        if (-not $Interactive) { throw 'The game (PRK.Client.exe) is running. Quit it first.' }
        Warn 'The game (PRK.Client.exe) is running.'
        [void](Read-Host 'Quit the game, then press Enter')
    }
}

function Test-Ours([string]$Path) {
    # every file ndGUI changes carries an NDGUI graphic id; the game's own files never do
    return $Latin1.GetString([System.IO.File]::ReadAllBytes($Path)).Contains('NDGUI')
}

function Save-Stock([string]$Path, [string]$Probe = $Path) {
    # Keep the untouched game file; every later install starts from it. When the live file is no longer
    # ours ($Probe has no NDGUI mark), a game patch replaced it: that copy is the new stock.
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-Path -LiteralPath "$Path.stock") -or -not (Test-Ours $Probe)) {
        Copy-Item -LiteralPath $Path -Destination "$Path.stock" -Force
    }
}

function Get-BuiltFrom {
    # the original game screens this release was built from: relative path -> SHA-256
    $map = @{}
    $file = Join-Path $Game 'built-from.txt'
    if (Test-Path -LiteralPath $file) {
        foreach ($line in [System.IO.File]::ReadAllLines($file)) {
            $parts = $line.Trim() -split '\s+'
            if ($parts.Count -eq 2) { $map[$parts[0]] = $parts[1] }
        }
    }
    return $map
}

function Test-SameGame([hashtable]$BuiltFrom, [string]$Key, [string]$Path) {
    # true when the game's original of this screen is the one the release was built from
    if (-not $BuiltFrom.ContainsKey($Key)) { return $false }
    return (Get-FileHash -LiteralPath "$Path.stock" -Algorithm SHA256).Hash -eq $BuiltFrom[$Key]
}

function Get-Stock([string]$Path) {
    if (Test-Path -LiteralPath "$Path.stock") { return "$Path.stock" }
    return $Path
}

function Test-OurPackage([string]$Folder) {
    $manifest = Join-Path $Folder 'package.xml'
    if (-not (Test-Path -LiteralPath $manifest)) { return $false }
    return ([System.IO.File]::ReadAllText($manifest) -match '<Package id="notum\.ndgui')
}

function Get-Providers([string]$AddonsDir) {
    # role -> package id, from every installed notum.ndgui* manifest
    $map = @{}
    foreach ($dir in Get-ChildItem -LiteralPath $AddonsDir -Directory -Filter 'ndgui*' -ErrorAction SilentlyContinue) {
        $manifest = Join-Path $dir.FullName 'package.xml'
        if (-not (Test-Path -LiteralPath $manifest)) { continue }
        $text = [System.IO.File]::ReadAllText($manifest)
        $id = [regex]::Match($text, '<Package id="([^"]+)"')
        if (-not $id.Success -or -not $id.Groups[1].Value.StartsWith('notum.ndgui')) { continue }
        foreach ($role in [regex]::Matches($text, '<Provides role="([^"]+)"')) {
            $map[$role.Groups[1].Value] = $id.Groups[1].Value
        }
    }
    return $map
}

function Get-PrefsPath {
    if ($env:NDGUI_PREFS) { return $env:NDGUI_PREFS }   # testing against a copy
    return (Join-Path $env:LOCALAPPDATA 'ProjectRubiKa\prefs\Client.xml')
}

function Set-Providers([hashtable]$Map, [bool]$Reset) {
    $prefs = Get-PrefsPath
    if (-not (Test-Path -LiteralPath $prefs)) {
        Warn "  No game settings yet ($prefs)."
        Warn '  Start the game once, quit, and run this again - or pick them in game:'
        Warn '  Options > Interface & HUD > UI packages.'
        return
    }
    Copy-Item -LiteralPath $prefs -Destination ($prefs + '.ndgui-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    $xml = [System.IO.File]::ReadAllText($prefs)
    $lines = New-Object System.Collections.ArrayList
    foreach ($role in ($Map.Keys | Sort-Object)) {
        $key = 'UiPackageProvider_' + $role.Substring(4).Replace('-', '_')
        $xml = [regex]::Replace($xml, '\r?\n?[ \t]*<Value name="' + [regex]::Escape($key) + '" value="[^"]*" />', '')
        if (-not $Reset) { [void]$lines.Add('    <Value name="' + $key + '" value="&quot;' + $Map[$role] + '&quot;" />') }
    }
    if (-not $Reset) {
        $at = $xml.IndexOf('<Root>')
        if ($at -lt 0) { Warn '  Unexpected settings file (no <Root>); pick the providers in game.'; return }
        $xml = $xml.Insert($at + 6, "`r`n" + ($lines -join "`r`n"))
    }
    [System.IO.File]::WriteAllText($prefs, $xml, $Utf8)
    if ($Reset) { Say "  reset $($Map.Count) roles to the built-in UI" } else { Say "  selected ndGUI for $($Map.Count) roles" }
}

function Install-Skin([string]$ClientDir) {
    $dir = Join-Path $ClientDir 'cd_image\gui\Default'
    $overlay = Join-Path $Game 'skin'
    $uvgi = Join-Path $dir 'Graphics.uvgi'; $uvga = Join-Path $dir 'Graphics.uvga'; $colors = Join-Path $dir 'GUIColors.xml'
    foreach ($f in @($uvgi, $uvga, $colors)) {
        if (-not (Test-Path -LiteralPath $f)) { throw "Game skin file missing: $f" }
    }
    foreach ($f in @($uvgi, $uvga, $colors)) {
        Save-Stock $f $uvgi   # only Graphics.uvgi carries the NDGUI mark for all three
    }
    # Graphics.uvgi = count line, then "NAME offset length"; Graphics.uvga = the PNGs back to back.
    $index = $Latin1.GetString([System.IO.File]::ReadAllBytes("$uvgi.stock")) -split "`r?`n"
    $blob = [System.IO.File]::ReadAllBytes("$uvga.stock")
    $out = New-Object System.IO.MemoryStream
    $entries = New-Object System.Collections.ArrayList
    $seen = @{}
    $replaced = 0
    foreach ($line in ($index | Select-Object -Skip 1)) {
        $parts = $line.Trim() -split '\s+'
        if ($parts.Count -ne 3) { continue }
        $name = $parts[0]
        $file = Join-Path $overlay ($name + '.png')
        if (Test-Path -LiteralPath $file) {
            $data = [System.IO.File]::ReadAllBytes($file); $replaced++
        } else {
            $data = New-Object byte[] ([int]$parts[2])
            [System.Array]::Copy($blob, [long]$parts[1], $data, 0, [int]$parts[2])
        }
        [void]$entries.Add("$name $($out.Length) $($data.Length)")
        $out.Write($data, 0, $data.Length)
        $seen[$name] = $true
    }
    $added = 0
    foreach ($name in [System.IO.File]::ReadAllLines((Join-Path $overlay 'new.txt'))) {
        if (-not $name -or $seen.ContainsKey($name)) { continue }
        $data = [System.IO.File]::ReadAllBytes((Join-Path $overlay ($name + '.png')))
        [void]$entries.Add("$name $($out.Length) $($data.Length)")
        $out.Write($data, 0, $data.Length)
        $added++
    }
    [System.IO.File]::WriteAllBytes($uvga, $out.ToArray())
    $text = "$($entries.Count)`r`n" + ($entries -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllBytes($uvgi, $Latin1.GetBytes($text))
    $xml = $Latin1.GetString([System.IO.File]::ReadAllBytes("$colors.stock"))
    foreach ($line in [System.IO.File]::ReadAllLines((Join-Path $overlay 'colors.txt'))) {
        $i = $line.IndexOf('=')
        if ($i -le 0) { continue }
        $key = $line.Substring(0, $i); $value = $line.Substring($i + 1)
        $xml = [regex]::Replace($xml, '(<Color name="' + [regex]::Escape($key) + '"\s+color=")[^"]*"', '${1}' + $value + '"')
    }
    [System.IO.File]::WriteAllBytes($colors, $Latin1.GetBytes($xml))
    Say "  skin: $($entries.Count) graphics ($added new, $($replaced) restyled)"
}

function Install-Screens([string]$ClientDir) {
    $count = 0
    $stale = 0
    $builtFrom = Get-BuiltFrom
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Game 'Layouts') -Filter '*.xml') {
        $target = Join-Path $ClientDir ('UI\Layouts\' + $file.Name)
        if (-not (Test-Path -LiteralPath $target)) { Warn "  skipped $($file.Name) (not in this game version)"; continue }
        Save-Stock $target
        if (-not (Test-SameGame $builtFrom "Layouts/$($file.Name)" $target)) {
            # the game changed this screen since the release was built: an older copy can crash the client
            Copy-Item -LiteralPath "$target.stock" -Destination $target -Force
            $stale++
            continue
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $count++
    }
    $window = Join-Path $ClientDir 'UI\Packages\Core\window.xml'
    Save-Stock $window
    if (Test-SameGame $builtFrom 'Packages/Core/window.xml' $window) {
        Copy-Item -LiteralPath (Join-Path $Game 'Packages\Core\window.xml') -Destination $window -Force
    } else {
        Copy-Item -LiteralPath "$window.stock" -Destination $window -Force
        $stale++
    }
    if ($stale) { Warn "  kept $stale game screen(s) stock: this ndGUI was built for another game version. Update ndGUI (menu 2)." }
    Say "  square buttons on $count game screens + window pins"
}

function Restore-Screens([string]$ClientDir) {
    $restored = 0
    foreach ($stock in Get-ChildItem -LiteralPath (Join-Path $ClientDir 'UI\Layouts') -Filter '*.xml.stock' -ErrorAction SilentlyContinue) {
        $live = $stock.FullName.Substring(0, $stock.FullName.Length - 6)
        # only put the backup back over our own file: if a game patch replaced it, the live file is newer
        if ((Test-Path -LiteralPath $live) -and -not (Test-Ours $live)) { continue }
        Copy-Item -LiteralPath $stock.FullName -Destination $live -Force
        $restored++
    }
    $window = Join-Path $ClientDir 'UI\Packages\Core\window.xml'
    if ((Test-Path -LiteralPath "$window.stock") -and (Test-Ours $window)) { Copy-Item -LiteralPath "$window.stock" -Destination $window -Force; $restored++ }
    Say "  restored $restored stock game screens"
}

function Restore-Skin([string]$ClientDir) {
    $dir = Join-Path $ClientDir 'cd_image\gui\Default'
    $restored = 0
    $uvgi = Join-Path $dir 'Graphics.uvgi'
    if ((Test-Path -LiteralPath $uvgi) -and -not (Test-Ours $uvgi)) { Say '  skin is already the game''s own'; return }
    foreach ($name in @('Graphics.uvgi', 'Graphics.uvga', 'GUIColors.xml')) {
        $path = Join-Path $dir $name
        if (Test-Path -LiteralPath "$path.stock") { Copy-Item -LiteralPath "$path.stock" -Destination $path -Force; $restored++ }
    }
    if ($restored) { Say '  stock skin restored' } else { Say '  skin was never changed' }
}

function Remove-Packages([string]$AddonsDir) {
    $removed = 0
    foreach ($dir in Get-ChildItem -LiteralPath $AddonsDir -Directory -Filter 'ndgui*' -ErrorAction SilentlyContinue) {
        if (Test-OurPackage $dir.FullName) { Remove-Item -LiteralPath $dir.FullName -Recurse -Force; $removed++ }
    }
    return $removed
}

function Get-ClientVersion([string]$ClientDir) {
    $parts = @()
    foreach ($name in @('spiritech.version.txt', 'version.txt')) {
        $path = Join-Path $ClientDir $name
        if (Test-Path -LiteralPath $path) { $parts += ([System.IO.File]::ReadAllText($path).Trim()) }
    }
    if ($parts.Count) { return ($parts -join ' / ') }
    return 'unknown'
}

# ---- snap-to-grid size (ndgui-lib\lua\grid.lua) -------------------------------------------
function Get-GridFile([string]$ClientDir) { return Join-Path $ClientDir 'UI\Addons\ndgui-lib\lua\grid.lua' }

function Get-Grid([string]$ClientDir) {
    $file = Get-GridFile $ClientDir
    if (-not (Test-Path -LiteralPath $file)) { return -1 }
    $m = [regex]::Match([System.IO.File]::ReadAllText($file), '(?m)^local SIZE = (\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return -1
}

function Set-Grid([string]$ClientDir, [int]$Size) {
    if ($Size -lt 0 -or $Size -gt 200) { throw 'The grid size must be a whole number from 0 to 200.' }
    $file = Get-GridFile $ClientDir
    if ((Get-Grid $ClientDir) -lt 0) { throw 'ndGUI is not installed in this game folder yet; install it first.' }
    $code = [regex]::Replace([System.IO.File]::ReadAllText($file), '(?m)^local SIZE = \d+', "local SIZE = $Size", 1)
    [System.IO.File]::WriteAllText($file, $code, $Utf8)
    if ($Size -ge 2) { Say "  snap grid: $Size px" } else { Say '  snap grid: off' }
}

function Get-GridLabel([int]$Size) {
    if ($Size -lt 0) { return 'not installed' }
    if ($Size -lt 2) { return 'off' }
    return "$Size px"
}

function Invoke-GridMenu([string]$ClientDir) {
    $current = Get-Grid $ClientDir
    if ($current -lt 0) { throw 'ndGUI is not installed in this game folder yet; install it first.' }
    Say "Windows and HUD pieces snap to this grid while you move or resize them, when the game's"
    Say 'snapping is on (Options > Interface & HUD > Windows and HUD > magnetism above 0).'
    Say "Now: $(Get-GridLabel $current)"
    $answer = (Read-Host "`nGrid size in pixels, e.g. 5, 10, 20, 25, 50 (0 = off) [keep]").Trim()
    if (-not $answer) { return }
    $size = 0
    if (-not [int]::TryParse($answer, [ref]$size)) { throw 'Give a whole number from 0 to 200.' }
    Set-Grid $ClientDir $size
    Say 'Restart the game to use it.'
}

# ---- actions ------------------------------------------------------------------------------
function Invoke-Install([string]$ClientDir, [bool]$KeepScreens, [bool]$KeepProviders = $false) {
    if (-not (Test-Path -LiteralPath (Join-Path $Game 'Addons'))) {
        throw "No 'game' folder next to install.ps1. Unpack the whole release zip and run install.bat from it."
    }
    Wait-GameClosed
    $built = $Info['client']; $have = Get-ClientVersion $ClientDir
    if ($built -and $built -ne $have) {
        Warn "This ndGUI build was made for game version $built; you have $have."
        Warn 'It usually works; anything that does not falls back to the stock UI. A newer ndGUI release may exist.'
    }
    $addons = Join-Path $ClientDir 'UI\Addons'
    New-Item -ItemType Directory -Force -Path $addons | Out-Null
    Say "`n[1/4] ndGUI packages"
    $keptGrid = Get-Grid $ClientDir   # the copy replaces grid.lua; keep the player's grid size
    $old = Remove-Packages $addons
    foreach ($dir in Get-ChildItem -LiteralPath (Join-Path $Game 'Addons') -Directory) {
        Copy-Item -LiteralPath $dir.FullName -Destination (Join-Path $addons $dir.Name) -Recurse -Force
    }
    if ($Grid -ge 0) { Set-Grid $ClientDir $Grid }
    elseif ($keptGrid -ge 0 -and $keptGrid -ne (Get-Grid $ClientDir)) { Set-Grid $ClientDir $keptGrid }
    $count = (Get-ChildItem -LiteralPath (Join-Path $Game 'Addons') -Directory).Count
    # remember what is installed, so -Update can tell whether a newer release exists
    $marker = Join-Path $addons 'ndgui\installed-version.txt'
    if (Test-Path -LiteralPath (Join-Path $addons 'ndgui')) { [System.IO.File]::WriteAllText($marker, $Version, $Utf8) }
    if ($old) { Say "  updated $count packages" } else { Say "  installed $count packages" }
    Say "`n[2/4] Square DarkTech buttons on the game's own screens"
    if ($KeepScreens) { Restore-Screens $ClientDir; Say '  kept stock (as asked)' } else { Install-Screens $ClientDir }
    Say "`n[3/4] DarkTech skin"
    Install-Skin $ClientDir
    if ($KeepProviders) {
        Say "`n[4/4] Keeping current HUD/window providers (as asked)"
    } else {
        Say "`n[4/4] Switching the HUD and windows to ndGUI"
        Set-Providers (Get-Providers $addons) $false
    }
    Say ''
    Write-Host 'Done! Start the game.' -ForegroundColor Green
    Say 'If something still looks stock, log out to character select and back in once.'
    Say 'To undo everything, run install.bat again and pick Uninstall.'
    Write-Host "`nBugs, issues, ideas? Ask 'thedenis' on the Project Rubi-Ka Discord." -ForegroundColor Cyan
}

function Get-InstalledVersion([string]$ClientDir) {
    $marker = Join-Path $ClientDir 'UI\Addons\ndgui\installed-version.txt'
    if (Test-Path -LiteralPath $marker) { return ([System.IO.File]::ReadAllText($marker)).Trim() }
    if (Test-Path -LiteralPath (Join-Path $ClientDir 'UI\Addons\ndgui')) { return 'an older version' }
    return $null
}

function Test-Newer([string]$Candidate, [string]$Current) {
    try { return [version]$Candidate -gt [version]$Current } catch { return $true }
}

function Invoke-Update([string]$ClientDir) {
    # Read the newest release from GitHub, download its zip, run that version's installer.
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $installed = Get-InstalledVersion $ClientDir
    Say "`nInstalled: $(if ($installed) { $installed } else { 'nothing yet' })"
    Say 'Checking GitHub for the newest release...'
    $api = "https://api.github.com/repos/$Project/releases/latest"
    try {
        $release = Invoke-RestMethod -Uri $api -UseBasicParsing -Headers @{ 'User-Agent' = 'ndgui-installer' }
    } catch {
        throw "Could not reach GitHub ($($_.Exception.Message)). Check your internet connection, or download the zip by hand: https://github.com/$Project/releases"
    }
    $latest = ([string]$release.tag_name).TrimStart('v')
    $link = @($release.assets | Where-Object { $_.name -like '*.zip' })[0]
    if (-not $latest -or -not $link) { throw "The newest GitHub release has no download. Get it by hand: https://github.com/$Project/releases" }
    Say "Newest:    $latest"
    if ($installed -and $installed -match '^\d' -and -not (Test-Newer $latest $installed)) {
        Write-Host "`nYou already have the newest ndGUI ($installed)." -ForegroundColor Green
        if ($Interactive) {
            $again = (Read-Host 'Reinstall it anyway (e.g. after a game patch)? [y/N]').Trim()
            if ($again -notmatch '^[yY]') { return }
        } else { return }
    }
    Wait-GameClosed
    $work = Join-Path ([System.IO.Path]::GetTempPath()) "ndgui-spiritech-update-$latest"
    if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $work | Out-Null
    $zip = Join-Path $work 'ndgui-spiritech.zip'
    Say "Downloading ndGUI $latest..."
    $ProgressPreference = 'SilentlyContinue'   # the progress bar makes downloads in 5.1 very slow
    Invoke-WebRequest -Uri $link.browser_download_url -OutFile $zip -UseBasicParsing -Headers @{ 'User-Agent' = 'ndgui-installer' }
    Expand-Archive -LiteralPath $zip -DestinationPath $work -Force
    $next = @(Get-ChildItem -LiteralPath $work -Recurse -Filter 'install.ps1')[0]
    if (-not $next) { throw 'The downloaded zip has no install.ps1.' }
    Say "Installing ndGUI $latest...`n"
    $installArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $next.FullName, '-Install', '-Client', $ClientDir)
    if ($KeepProviders) { $installArgs += '-KeepProviders' }
    & powershell.exe @installArgs
    if ($LASTEXITCODE -ne 0) { throw "Installing $latest failed (see above)." }
    Say "`nThe $latest installer (for Uninstall later) is in: $(Split-Path -Parent $next.FullName)"
}

function Invoke-Uninstall([string]$ClientDir) {
    Wait-GameClosed
    $addons = Join-Path $ClientDir 'UI\Addons'
    Say 'Back to the stock UI:'
    Set-Providers (Get-Providers $addons) $true
    Restore-Skin $ClientDir
    Restore-Screens $ClientDir
    $removed = Remove-Packages $addons
    Say "  removed $removed ndGUI packages"
    Write-Host 'Done. The stock UI is back on the next start.' -ForegroundColor Green
}

try {
    if ($Interactive) { Say "ndGUI for Spiritech $Version`n" }
    if ($Client) {
        $dir = Resolve-ClientDir $Client
        if (-not $dir) { throw "'$Client' is not the Spiritech game folder (the one with PRK.Client.exe and UI\ inside)." }
    } else {
        $dir = Find-ClientDir
        if (-not $dir) {
            if (-not $Interactive) { throw 'Could not find the game. Run again with -Client "<folder with PRK.Client.exe>".' }
            $dir = Select-ClientDir
        }
    }
    Say "Game folder: $dir"
    if ($Install) { Invoke-Install $dir ([bool]$StockScreens) ([bool]$KeepProviders) }
    elseif ($Grid -ge 0) { Set-Grid $dir $Grid; Say 'Restart the game to use it.' }
    elseif ($Update) { Invoke-Update $dir }
    elseif ($Uninstall) { Invoke-Uninstall $dir }
    else {
        $installed = Get-InstalledVersion $dir
        if ($installed) { Say "Installed: ndGUI $installed" }
        Say ''
        Say "  1) Install / update to $Version (this folder)"
        Say '  2) Update to the newest version (downloads from GitHub)'
        Say "  3) Install $Version, but keep the game's own screens stock (Options, login...)"
        Say '  4) Uninstall (back to the stock UI)'
        Say "  5) Snap-to-grid size (now: $(Get-GridLabel (Get-Grid $dir)))"
        Say '  6) Quit'
        $choice = (Read-Host "`nPick 1-6 [1]").Trim()
        if (-not $choice) { $choice = '1' }
        switch ($choice) {
            '1' { Invoke-Install $dir $false }
            '2' { Invoke-Update $dir }
            '3' { Invoke-Install $dir $true }
            '4' { Invoke-Uninstall $dir }
            '5' { Invoke-GridMenu $dir }
        }
    }
} catch {
    Write-Host "`n$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Stuck? Ask 'thedenis' on the Project Rubi-Ka Discord (send a screenshot of this window)." -ForegroundColor Cyan
    if (-not $Interactive) { exit 1 }
}
if ($Interactive) { [void](Read-Host "`nPress Enter to close") }
