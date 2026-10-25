# Plain-assert tests for sync.ps1. Runs sync.ps1 in a child process of the
# same PowerShell edition, so run this file under both powershell and pwsh.
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot
$exe = (Get-Process -Id $PID).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('wwcc-tests-' + [guid]::NewGuid().ToString('N'))
$utf8 = New-Object Text.UTF8Encoding $false
$script:failures = 0

function Check([bool]$cond, [string]$name) {
    if ($cond) { Write-Host "  ok   $name" }
    else { Write-Host "  FAIL $name" -ForegroundColor Red; $script:failures++ }
}

function Write-Text([string]$path, [string]$text) {
    [void][IO.Directory]::CreateDirectory((Split-Path $path))
    [IO.File]::WriteAllText($path, $text, $utf8)
}

# Fresh copy of WorkWithCC with two test skills, so tests can edit the source.
function New-Source([string]$name) {
    $src = Join-Path $root $name
    [void][IO.Directory]::CreateDirectory($src)
    Copy-Item (Join-Path $repo 'sync.ps1') $src
    Copy-Item (Join-Path $repo 'shared') $src -Recurse
    Copy-Item (Join-Path $repo 'templates') $src -Recurse
    Write-Text "$src\shared\skills\demo\SKILL.md" "---`nname: demo`ndescription: Demo skill.`n---`n`n# Demo`n"
    Write-Text "$src\shared\skills\demo\notes.txt" "plain file`n"
    Write-Text "$src\shared\skills\gone\SKILL.md" "---`nname: gone`ndescription: Removed later.`n---`n`nBody`n"
    $src
}

function New-Target([string]$name) {
    $t = Join-Path $root $name
    [void][IO.Directory]::CreateDirectory("$t\.git")  # fake git repo root
    $t
}

function Invoke-Sync([string]$src, [string]$target, [string[]]$extra = @()) {
    # PS 5.1 turns a child's stderr into a terminating error under 'Stop'.
    $ErrorActionPreference = 'Continue'
    & $exe -NoProfile -ExecutionPolicy Bypass -File "$src\sync.ps1" -Target $target @extra *> $null
    $LASTEXITCODE
}

# Every file under the target (except .git) with its hash.
function Get-Snapshot([string]$target) {
    $snap = @{}
    foreach ($f in Get-ChildItem -LiteralPath $target -Recurse -File -Force | Where-Object { $_.FullName -notlike "$target\.git\*" }) {
        $snap[$f.FullName.Substring($target.Length + 1)] = (Get-FileHash -LiteralPath $f.FullName).Hash
    }
    $snap
}

function Same-Snapshot($a, $b) {
    if ($a.Count -ne $b.Count) { return $false }
    foreach ($k in $a.Keys) { if ($b[$k] -ne $a[$k]) { return $false } }
    $true
}

try {
    Write-Host "PowerShell $($PSVersionTable.PSVersion) ($exe)"
    $src = New-Source 'src'

    Write-Host 'Fresh project'
    $t = New-Target 'Fresh'
    Check ((Invoke-Sync $src $t) -eq 0) 'exit code 0'
    $claude = [IO.File]::ReadAllText("$t\CLAUDE.md")
    Check ($claude.StartsWith("# Fresh`n")) 'CLAUDE.md title is the folder name'
    Check ($claude.Contains('@.claude/workwithcc/CLAUDE.md') -and $claude.Contains('@Docs/Decisions.md')) 'CLAUDE.md has both @ imports'
    Check (-not $claude.Contains('WorkWithCC')) 'CLAUDE.md has no sync header'
    Check (Test-Path "$t\Docs\Decisions.md") 'Docs/Decisions.md created'
    Check (Test-Path "$t\.claude\workwithcc\CLAUDE.md") 'shared CLAUDE.md synced'
    Check (Test-Path "$t\.claude\skills\demo\notes.txt") 'non-md skill file synced'
    $manifest = [IO.File]::ReadAllLines("$t\.claude\workwithcc\manifest.txt")
    Check ($manifest -contains '.claude/skills/demo/SKILL.md' -and $manifest -contains '.claude/workwithcc/CLAUDE.md') 'manifest lists synced files'
    Check (-not ($manifest -contains 'CLAUDE.md' -or $manifest -contains 'Docs/Decisions.md')) 'manifest excludes template files'
    Check ([IO.File]::ReadAllText("$t\.claude\skills\demo\notes.txt") -eq "plain file`n") 'non-md file copied unchanged'

    Write-Host 'SKILL.md frontmatter and encoding'
    $bytes = [IO.File]::ReadAllBytes("$t\.claude\skills\demo\SKILL.md")
    Check (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'no BOM'
    $lines = [IO.File]::ReadAllLines("$t\.claude\skills\demo\SKILL.md")
    Check ($lines[0] -eq '---') 'frontmatter on line 1'
    Check ($lines[3] -eq '---' -and $lines[4].Contains('WorkWithCC')) 'header right after frontmatter'
    $shared = [IO.File]::ReadAllLines("$t\.claude\workwithcc\CLAUDE.md")
    Check ($shared[0].Contains('WorkWithCC')) 'header on line 1 without frontmatter'
    $anyBom = Get-ChildItem $t -Recurse -File -Force | Where-Object { $_.FullName -notlike "$t\.git\*" } | Where-Object {
        $b = [IO.File]::ReadAllBytes($_.FullName); $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF }
    Check (-not $anyBom) 'no written file has a BOM'

    Write-Host 'Second sync'
    Write-Text "$t\CLAUDE.md" "# Fresh`n`nedited by hand`n"
    $before = Get-Snapshot $t
    Check ((Invoke-Sync $src $t) -eq 0) 'exit code 0'
    Check (Same-Snapshot $before (Get-Snapshot $t)) 'no changes, hand-edited CLAUDE.md kept'

    Write-Host 'Existing CLAUDE.md without manifest'
    $t = New-Target 'HasClaude'
    Write-Text "$t\CLAUDE.md" "# Mine`n"
    $before = Get-Snapshot $t
    Check ((Invoke-Sync $src $t) -ne 0) 'non-zero exit code'
    Check (Same-Snapshot $before (Get-Snapshot $t)) 'no file created or changed'
    Check (-not (Test-Path "$t\.claude")) '.claude/ not created'
    Check (-not (Test-Path "$t\Docs")) 'Docs/ not created'

    Write-Host 'Fresh project with existing Docs/Decisions.md'
    $t = New-Target 'HasDecisions'
    Write-Text "$t\Docs\Decisions.md" "# Existing decisions`n"
    Check ((Invoke-Sync $src $t) -eq 0) 'exit code 0'
    Check ([IO.File]::ReadAllText("$t\Docs\Decisions.md") -eq "# Existing decisions`n") 'Docs/Decisions.md unchanged'
    Check (Test-Path "$t\CLAUDE.md") 'CLAUDE.md created'

    Write-Host 'Deletion'
    $t = New-Target 'Delete'
    Check ((Invoke-Sync $src $t) -eq 0) 'first sync'
    Write-Text "$t\.claude\skills\mine\SKILL.md" "---`nname: mine`n---`n"
    Remove-Item "$src\shared\skills\gone" -Recurse -Force
    Check ((Invoke-Sync $src $t) -eq 0) 'second sync'
    Check (-not (Test-Path "$t\.claude\skills\gone")) 'removed skill deleted, folder too'
    Check (Test-Path "$t\.claude\skills\mine\SKILL.md") 'project skill kept'
    Check (Test-Path "$t\.claude\skills\demo\SKILL.md") 'other shared skill kept'
    Check (-not ([IO.File]::ReadAllLines("$t\.claude\workwithcc\manifest.txt") -contains '.claude/skills/gone/SKILL.md')) 'manifest updated'

    Write-Host 'WhatIf and guards'
    $t = New-Target 'WhatIf'
    Check ((Invoke-Sync $src $t @('-WhatIf')) -eq 0) 'WhatIf exit code 0'
    Check ((Get-Snapshot $t).Count -eq 0) 'WhatIf writes nothing'
    $noGit = Join-Path $root 'NoGit'
    [void][IO.Directory]::CreateDirectory($noGit)
    Check ((Invoke-Sync $src $noGit) -ne 0) 'refuses non-git folder'
    [void][IO.Directory]::CreateDirectory("$src\.git")
    Check ((Invoke-Sync $src $src) -ne 0) 'refuses WorkWithCC itself'
}
finally {
    Remove-Item $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:failures) { Write-Host "$($script:failures) failed" -ForegroundColor Red; exit 1 }
Write-Host 'All passed' -ForegroundColor Green
exit 0
