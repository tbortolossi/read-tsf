# Install, update and contribute to the read-tsf skill, with or without GitHub.
# The Windows twin of read-tsf-sync: same commands, same working copy, same
# contribution format. Runs on Windows PowerShell 5.1 and PowerShell 7.
#
#   read-tsf-sync install    [<read-tsf-X.Y.Z.tar.gz>] [--replace]
#   read-tsf-sync update     [<read-tsf-X.Y.Z.tar.gz>]
#   read-tsf-sync status
#   read-tsf-sync contribute -m "<summary>" [-d "<details>"] [--author "Name <mail>"]
#                            [--evidence "platform ;; PAN-OS ;; check ;; result"]...
#                            [--no-evidence "<why>"] [--tsf <extracted-tsf>]
#                            [--offline] [--yes] [--out <dir>]
#
# Run it through read-tsf-sync.cmd, or `powershell -NoProfile -File
# read-tsf-sync.ps1 ...`. It needs nothing beyond what Windows 10 and later
# ship (tar.exe, PowerShell); git and gh are used when they are there.
#
# It never bypasses the execution policy, never encodes a command, never
# downloads anything but through git, never sends mail, and leaves no
# scheduled task, service, registry key or PATH change behind. If the
# execution policy refuses an unsigned local script, that is your IT's call:
# `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned`, or have it signed.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$RepoUrl    = if ($env:READ_TSF_REPO_URL) { $env:READ_TSF_REPO_URL } else { 'https://github.com/tbortolossi/read-tsf.git' }
$GhRepo     = 'tbortolossi/read-tsf'
$Maintainer = 'Thomas Bortolossi <thomasbortolossi@gmail.com>'
$Market     = 'tbortolossi'
$Plugin     = 'read-tsf@tbortolossi'
$Manifest   = 'plugins/read-tsf/.claude-plugin/plugin.json'

# What a contribution may carry. Same lists in read-tsf-sync and tools/intake.sh.
$AllowPath = '^(plugins/read-tsf/.+|tools/[^/]+|\.claude-plugin/marketplace\.json|\.github/workflows/[^/]+|[A-Z]+\.md)$'
$AllowExt  = '(\.(md|sh|ps1|cmd|json|yml|yaml|txt)|/bin/read-tsf-sync)$'
$MaxFile   = 524288

$IsWin = $env:OS -eq 'Windows_NT'
if ($env:READ_TSF_HOME) { $HomeDir = $env:READ_TSF_HOME }
elseif ($IsWin) { $HomeDir = Join-Path $env:LOCALAPPDATA 'read-tsf' }
else { $HomeDir = Join-Path $HOME '.local/share/read-tsf' }
$Work = Join-Path $HomeDir 'repo'
$Base = Join-Path $HomeDir 'base'
$Tmp  = Join-Path ([IO.Path]::GetTempPath()) ('read-tsf-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $Tmp | Out-Null
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Replace = $false
$script:Hush = $false

function Say([string]$m)  { Write-Output $m }
function Note([string]$m) { if (-not $script:Hush) { [Console]::Error.WriteLine($m) } }
function Die([string]$m)  { [Console]::Error.WriteLine("read-tsf-sync: $m"); throw 'read-tsf-sync-exit' }
function Have([string]$c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }

# Native commands: stdout returned, stderr shown (or dropped with -Quiet),
# exit code in $script:Code. Stderr is never turned into a PowerShell error.
function X([string]$exe, [string[]]$a, [switch]$Quiet, [switch]$Check) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    if ($Quiet) { $out = & $exe @a 2>$null } else { $out = & $exe @a }
  } finally { $ErrorActionPreference = $old }
  $script:Code = $LASTEXITCODE
  if ($Check -and $script:Code -ne 0) { Die "$exe $($a -join ' ') failed ($script:Code)" }
  return $out
}

function TarExe {
  if ($IsWin) {
    $t = Join-Path $env:SystemRoot 'System32\tar.exe'   # not Git's tar, which reads C: as a host
    if (Test-Path $t) { return $t }
  }
  return 'tar'
}

function VersionOf([string]$tree) {
  $p = Join-Path $tree $Manifest
  if (-not (Test-Path $p)) { return '' }
  return (Get-Content -Raw -Path $p | ConvertFrom-Json).version
}
function Newer([string]$a, [string]$b) { return ([version]$a) -gt ([version]$b) }

function Mode {
  if (Test-Path (Join-Path $Work '.git')) { return 'online' }
  if (Test-Path $Base) { return 'offline' }
  return 'none'
}

# --- text, hashes, what may leave the machine --------------------------------

# A file as it is compared and shipped: no UTF-8 BOM, no CR, ends with LF.
function NormBytes([string]$path) {
  $b = [IO.File]::ReadAllBytes($path)
  $start = 0
  if ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) { $start = 3 }
  $ms = New-Object System.IO.MemoryStream
  $last = -1
  for ($i = $start; $i -lt $b.Length; $i++) {
    if ($b[$i] -ne 13) { $ms.WriteByte($b[$i]); $last = $b[$i] }
  }
  if ($last -ne -1 -and $last -ne 10) { $ms.WriteByte(10) }
  return ,$ms.ToArray()
}
function Sha([byte[]]$bytes) {
  $h = [Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($h) -replace '-', '').ToLower()
}
function HashN([string]$path) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return '-' }
  return Sha (NormBytes $path)
}
function Same([string]$a, [string]$b) {   # raw bytes equal is the fast path
  $ra = [IO.File]::ReadAllBytes($a); $rb = [IO.File]::ReadAllBytes($b)
  if ($ra.Length -eq $rb.Length -and (Sha $ra) -eq (Sha $rb)) { return $true }
  return (HashN $a) -eq (HashN $b)
}
function Allowed([string]$p) { return ($p -cmatch $AllowPath) -and ($p -cmatch $AllowExt) }
function IsText([string]$path) { return [Array]::IndexOf([IO.File]::ReadAllBytes($path), [byte]0) -lt 0 }

function FilesIn([string]$root) {
  if (-not (Test-Path $root)) { return @() }
  $full = (Resolve-Path $root).Path.TrimEnd('\', '/')
  $list = Get-ChildItem -LiteralPath $full -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($full.Length + 1) -replace '\\', '/'
    if (-not ($rel -eq '.git' -or $rel.StartsWith('.git/'))) { $rel }
  }
  return @($list)
}
function P([string]$root, [string]$rel) { return Join-Path $root ($rel -replace '/', [IO.Path]::DirectorySeparatorChar) }

function BaseCommit {
  switch (Mode) {
    'online' {
      $c = X git @('-C', $Work, 'merge-base', 'HEAD', 'origin/main') -Quiet
      if ($script:Code -ne 0) { $c = X git @('-C', $Work, 'rev-parse', 'HEAD') -Quiet }
      return "$c".Trim()
    }
    'offline' {
      $s = P $Base '.read-tsf-release'
      if (Test-Path $s) { return (Get-Content -Raw $s).Trim() }
      return 'unknown'
    }
    default { return 'unknown' }
  }
}

function BaseTree {
  if ((Mode) -eq 'offline') { return $Base }
  $t = Join-Path $Tmp 'base'
  if (-not (Test-Path $t)) {
    New-Item -ItemType Directory -Path $t | Out-Null
    $tar = Join-Path $Tmp 'base.tar'
    X git @('-C', $Work, 'archive', '-o', $tar, (BaseCommit)) -Check | Out-Null
    X (TarExe) @('-xf', $tar, '-C', $t) -Check | Out-Null
  }
  return $t
}

function Changes {   # objects {Op; Path}; what is not part of the skill is reported, not sent
  $base = BaseTree
  $all = @(FilesIn $base) + @(FilesIn $Work) | Sort-Object -Unique
  foreach ($p in $all) {
    if ($p -eq '.read-tsf-release') { continue }
    $w = P $Work $p; $o = P $base $p
    $inW = Test-Path -LiteralPath $w -PathType Leaf; $inB = Test-Path -LiteralPath $o -PathType Leaf
    if (-not $inW) { $op = 'delete' }
    elseif (-not $inB) { $op = 'add' }
    elseif (-not (Same $w $o)) { $op = 'modify' }
    else { continue }
    if (-not (Allowed $p)) { if ($op -ne 'delete') { Note "not included (not part of the skill): $p" }; continue }
    if ($op -ne 'delete') {
      if (-not (IsText $w)) { Note "not included (binary): $p"; continue }
      if ((Get-Item -LiteralPath $w).Length -gt $MaxFile) { Note "not included (over $MaxFile bytes): $p"; continue }
    }
    [pscustomobject]@{ Op = $op; Path = $p }
  }
}

# Same patterns as tools/check-no-customer-data.sh, for machines without bash,
# plus the checks only a contribution gets. $items: @{Name; Lines}.
$Tlds = 'com|net|org|fr|de|be|ch|uk|it|es|nl|lu|at|se|no|dk|fi|pl|pt|io|eu|us|ca|au|jp|info|biz|local|corp|lan|intra|internal|int'
$KnownDomains = '(^|\.)(example\.(com|net|org)|anon\.internal|paloaltonetworks\.com|github\.com|githubusercontent\.com|anthropic\.com|claude\.com|claude\.ai|keepachangelog\.com|semver\.org|shellcheck\.net)$'
$TsfKeys = 'hostname|serial|domain|ip-address|public-ip-address|ipv6-address|mac-address|default-gateway'

function CustomerData($items, [string[]]$deny) {
  $hits = @()
  $cred = 'BEGIN [A-Z ]*PRIVATE' + ' KEY|ghp_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN ' + 'CERTIFICATE-----|-AQ' + '==[A-Za-z0-9+/=]{8,}|\$[156]\$[A-Za-z0-9./]{8,}'
  foreach ($it in $items) {
    $n = 0
    foreach ($line in $it.Lines) {
      $n++
      $at = "$($it.Name):${n}:$line"
      if ($line -cmatch '(^|[^0-9.])([0-9]{1,3}\.){3}[0-9]{1,3}([^0-9.]|$)' -and
          $line -cnotmatch '(^|[^0-9.])(192\.0\.2\.|198\.51\.100\.|203\.0\.113\.|127\.0\.0\.1|0\.0\.0\.0|255\.255\.255\.)' -and
          $line -cnotmatch '(^|[^0-9.])100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\.') { $hits += "non-documentation IPv4 address: $at" }
      if ($line -cmatch '(^|[^0-9])0[0-9]{11}([^0-9]|$)') { $hits += "possible serial number: $at" }
      if ($line -cmatch '(^|[^0-9a-fA-F:])([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}([^0-9a-fA-F:]|$)' -and
          $line -notmatch '00:00:5e:00:53:|00:00:00:00:00:00|ff:ff:ff:ff:ff:ff') { $hits += "MAC address: $at" }
      if ($line -cmatch '<(hostname|serial|domain|phash|password|private-key|secret|pre-shared-key|key)>[^<\s][^<]*</') { $hits += "config value: $at" }
      if ($line -cmatch '(?<![\w.@-])[\w.%+-]+@(?:[a-zA-Z0-9-]*[a-zA-Z][a-zA-Z0-9-]*\.)+[a-zA-Z]{2,}\b' -and
          $line -cnotmatch 'thomasbortolossi@gmail\.com|noreply@|@example\.(com|org)|\.anon\.internal') { $hits += "unexpected e-mail address: $at" }
      if ($line -cmatch $cred) { $hits += "possible credential: $($it.Name):${n}" }
      foreach ($m in [regex]::Matches($line, "([a-z0-9-]+\.)+($Tlds)\.?([^a-z0-9-]|$)", 'IgnoreCase')) {
        $d = ($m.Value -replace '[^a-zA-Z0-9]+$', '').ToLower()
        if ($d -notmatch $KnownDomains) { $hits += "domain name: $d" }
      }
      foreach ($x in $deny) {
        if ($line.IndexOf($x, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hits += "identifier from the TSF or the denylist: $at" }
      }
    }
  }
  return @($hits | Select-Object -Unique)
}

function TextLines([byte[]]$bytes) {   # normalized bytes -> lines, without the empty one after the final LF
  $t = $Utf8.GetString($bytes)
  if ($t.Length -eq 0) { return ,@() }
  return ,($t.Substring(0, $t.Length - 1) -split "`n")
}

function NewLines([string]$basePath, [string]$workPath) {   # lines the edit brings in
  $work = TextLines (NormBytes $workPath)
  if (-not (Test-Path -LiteralPath $basePath -PathType Leaf)) { return ,$work }
  $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
  foreach ($l in (TextLines (NormBytes $basePath))) { [void]$seen.Add($l) }
  return ,@($work | Where-Object { -not $seen.Contains($_) })
}

function TsfIdentifiers([string]$dir) {   # identity of the device being analyzed, from show system info
  if (-not (Test-Path -LiteralPath $dir)) { Die "--tsf: no such file or directory: $dir" }
  if (Test-Path -LiteralPath $dir -PathType Leaf) { $files = @((Get-Item -LiteralPath $dir).FullName) }
  else {
    $files = @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter 'techsupport_*.txt' -ErrorAction SilentlyContinue |
      Where-Object { ($_.FullName -replace '\\', '/') -match '/tmp/cli/techsupport_[^/]*\.txt$' } | ForEach-Object { $_.FullName })
  }
  if (-not $files.Count) { Die "--tsf: no tmp/cli/techsupport_*.txt under $dir" }
  $ids = foreach ($f in $files) {
    foreach ($line in [IO.File]::ReadLines($f)) {
      if ($line -match "^\s*($TsfKeys):\s*(\S.*?)\s*$") {
        $v = $Matches[2]
        if ($v.Length -ge 4 -and $v -notmatch '^(unknown|none|n/a|off|on|yes|no|0\.0\.0\.0|::)$') { $v }
      }
    }
  }
  return ,@($ids | Sort-Object -Unique)
}

# --- carrying local edits across an update -----------------------------------

function SaveEdits {
  $base = BaseTree
  $saved = @()
  $script:Hush = $true; $list = @(Changes); $script:Hush = $false
  foreach ($c in $list) {
    $copy = $null
    if ($c.Op -ne 'delete') {
      $copy = P (Join-Path $Tmp 'edits') $c.Path
      New-Item -ItemType Directory -Force -Path (Split-Path $copy) | Out-Null
      Copy-Item -LiteralPath (P $Work $c.Path) -Destination $copy
    }
    $saved += [pscustomobject]@{ Op = $c.Op; Path = $c.Path; Was = (HashN (P $base $c.Path)); Copy = $copy }
  }
  return ,$saved
}

function RestoreEdits($saved) {
  $kept = 0
  $pending = Join-Path (Join-Path $HomeDir 'pending') (Get-Date -Format 'yyyyMMdd-HHmmss')
  foreach ($e in $saved) {
    $w = P $Work $e.Path
    $now = HashN $w
    $mine = if ($e.Copy) { HashN $e.Copy } else { '-' }
    if ($now -eq $mine) { Say "already in this release: $($e.Path)" }
    elseif ($now -eq $e.Was) {
      if ($e.Op -eq 'delete') { Remove-Item -LiteralPath $w -Force -ErrorAction SilentlyContinue }
      else { New-Item -ItemType Directory -Force -Path (Split-Path $w) | Out-Null; Copy-Item -LiteralPath $e.Copy -Destination $w -Force }
      $kept++
    } else {
      $dest = P $pending $e.Path
      New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
      if ($e.Op -eq 'delete') { New-Item -ItemType File -Path "$dest.deleted" | Out-Null }
      else { Copy-Item -LiteralPath $e.Copy -Destination $dest }
      Say "warning: $($e.Path) changed upstream too; your version is in $dest"
    }
  }
  if ($kept -gt 0) { Say "your local edits were kept ($kept file(s))" }
}

# --- where the skill comes from ----------------------------------------------

function GitHubUp {
  if (-not (Have git)) { return $false }
  $env:GIT_TERMINAL_PROMPT = '0'
  X git @('-c', 'http.lowSpeedLimit=1', '-c', 'http.lowSpeedTime=20', 'ls-remote', '-q', $RepoUrl, 'HEAD') -Quiet | Out-Null
  return $script:Code -eq 0
}

function FindArchive {
  $dirs = @((Get-Location).Path, (Join-Path $HOME 'Downloads'), (Join-Path $HOME "T$([char]0xE9)l$([char]0xE9)chargements"))
  if ($env:USERPROFILE) { $dirs += (Join-Path $env:USERPROFILE 'Downloads') }
  $found = foreach ($d in ($dirs | Select-Object -Unique)) {
    if (Test-Path $d) {
      Get-ChildItem -LiteralPath $d -File -Filter 'read-tsf-*.tar.gz' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^read-tsf-(\d+\.\d+\.\d+)\.tar\.gz$' } |
        ForEach-Object { [pscustomobject]@{ V = [version]$Matches[1]; Path = $_.FullName } }
    }
  }
  $best = @($found) | Sort-Object V | Select-Object -Last 1
  if ($best) { return $best.Path }
  return $null
}

function PickSource([string]$arg, [string]$cmd) {
  if ($arg) { return $arg }
  if (GitHubUp) { return 'online' }
  $best = FindArchive
  if ($best) { Note "GitHub is not reachable; using $best"; return $best }
  Die "GitHub is not reachable and no read-tsf-X.Y.Z.tar.gz was found here or in Downloads.`nPass the archive: read-tsf-sync $cmd C:\path\to\read-tsf-X.Y.Z.tar.gz"
}

function VerifyArchive([string]$tgz) {
  if (-not (Test-Path -LiteralPath $tgz -PathType Leaf)) { Die "no such archive: $tgz" }
  $sum = "$tgz.sha256"
  if (Test-Path -LiteralPath $sum) {
    $want = ((Get-Content -LiteralPath $sum -TotalCount 1) -split '\s+')[0].ToLower()
    $got = (Get-FileHash -Algorithm SHA256 -LiteralPath $tgz).Hash.ToLower()
    if ($want -ne $got) { Die "checksum mismatch for $tgz - do not install it" }
    Say 'checksum ok'
  } else {
    Say "note: no $(Split-Path -Leaf $sum) beside the archive, integrity not checked"
  }
}

function Unpack([string]$tgz, [string]$dest) {
  $out = Join-Path $Tmp ('unpack-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $out | Out-Null
  X (TarExe) @('-xzf', (Resolve-Path -LiteralPath $tgz).Path, '-C', $out) -Check | Out-Null
  $top = Get-ChildItem -LiteralPath $out -Directory | Select-Object -First 1
  if (-not $top -or -not (Test-Path (P $top.FullName $Manifest))) { Die "$tgz is not a read-tsf release archive" }
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest }
  Move-Item -LiteralPath $top.FullName -Destination $dest
}

function CopyTree([string]$from, [string]$to) {   # file by file, merging into $to
  foreach ($p in (FilesIn $from)) {
    $d = P $to $p
    New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null
    Copy-Item -LiteralPath (P $from $p) -Destination $d -Force
  }
}

# Updates happen in place: on Windows a directory that is someone's current
# directory, or holds the running launcher, cannot be renamed.
function DropShipped($saved) {
  if ((Mode) -eq 'online') { $shipped = @(X git @('-C', $Work, 'ls-files') -Check) } else { $shipped = @(FilesIn $Base) }
  foreach ($p in ($shipped + @($saved | ForEach-Object { $_.Path }))) {
    if ($p) { Remove-Item -LiteralPath (P $Work $p) -Force -ErrorAction SilentlyContinue }
  }
}

# --- Claude Code registration ------------------------------------------------

function Register {
  if ($env:READ_TSF_NO_REGISTER -eq '1') { Say 'READ_TSF_NO_REGISTER=1: Claude Code left untouched'; return }
  if (-not (Have claude)) {
    Say 'claude is not on PATH. Run these once it is:'
    Say "  claude plugin marketplace add `"$Work`""
    Say "  claude plugin install $Plugin"
    return
  }
  $list = @(X claude @('plugin', 'marketplace', 'list') -Quiet)
  $current = ''
  for ($i = 0; $i -lt $list.Count; $i++) {
    if ("$($list[$i])" -match [regex]::Escape($Market)) { $current = ($list[$i..([Math]::Min($i + 3, $list.Count - 1))] -join "`n"); break }
  }
  if ($current -and -not $current.Contains($Work)) {
    if (-not $script:Replace) {
      Say "Claude Code already has a '$Market' marketplace from another source:"
      Say $current
      Say "Run 'read-tsf-sync install --replace' to point it at $Work instead."
      throw 'read-tsf-sync-exit'
    }
    Say "replacing the existing '$Market' marketplace with $Work"
    X claude @('plugin', 'marketplace', 'remove', $Market) -Check | Out-Null
    $current = ''
  }
  if (-not $current) { X claude @('plugin', 'marketplace', 'add', $Work) -Check }
  X claude @('plugin', 'marketplace', 'update', $Market) -Check
  if ((@(X claude @('plugin', 'list') -Quiet) -join "`n").Contains($Plugin)) { X claude @('plugin', 'update', $Plugin) -Check }
  else { X claude @('plugin', 'install', $Plugin) -Check }
  Say "restart Claude Code to load read-tsf $(VersionOf $Work)"
}

function WriteLauncher {   # outside the working copy, so an update never pulls it from under cmd.exe
  if (-not $IsWin) { return }
  $l = Join-Path $HomeDir 'read-tsf-sync.cmd'
  $text = "@echo off`r`npowershell.exe -NoProfile -File `"%~dp0repo\plugins\read-tsf\bin\read-tsf-sync.ps1`" %*`r`n"
  [IO.File]::WriteAllText($l, $text, [Text.Encoding]::ASCII)
  Say "command: $l"
}

# --- commands ----------------------------------------------------------------

function Install([string]$arg) {
  if ((Mode) -ne 'none') {
    if (-not $script:Replace) { Die "already installed in $HomeDir ($(Mode) mode) - use 'update'" }
    Register; return
  }
  $src = PickSource $arg 'install'
  New-Item -ItemType Directory -Force -Path $HomeDir | Out-Null
  if ($src -eq 'online') {
    X git @('clone', '--quiet', $RepoUrl, $Work) -Check | Out-Null
  } else {
    VerifyArchive $src
    Unpack $src $Base
    CopyTree $Base $Work
  }
  WriteLauncher
  Say "installed read-tsf $(VersionOf $Work) in $Work ($(Mode) mode)"
  Register
}

function Update([string]$arg) {
  $m = Mode
  if ($m -eq 'none') { Die "not installed - run 'install' first" }
  $before = VersionOf $Work
  if (-not $arg -and $m -eq 'online') {
    if (-not (GitHubUp)) { Die 'GitHub is not reachable. This copy follows it; pass a release archive to switch it to offline updates.' }
    $src = 'online'
  } else { $src = PickSource $arg 'update' }

  $new = Join-Path $Tmp 'new'
  if ($src -ne 'online') {
    VerifyArchive $src
    Unpack $src $new
    $nv = VersionOf $new
    if (-not (Newer $nv $before) -and $env:FORCE -ne '1') {
      if ($nv -eq $before) { Say "read-tsf $before is already installed"; return }
      Die "$src is $nv, older than the installed $before (FORCE=1 to downgrade)"
    }
  }
  $saved = SaveEdits

  if ($src -eq 'online' -and $m -eq 'online') {
    foreach ($e in $saved) {
      X git @('-C', $Work, 'ls-files', '--error-unmatch', '--', $e.Path) -Quiet | Out-Null
      if ($script:Code -eq 0) { X git @('-C', $Work, 'checkout', '-q', '--', $e.Path) -Check | Out-Null }
      else { Remove-Item -LiteralPath (P $Work $e.Path) -Force }
    }
    X git @('-C', $Work, 'pull', '--ff-only', '--quiet') | Out-Null
    if ($script:Code -ne 0) {
      RestoreEdits $saved | Out-Null
      Die "could not fast-forward $Work (local commits?); your edits are back in the tree"
    }
  } elseif ($src -eq 'online') {   # offline copy, GitHub reachable now: become a clone
    $clone = Join-Path $Tmp 'clone'
    X git @('clone', '--quiet', $RepoUrl, $clone) -Check | Out-Null
    $nv = VersionOf $clone
    if ((Newer $before $nv) -and $env:FORCE -ne '1') { Die "GitHub has $nv, older than the installed $before (FORCE=1 to switch anyway)" }
    DropShipped $saved
    Move-Item -LiteralPath (Join-Path $clone '.git') -Destination (Join-Path $Work '.git')
    X git @('-C', $Work, 'reset', '-q', '--hard') -Check | Out-Null
    Remove-Item -Recurse -Force $Base
    Say 'this copy now follows GitHub'
  } else {
    DropShipped $saved
    if ($m -eq 'online') {   # set aside, not deleted
      Move-Item -LiteralPath (Join-Path $Work '.git') -Destination (Join-Path $HomeDir ('git-' + (Get-Date -Format 'yyyyMMdd-HHmmss')))
    }
    CopyTree $new $Work
    if (Test-Path $Base) { Remove-Item -Recurse -Force $Base }
    CopyTree $new $Base
  }
  RestoreEdits $saved
  Say "read-tsf $before -> $(VersionOf $Work) ($(Mode) mode)"
  Register
}

function Status {
  Say "working copy: $Work"
  Say "mode:         $(Mode)"
  if ((Mode) -eq 'none') { return }
  Say "version:      $(VersionOf $Work)"
  Say "base commit:  $(BaseCommit)"
  $list = @(Changes)
  if ($list.Count) { Say 'local edits:'; foreach ($c in $list) { Say "  $($c.Op)`t$($c.Path)" } }
  else { Say 'local edits:  none' }
}

function Conventional([string]$s) {
  if ($s -cmatch '^[a-z]+(\([a-z0-9-]+\))?!?: ') { return $s }
  return "docs(read-tsf): $s"
}

function Contribute([string[]]$a) {
  $s = @{ Summary = ''; Details = ''; Author = ''; NoEvidence = ''; Tsf = ''; Evidence = @() }
  $offline = $false; $yes = $false; $out = (Get-Location).Path
  for ($i = 0; $i -lt $a.Count; $i++) {
    switch -CaseSensitive ($a[$i]) {
      '-m'            { $s.Summary = $a[++$i] }
      '-d'            { $s.Details = $a[++$i] }
      '--evidence'    { $s.Evidence += $a[++$i] }
      '--no-evidence' { $s.NoEvidence = $a[++$i] }
      '--tsf'         { $s.Tsf = $a[++$i] }
      '--author'      { $s.Author = $a[++$i] }
      '--offline'     { $offline = $true }
      '--yes'         { $yes = $true }
      '--out'         { $out = $a[++$i] }
      default         { Die "unknown option: $($a[$i])" }
    }
  }
  if (-not $s.Summary) { Die 'say what the change is: -m "fix the GP log path on 11.1"' }
  if ((Mode) -eq 'none') { Die 'not installed - nothing to contribute' }

  $changes = @(Changes)
  if (-not $changes.Count) { Die "no edits to the skill in $Work" }
  Say 'this contribution carries:'
  foreach ($c in $changes) { Say "  $($c.Op)`t$($c.Path)" }

  if (-not $s.Evidence.Count -and -not $s.NoEvidence -and @($changes | Where-Object { $_.Path.StartsWith('plugins/read-tsf/skills/read-tsf/') }).Count) {
    Die ("say where it was verified, once per archive:`n" +
         "  --evidence `"PA-3220 ;; 11.1.6 ;; grep -c 'IKE SA' var/log/pan/ikemgr.log ;; one line per rekey`"`n" +
         'or, for a change that makes no new claim: --no-evidence "typo"')
  }

  if (-not $s.Author -and (Have git)) {
    $n = "$(X git @('-C', $Work, 'config', 'user.name') -Quiet)".Trim()
    $e = "$(X git @('-C', $Work, 'config', 'user.email') -Quiet)".Trim()
    if ($n -and $e) { $s.Author = "$n <$e>" }
  }
  if (-not $s.Author) { Die 'say who you are: --author "First Last <you@example.com>"' }

  # The rule of this repository applies before anything leaves the machine.
  $s.Report = ScanContribution $s $changes

  $why = ''
  if ($offline) { $why = '--offline was given' }
  elseif ((Mode) -ne 'online') { $why = 'this copy was installed from an archive, not cloned' }
  elseif (-not (Have gh)) { $why = 'gh is not installed' }
  else {
    X gh @('auth', 'status') -Quiet | Out-Null
    if ($script:Code -ne 0) { $why = 'gh is not logged in (gh auth login)' }
    else {
      X gh @('api', "repos/$GhRepo", '--silent') -Quiet | Out-Null
      if ($script:Code -ne 0) { $why = 'GitHub does not answer' }
    }
  }
  if ($why) {
    Say "writing a file to e-mail ($why)"
    ContributeFile $s $out $changes
  } elseif ($yes) {
    ContributePr $s $changes
  } else {
    Say ''
    Say "gh is logged in: rerun with --yes to open a pull request on $GhRepo with these files,"
    Say 'or with --offline to write a file to e-mail instead. Nothing was sent.'
  }
}

# Every check that stands between an edit and the outside world. Runs on the
# lines the edit adds and on the text written around it (summary, evidence).
function ScanContribution($s, $changes) {
  $base = BaseTree
  $items = @(); $n = 0
  foreach ($c in $changes) {
    if ($c.Op -eq 'delete') { continue }
    $lines = NewLines (P $base $c.Path) (P $Work $c.Path)
    $n += $lines.Count
    $items += [pscustomobject]@{ Name = $c.Path; Lines = $lines }
  }
  $human = @($s.Summary, $s.Details) + $s.Evidence + @($s.NoEvidence)
  $items += [pscustomobject]@{ Name = 'summary-and-evidence'; Lines = $human }

  $deny = @(); $denyN = 0; $tsfN = 0
  $dl = Join-Path $HomeDir 'denylist.txt'
  if (Test-Path -LiteralPath $dl) {
    $deny += @([IO.File]::ReadAllLines($dl) | ForEach-Object { $_.Trim() } | Where-Object { $_ -and -not $_.StartsWith('#') })
    $denyN = $deny.Count
  }
  if ($s.Tsf) { $ids = TsfIdentifiers $s.Tsf; $tsfN = $ids.Count; $deny += $ids }

  $hits = @(CustomerData $items $deny)
  if ($hits.Count) {
    $hits | ForEach-Object { Note $_ }
    Note ''
    Note 'Use the placeholders in CLAUDE.md (192.0.2.x, hostNNN, userNNN, ZONE-0012, <serial>).'
    Die 'fix the above before contributing - nothing was written or sent'
  }
  if ($s.Tsf) { $src = "$tsfN identifier(s) of the analyzed TSF (hostname, serial, domain, addresses)" }
  else { $src = 'no TSF given (--tsf), so its own hostname and serial were not looked for' }
  switch ($denyN) { 0 { $dn = 'none on this machine' } 1 { $dn = '1 entry, no hit' } default { $dn = "$denyN entries, no hit" } }
  [Console]::Out.WriteLine("checks passed: nothing that looks like customer data in $n new line(s)")   # not Say: this function returns a value
  $dash = [char]0x2014
  return ("- Customer-data patterns $dash addresses outside the documentation ranges, e-mail, serials, MAC, config values, secrets, domain names $dash on $n new line(s) and the text above: no hit.`n" +
          "- ${src}: no hit.`n- Personal denylist: $dn.")
}

function FenceFor([string]$text) {   # a code fence longer than any backtick run in the text
  $max = 0
  foreach ($m in [regex]::Matches($text, '`+')) { if ($m.Length -gt $max) { $max = $m.Length } }
  if ($max -lt 3) { $max = 2 }
  return ('`' * ($max + 1))
}

function FileDiff([string]$op, [string]$path) {   # unified diff of the normalized texts, or $null
  if (-not (Have git)) { return $null }
  $d = Join-Path $Tmp ('diff-' + [guid]::NewGuid().ToString('N'))
  $a = '/dev/null'; $b = '/dev/null'
  if ($op -ne 'add') { $f = P (Join-Path $d 'a') $path; New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null; [IO.File]::WriteAllBytes($f, (NormBytes (P (BaseTree) $path))); $a = "a/$path" }
  if ($op -ne 'delete') { $f = P (Join-Path $d 'b') $path; New-Item -ItemType Directory -Force -Path (Split-Path $f) | Out-Null; [IO.File]::WriteAllBytes($f, (NormBytes (P $Work $path))); $b = "b/$path" }
  Push-Location $d
  try { $out = @(X git @('-c', 'core.quotepath=off', 'diff', '--no-index', '--no-color', '--src-prefix=', '--dst-prefix=', '--', $a, $b) -Quiet) }
  finally { Pop-Location }
  return ,@($out | Where-Object { $_ -notmatch '^(diff --git|index |new file mode|deleted file mode)' })
}

function EvidenceRow([string]$e) {   # "platform ;; version ;; check ;; result" -> a table row
  $f = @($e -split ' ;; ') + @('', '', '', '')
  $check = $f[2]
  if ($check -and -not $check.Contains('`')) { $check = '`' + $check + '`' }
  return "| $($f[0]) | $($f[1]) | $($check -replace '\|', '\|') | $($f[3]) |"
}

function WriteMarkdown($s, [string]$out, $changes) {   # the contribution, for a human first
  $subject = Conventional $s.Summary
  $base = BaseTree
  $v = VersionOf $Work
  $name = ($s.Author -replace '\s*<.*$', '')
  $lines = New-Object 'System.Collections.Generic.List[string]'
  $add = { param([string]$l) $lines.Add($l) }
  & $add '<!-- read-tsf contribution'; & $add 'Format: 3'; & $add "From: $($s.Author)"
  & $add "Base-Version: $v"; & $add "Base-Commit: $(BaseCommit)"
  & $add "Date: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"; & $add "Subject: $subject"; & $add '-->'
  & $add ''; & $add "# $subject"; & $add ''
  & $add "Contribution to **read-tsf $v** from $name, $((Get-Date).ToUniversalTime().ToString('yyyy-MM-dd'))."
  & $add "Send this file, as an attachment, to $Maintainer."; & $add ''
  & $add '<!-- read-tsf pr-body -->'; & $add '## Summary'; & $add ''
  if ($s.Details) { & $add ($s.Details -replace "`r", '') } else { & $add $s.Summary }
  & $add ''; & $add '## Evidence'; & $add ''
  if ($s.Evidence.Count) {
    & $add '| Platform | PAN-OS | What was checked | Result |'; & $add '|---|---|---|---|'
    foreach ($e in $s.Evidence) { & $add (EvidenceRow $e) }
  } else { & $add "None given: $($s.NoEvidence)" }
  & $add ''; & $add '## Changes'; & $add ''; & $add '| File | Change | Lines |'; & $add '|---|---|---|'
  $diffs = @()
  foreach ($c in $changes) {
    $d = FileDiff $c.Op $c.Path
    if ($null -ne $d -and $d.Count) {
      $diffs += $d
      $body = @($d | Select-Object -Skip 2)
      $plus = @($body | Where-Object { $_.StartsWith('+') }).Count; $minus = @($body | Where-Object { $_.StartsWith('-') }).Count
      & $add "| ``$($c.Path)`` | $($c.Op) | +$plus $([char]0x2212)$minus |"
    } else { & $add "| ``$($c.Path)`` | $($c.Op) | |" }
  }
  & $add ''; & $add '## Checks run before sending'; & $add ''
  foreach ($l in ($s.Report -split "`n")) { & $add $l }
  & $add '<!-- read-tsf pr-body end -->'; & $add ''; & $add '## Diff'; & $add ''
  if ($diffs.Count) {
    $fence = FenceFor ($diffs -join "`n")
    & $add "${fence}diff"; foreach ($l in $diffs) { & $add $l }; & $add $fence
  } else { & $add 'No diff tool on this machine; the full text below is what counts.' }
  & $add ''; & $add '## Full text of the changed files'; & $add ''
  & $add 'Read by `tools/intake.sh`. Do not edit below this line.'; & $add ''

  $fs = [IO.File]::Create($out)
  try {
    $w = { param([string]$t) $bytes = $Utf8.GetBytes("$t`n"); $fs.Write($bytes, 0, $bytes.Length) }
    foreach ($l in $lines) { & $w $l }
    foreach ($c in $changes) {
      $was = HashN (P $base $c.Path)
      & $w "### ``$($c.Path)`` ($($c.Op))"; & $w ''
      if ($c.Op -eq 'delete') {
        & $w "<!-- read-tsf file: delete $($c.Path) base=$was lines=0 -->"
      } else {
        $body = NormBytes (P $Work $c.Path)
        $count = 0; foreach ($x in $body) { if ($x -eq 10) { $count++ } }
        $fence = FenceFor ($Utf8.GetString($body))
        & $w "<!-- read-tsf file: $($c.Op) $($c.Path) base=$was lines=$count -->"
        & $w "${fence}text"
        $fs.Write($body, 0, $body.Length)
        & $w $fence
      }
      & $w ''
    }
    & $w '<!-- read-tsf end -->'
  } finally { $fs.Close() }
}

function ContributePr($s, $changes) {
  $title = Conventional $s.Summary
  $doc = Join-Path $Tmp 'contribution.md'
  WriteMarkdown $s $doc $changes
  $all = [IO.File]::ReadAllLines($doc)
  $a = [Array]::IndexOf($all, '<!-- read-tsf pr-body -->'); $b = [Array]::IndexOf($all, '<!-- read-tsf pr-body end -->')
  $body = Join-Path $Tmp 'pr-body.md'
  [IO.File]::WriteAllText($body, (($all[($a + 1)..($b - 1)] -join "`n") + "`n`nSent with ``read-tsf-sync contribute`` from read-tsf $(VersionOf $Work).`n"), $Utf8)

  $slug = (($s.Summary.ToLower() -replace '[^a-z0-9]+', '-').Trim('-'))
  if ($slug.Length -gt 40) { $slug = $slug.Substring(0, 40).TrimEnd('-') }
  $branch = "contrib/$(Get-Date -Format yyyyMMdd)-$slug"
  X git @('-C', $Work, 'switch', '-q', '-c', $branch) -Check | Out-Null
  foreach ($c in $changes) {
    if ($c.Op -eq 'delete') { X git @('-C', $Work, 'rm', '-q', '--cached', '--', $c.Path) -Check | Out-Null }
    else { X git @('-C', $Work, 'add', '--', $c.Path) -Check | Out-Null }
  }
  # Messages go through files: Windows PowerShell 5.1 mangles quotes in native arguments.
  $msg = Join-Path $Tmp 'msg.txt'
  $text = $title; if ($s.Details) { $text += "`n`n$($s.Details)" }
  [IO.File]::WriteAllText($msg, "$text`n", $Utf8)
  $name = ($s.Author -replace '\s*<.*$', ''); $mail = ($s.Author -replace '^.*<(.*)>.*$', '$1')
  X git @('-C', $Work, '-c', "user.name=$name", '-c', "user.email=$mail", 'commit', '-q', '-F', $msg) -Check | Out-Null
  $remote = 'origin'
  if ("$(X gh @('api', "repos/$GhRepo", '--jq', '.permissions.push') -Quiet)".Trim() -ne 'true') {
    Push-Location $Work; try { X gh @('repo', 'fork', $GhRepo, '--remote', '--remote-name', 'fork') -Quiet | Out-Null } finally { Pop-Location }
    $remote = 'fork'
  }
  X git @('-C', $Work, 'push', '-q', '-u', $remote, $branch) -Check | Out-Null
  $head = $branch
  if ($remote -ne 'origin') { $head = "$("$(X gh @('api', 'user', '--jq', '.login') -Quiet)".Trim()):$branch" }
  Push-Location $Work
  try { X gh @('pr', 'create', '--repo', $GhRepo, '--head', $head, '--base', 'main', '--title', $title, '--body-file', $body) -Check }
  finally { Pop-Location }
  # Back on main with the edit still in the tree, so the skill keeps it until the merge.
  $paths = @($changes | ForEach-Object { $_.Path })
  X git @('-C', $Work, 'switch', '-q', 'main') -Check | Out-Null
  X git (@('-C', $Work, 'checkout', '-q', $branch, '--') + $paths) -Quiet | Out-Null
  X git (@('-C', $Work, 'reset', '-q', '--') + $paths) -Quiet | Out-Null
  Say "pull request opened; your copy keeps the edit until 'update' brings the merged version"
}

function ContributeFile($s, [string]$dir, $changes) {
  $ok = $false
  try { if (Test-Path $dir -PathType Container) { $probe = Join-Path $dir ('read-tsf-probe-' + [guid]::NewGuid().ToString('N')); [IO.File]::WriteAllText($probe, ''); Remove-Item -Force -LiteralPath $probe; $ok = $true } } catch { $ok = $false }
  if (-not $ok) { $dir = Join-Path $HomeDir 'outbox'; New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $out = Join-Path $dir "read-tsf-$(VersionOf $Work)-contribution-$(Get-Date -Format 'yyyyMMdd-HHmmss').md"
  WriteMarkdown $s $out $changes
  Say ''
  Say "wrote $out"
  Say 'It is a Markdown document: read it before sending - summary, evidence, diff, then the full text.'
  Say "E-mail it yourself, as an attachment, to $Maintainer"
  Say "subject: [read-tsf] $(Conventional $s.Summary)"
  Say "Your copy keeps the edit; 'update' carries it over until a release includes it."
}

function Usage {
  Get-Content -LiteralPath $PSCommandPath | Select-Object -Skip 4 -First 7 | ForEach-Object { $_ -replace '^# ?', '' }
}

$rest = @($args | Where-Object { $_ -ne '--replace' })
if ($rest.Count -ne $args.Count) { $script:Replace = $true }
$cmd = if ($rest.Count) { $rest[0] } else { '' }
$more = [string[]]@()   # an empty array assigned from an if-statement would become $null
if ($rest.Count -gt 1) { $more = [string[]]$rest[1..($rest.Count - 1)] }
$status = 0
try {
  switch -CaseSensitive ($cmd) {
    'install'    { Install $(if ($more.Count) { $more[0] } else { '' }) }
    'update'     { Update $(if ($more.Count) { $more[0] } else { '' }) }
    'status'     { Status }
    'contribute' { Contribute $more }
    { $_ -in 'help', '-h', '--help' } { Usage }
    default      { Usage; $status = 2 }
  }
} catch {
  if ("$_" -ne 'read-tsf-sync-exit') { [Console]::Error.WriteLine("read-tsf-sync: $_"); if ($env:READ_TSF_DEBUG) { [Console]::Error.WriteLine($_.ScriptStackTrace) } }
  $status = 1
} finally {
  Remove-Item -Recurse -Force $Tmp -ErrorAction SilentlyContinue
}
exit $status
