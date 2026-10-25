<#
.SYNOPSIS
    Copies WorkWithCC shared rules and skills into a project's .claude/ folder.
.EXAMPLE
    .\sync.ps1 -Target C:\path\to\Project -WhatIf
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Target
)

$ErrorActionPreference = 'Stop'
# No BOM: a BOM in front of SKILL.md breaks YAML frontmatter parsing.
# PS 5.1 Set-Content/Out-File add one, so all writes go through WriteAllBytes.
$utf8 = New-Object Text.UTF8Encoding $false
$header = '<!-- 由 WorkWithCC 同步，修改請到 WorkWithCC -->'
$manifestRel = '.claude/workwithcc/manifest.txt'

function Fail([string]$message) {
    [Console]::Error.WriteLine($message)
    exit 1
}

# --- Validate target ---
if (-not (Test-Path -LiteralPath $Target -PathType Container)) { Fail "找不到目標資料夾：$Target" }
$Target = [IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Target).ProviderPath).TrimEnd('\', '/')
$source = [IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\', '/')
if ($Target -eq $source) { Fail '目標不能是 WorkWithCC 自己。' }
if (-not (Test-Path -LiteralPath (Join-Path $Target '.git'))) { Fail "目標必須是 git repo 的根目錄：$Target" }

# --- Build desired content: target-relative path -> bytes ---
function Add-Header([string]$text) {
    $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    # Frontmatter must stay on line 1, so the header goes right after it.
    $m = [regex]::Match($text, '\A---\r?\n[\s\S]*?\r?\n---[ \t]*(\r?\n|\z)')
    if ($m.Success) {
        $end = $m.Index + $m.Length
        $sep = if ($m.Groups[1].Value) { '' } else { $nl }
        return $text.Substring(0, $end) + $sep + $header + $nl + $text.Substring($end)
    }
    return $header + $nl + $nl + $text
}

$desired = @{}  # case-insensitive, matches Windows paths
function Add-Source([string]$file, [string]$rel) {
    if ($file -like '*.md') {
        # ReadAllText strips a source BOM if present.
        $desired[$rel] = $utf8.GetBytes((Add-Header ([IO.File]::ReadAllText($file))))
    } else {
        $desired[$rel] = [IO.File]::ReadAllBytes($file)
    }
}

$shared = Join-Path $source 'shared'
Add-Source (Join-Path $shared 'CLAUDE.md') '.claude/workwithcc/CLAUDE.md'
$skills = Join-Path $shared 'skills'
if (Test-Path -LiteralPath $skills) {
    foreach ($f in Get-ChildItem -LiteralPath $skills -Recurse -File -Force) {
        Add-Source $f.FullName ('.claude/skills/' + $f.FullName.Substring($skills.Length + 1).Replace('\', '/'))
    }
}

# --- First run check: must happen before any write ---
$manifestPath = Join-Path $Target $manifestRel
$firstRun = -not (Test-Path -LiteralPath $manifestPath)
if ($firstRun -and (Test-Path -LiteralPath (Join-Path $Target 'CLAUDE.md'))) {
    Fail ('目標已有 CLAUDE.md，為避免覆蓋專案內容，同步已全部取消。' +
        '請手動把 `@.claude/workwithcc/CLAUDE.md` 和 `@Docs/Decisions.md` 加進現有的 CLAUDE.md，或先移走它再重新執行。')
}

# --- Writes ---
$added = New-Object Collections.Generic.List[string]
$updated = New-Object Collections.Generic.List[string]
$removed = New-Object Collections.Generic.List[string]

function Write-File([string]$rel, [byte[]]$bytes) {
    $path = [IO.Path]::GetFullPath((Join-Path $Target $rel))
    $exists = Test-Path -LiteralPath $path
    if ($exists -and [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -eq [Convert]::ToBase64String($bytes)) { return }
    if ($PSCmdlet.ShouldProcess($rel, $(if ($exists) { '更新' } else { '新增' }))) {
        [void][IO.Directory]::CreateDirectory((Split-Path $path))
        [IO.File]::WriteAllBytes($path, $bytes)
    }
    if ($exists) { $updated.Add($rel) } else { $added.Add($rel) }
}

# Template files belong to the project once created: never in the manifest.
if ($firstRun) {
    $templates = Join-Path $source 'templates'
    $claudeMd = [IO.File]::ReadAllText((Join-Path $templates 'CLAUDE.md')).Replace('{{ProjectName}}', (Split-Path -Leaf $Target))
    Write-File 'CLAUDE.md' ($utf8.GetBytes($claudeMd))
    if (-not (Test-Path -LiteralPath (Join-Path $Target 'Docs/Decisions.md'))) {
        Write-File 'Docs/Decisions.md' ($utf8.GetBytes([IO.File]::ReadAllText((Join-Path $templates 'Decisions.md'))))
    }
}

$sorted = @($desired.Keys | Sort-Object)
foreach ($rel in $sorted) { Write-File $rel $desired[$rel] }

# Delete files the previous sync wrote that the source no longer has.
if (-not $firstRun) {
    $claudeDir = Join-Path $Target '.claude'
    foreach ($rel in [IO.File]::ReadAllLines($manifestPath)) {
        # Only manifest entries inside .claude/ are ours to delete.
        if (-not $rel -or $desired.ContainsKey($rel) -or -not $rel.StartsWith('.claude/') -or $rel.Contains('..')) { continue }
        $path = [IO.Path]::GetFullPath((Join-Path $Target $rel))
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        if ($PSCmdlet.ShouldProcess($rel, '刪除')) {
            Remove-Item -LiteralPath $path -Force
            # Remove folders left empty, e.g. a deleted skill's folder.
            $dir = Split-Path $path
            while ($dir.Length -gt $claudeDir.Length -and -not (Get-ChildItem -LiteralPath $dir -Force | Select-Object -First 1)) {
                Remove-Item -LiteralPath $dir -Force
                $dir = Split-Path $dir
            }
        }
        $removed.Add($rel)
    }
}

Write-File $manifestRel ($utf8.GetBytes((($sorted | ForEach-Object { "$_`n" }) -join '')))

# --- Report ---
$mode = if ($WhatIfPreference) { '（預覽，未寫入任何檔案）' } else { '' }
Write-Host "同步完成：$Target$mode"
foreach ($group in @(@('新增', $added), @('更新', $updated), @('刪除', $removed))) {
    Write-Host "$($group[0])：$($group[1].Count) 個"
    foreach ($rel in $group[1]) { Write-Host "  $rel" }
}
