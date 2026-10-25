# WorkWithCC

這個 repo 是各專案共用的 Claude Code 規則與 skill 的唯一編輯來源，由 `sync.ps1` 複製進各專案。

## 結構

- `shared/`：發佈到各專案的內容。`shared/CLAUDE.md` → `<target>/.claude/workwithcc/CLAUDE.md`；`shared/skills/<name>/` → `<target>/.claude/skills/<name>/`。
- `templates/`：第一次套用時建立專案的 `CLAUDE.md` 和 `Docs/Decisions.md`，建立後歸專案所有。
- `sync.ps1`、`tests/sync.tests.ps1`：同步腳本和它的測試。

## 規則

- 要發佈的規則和 skill 改在 `shared/`；本檔、`Docs/` 和 `.claude/` 只作用於 WorkWithCC 自己。
- 改了 `sync.ps1` 後，在 `powershell`（5.1）和 `pwsh`（7）各跑一次 `tests/sync.tests.ps1`。
- 文件用繁體中文，程式碼註解用英文。

@shared/CLAUDE.md
@Docs/Decisions.md
