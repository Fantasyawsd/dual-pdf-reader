# P0-2 Debot 修复 + Dot 侧栏 IA v1.1 验收证据

时间（Asia/Shanghai）：2026-11-05 18:49

## 测试

- `./build_and_run.sh --test` → **430 passed, 0 failed**
- `./build_and_run.sh --ui-test` → LegacyUI 66 passed；BugAudit 73 checks, 0 failed

## C1 — promote savePaper 失败回滚

断言（`runPromoteSaveFailureRollbackTest`）：
- `testingPromoteSavePaperResult = false` 后 `promoteToLibrary` 返回 failure
- 临时文档仍在 TransientStore，笔记 `must-survive` 完好
- `LibraryStore.shared.papers.count` 不变；无标题「C1 Fail」孤儿条目
- 实现：`TransientStore.promoteToLibrary` 在 save 失败时 `deletePaper(id: created.id)`

## C2 — reading-state debounce 0.75s + flush

断言（`runReadingStateDebounceFlushTest`）：
- 连续 3 次 `updateReadingState` 后 `readingPersistCountForTests` 未增加
- `flushReadingState()` 恰好 +1 次磁盘写；内存与重载后 disk `lastReadPage == 3`
- `LibraryStore.flushReadingState` 同时调用 `TransientStore.flushReadingState`
- 实现：编码在调用线程完成，atomic write 在 `persistQueue`，`group.wait` 不回主线程（无死锁）

## C3 — 加密解锁 PDFDocument 跨 promote 保留

断言（`runUnlockedDocumentSurvivesPromoteTest`）：
- promote 成功后旧 id 无 unlocked；新 library id 有 unlocked
- 源码证据：`adoptLibraryPaper` → `transferUnlockedDocument`；`.pdf` 变更且 unlocked 存在时跳过 reload
- promote 路径：`deleteTransient(..., clearUnlocked: false)` + re-key `unlockedDocuments`

## Bookmark / 最近不可用

- `resolveBookmark`：缓存命中直接返回；否则先 `stopAccessing` 再 `startAccessing`
- `PaperDTO.isSourceMissing`；打开时 `presentMissingTransientAlert`；中心列表「源文件不可用」标记

## Tab 去重

- `openOrSwitchToPaperTab`：`openReaderTabs[paperId]` 复用同一 VC
- 最近 / 全部文献 中心列表均 `openPaperDual(paperId)` → 同一 bridge → 同一 tab

## Dot 侧栏 IA（P0-spec v1.1）

断言（`runSidebarSourcesOnlyIATest` + Recent）：
- 侧栏只有「来源」：`最近`（时钟图标）+「文献库」下「全部文献」与分类；**无** `recentPreview` / `recent-item` 文件行
- 默认 `filterKind: 'recent'`；`recentPapers` 为空时回退「全部文献」
- `recentCombined(limit: 30)`；临时带「未入库」；右键「存入文献库」「从最近中移除」
- promote 成功后 `libraryVC.refreshAllUI()` → 「未入库」消失并出现在全部文献

## Promote 前后（断言代替截图）

| 阶段 | 证据 |
|------|------|
| before | C1/C3：transient `isTransient` + unlocked under old id；中心列表可渲染「未入库」 |
| after success | C3：unlocked under new id；`adoptPromotedTab` 换绑同一 tab；`refreshAllUI` |
| after failure | C1：transient 保留，library 无孤儿 |

