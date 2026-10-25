# WorkWithCC

各專案共用的 Claude Code 規則與 skill。內容由 `sync.ps1` 複製進專案的 `.claude/`，同步後的檔案會 commit 在專案裡，所以任何人 clone 專案就自動套用，不需要安裝或設定。

## 套用到一個專案

目標必須是 git repo 的根目錄。先用 `-WhatIf` 預覽：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\path\to\WorkWithCC\sync.ps1 -Target C:\path\to\MyProject -WhatIf
```

也可以把專案資料夾拖到 `sync-preview.bat`（預覽）或 `sync.bat`（直接同步）上，或雙擊後輸入路徑。

確認後拿掉 `-WhatIf` 執行，再到專案裡檢查變更並 commit。Windows PowerShell 5.1（`powershell`）和 PowerShell 7（`pwsh`）都能執行；腳本不會執行任何 git 指令。

第一次套用時：

- 建立 `CLAUDE.md`（標題是資料夾名稱，並匯入共用規則和 `Docs/Decisions.md`），下方「專案專屬規則」段落自行填寫。
- `Docs/Decisions.md` 不存在時用範本建立，已存在就不動。
- 這兩個檔案建立後就屬於專案，之後的同步不會再修改或刪除。

**專案已經有 `CLAUDE.md`**：第一次同步會在寫入任何檔案前取消，避免覆蓋專案內容。做法是先把 `CLAUDE.md` 暫時移走、執行同步，再用原本的檔案取代範本建立的那份，並在其中加入：

```markdown
@.claude/workwithcc/CLAUDE.md
@Docs/Decisions.md
```

之後的同步不會再檢查 `CLAUDE.md`。

## 更新

在 WorkWithCC 拉下最新版，對專案再執行一次同樣的指令，然後在專案 commit。

## 同步規則

| 來源 | 目標 |
| --- | --- |
| `shared/CLAUDE.md` | `.claude/workwithcc/CLAUDE.md` |
| `shared/skills/<name>/` | `.claude/skills/<name>/` |

- 同步寫入的檔案記錄在 `.claude/workwithcc/manifest.txt`。來源刪掉的檔案，下次同步時也會從專案刪除；不在 manifest 裡的檔案（專案自己的 skill 等）不會被動到。
- 同步來的 `.md` 檔會加一行註解「由 WorkWithCC 同步，修改請到 WorkWithCC」（有 YAML frontmatter 的放在 frontmatter 之後）。要修改請改 WorkWithCC 的 `shared/`，在專案裡改的內容會在下次同步被蓋掉。
- 檔案一律以 UTF-8 無 BOM 寫出。
- 同一份來源重複執行不會產生差異。

## 新增共用 skill

在 `shared/skills/<name>/SKILL.md` 建立 skill，再對各專案執行同步。

## 尚未支援：hook

hook 設定在 `.claude/settings.json`，同步時必須和專案自己的設定合併，這一版還不處理。等第一個要共用的 hook 出現時再設計。

## 測試

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\sync.tests.ps1
pwsh -NoProfile -File tests\sync.tests.ps1
```
