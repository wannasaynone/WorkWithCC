# 架構決策

每條決策一個條目，編號依序遞增，格式：

```markdown
## #N 標題

- 規則：要遵守什麼。
- 理由：為什麼這樣決定。
- 重新檢討時機（選填）：什麼情況出現時要重新評估。
- 日期：YYYY-MM-DD
```

推翻決策時不刪除舊條目：在舊條目標題後標註「（已被 #N 取代）」，再另起新條目 #N 寫新決策。

## #1 共用工作流以複製同步發佈

- 規則：共用的規則與 skill 只在 WorkWithCC 的 `shared/` 編輯，由 `sync.ps1` 複製進目標專案的 `.claude/`，由使用者在目標專案 commit。
- 理由：任何人 clone 專案就能套用，不需安裝。git submodule 的內容無法放在 repo 根目錄、其中的 `.claude/skills` 不會被載入；plugin 需要每個人手動安裝且不支援 CLAUDE.md；`~/.claude` 只對一個人、一台電腦有效。
- 重新檢討時機（選填）：Claude Code 能從 submodule 或 plugin 自動載入 CLAUDE.md 與 skill 時。
- 日期：2026-10-25

## #2 同步檔案的歸屬由 manifest 決定

- 規則：`<target>/.claude/workwithcc/manifest.txt` 列出從 `shared/` 同步寫入的所有檔案；同步只會更新或刪除 manifest 裡的檔案。範本建立的 `CLAUDE.md`、`Docs/Decisions.md` 歸專案所有，不進 manifest。manifest 不存在即視為第一次套用。
- 理由：專案自己的 skill 和設定與同步內容放在同一個 `.claude/` 底下，需要明確的清單才能安全刪除過時檔案。
- 日期：2026-10-25

## #3 hook 暫不同步

- 規則：`sync.ps1` 不處理 hook 與 `.claude/settings.json`。
- 理由：hook 設定在 `.claude/settings.json`，必須和專案自己的設定合併，沒有實際需求前不設計。
- 重新檢討時機（選填）：出現第一個要共用的 hook 時。
- 日期：2026-10-25
