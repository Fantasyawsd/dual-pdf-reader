# DualPDFReader

原生 macOS 双栏文献阅读器，使用 AppKit、PDFKit 和 WKWebView，无第三方运行时依赖。

## 构建和验证

需要 macOS 和 Apple Command Line Tools。编译目标为当前机器架构、macOS 12.0；旧系统运行兼容性仍需在对应系统验证。

```sh
./build_and_run.sh --build   # 优化编译、复制网页资源、签名，生成 DualPDFReader.app
./build_and_run.sh --test    # 使用临时目录运行回归测试
./build_and_run.sh --run     # 构建后启动 app
```

`--debug`、`--logs`、`--verify` 提供调试、日志和启动检查。默认执行 `--build`，不会自动打开应用。Codex 的 Run 按钮使用 `--run`。

原有窗口和 WebView 集成测试保留在 `Tests/LegacyUITests.swift`；`./build_and_run.sh --ui-test` 还会运行 `Tests/BugAudit/run.sh`，覆盖单双栏切换、缩放、真实分隔线拖动、侧栏折叠、阅读状态恢复及搜索生命周期。两组测试均使用临时文献库。普通构建和回归测试不执行集成测试。

标题栏标签支持任意拖拽排序（包括文库标签）；拖到横向边缘时自动滚动，便于在大量标签间快速换位。

## 模块边界

| 模块 | 职责 |
| --- | --- |
| `AppDelegate` / `MainWindowController` / `TabBarViews` | 应用生命周期、菜单、延迟加载标签页和窗口控件 |
| `LibraryStore` | 主线程上的文献状态、ID 索引、提交结果和变更通知 |
| `LibraryFileStorage` | 原子 JSON 写入、PDF 暂存与失败回滚、独立附件路径 |
| `PDFMetadataExtractor` / `PDFSummaryCache` | 元数据识别、后台缩略图、缓存失效 |
| `LibraryViewController` / `LibraryWorkspacePage` | 文献库桥接、页面状态与资源组装 |
| `ReaderTabViewController` / `PDFReaderViews` | 阅读交互和原生 PDF 控件 |
| `PDFViewportCoordinator` | 布局事务、延迟任务失效、各栏阅读锚点和文档对校准 |
| `PDFViewportLayout` | 按实际栏宽计算缩放、处理旋转和裁切框、统一页面水平居中 |
| `ReaderLayoutViews` | 根视图与两级分隔线的几何变化通知及尺寸约束 |
| `ColumnToolbarViews` | 左右栏独立工具栏、阅读/批注/形状选项卡、调色盘与底部页码胶囊 |
| `PDFScrollSynchronizer` | 连续页坐标、双栏同步、阅读位置恢复 |
| `PDFAnnotationService` | 跨页选区转换与增量高亮更新 |
| `PDFSearchController` | 可取消的 PDFKit 异步搜索 |
| `NoteEditorSheetController` / `MarkdownMathRenderer` | 笔记编辑、Markdown 和部分 LaTeX 语法渲染 |
| `MarkdownNotesExporter` | 单向导出 `notes.md` |
| `LibraryStore+Samples` / `SamplePaperPDFBuilder` | 示例文献及 PDF 生成 |

文献库页面和笔记渲染的 JavaScript、CSS、HTML 位于 `Resources/`，构建时复制进 app。Swift 源码不再内嵌整份文献库网页。

## 数据与保存约定

每篇论文独立保存到 `<文献库>/<paper-id>/`，包含 `meta.json`、原文/译文 PDF、`notes.md` 和 `attachments/`。已有 JSON 可以直接读取；新增的阅读位置和跨页批注字段均为可选。

- `meta.json` 是应用内笔记的来源；`notes.md` 供外部查看，外部编辑不会反向导入。阅读进度变化不会重写 `notes.md`。
- 常规修改在元数据写入成功后发布到内存和界面。PDF 替换先验证并暂存新文件，元数据提交失败时恢复旧 PDF。
- 同名附件放入独立目录；相关论文的双向元数据在单次操作失败时回滚。删除论文移至 Finder 废纸篓。
- 阅读滚动在 400 毫秒内合并保存；切换标签页、关闭标签页及退出应用前立即提交。强制终止进程可能丢失最近尚未提交的阅读位置。
- 每栏分别保存当前 PDF、阅读位置、缩放模式和倍率；阅读模式、同步开关、互换和用户分栏比例也随论文保存。旧元数据可继续读取。布局变化会暂时隔离同步通知，完成后恢复各栏位置；隐藏栏不会覆盖阅读进度。
- 拖动分隔线、开关侧栏、缩放及空白点击保持各栏自己的阅读锚点；布局恢复不额外触发双栏对齐。页尾受尺寸限制时保留期望锚点，恢复空间后还原。同步由滚动、导航和开启同步发起。
- 每次打开阅读器、显示隐藏栏或改变栏宽，PDF 都按该栏可用宽度重新适配并水平居中；拖动过程中实时更新。右侧栏打开时压缩整个 PDF 画布，保留两栏的比例，分隔线允许在 5%–95% 之间调整。
- 两栏的手动缩放独立于滚动同步，始终保持页面水平居中。按钮、右键菜单和触控板只缩放操作的那一栏；快捷键只缩放当前活动栏。开启同步保留各栏自己的倍率和适配模式。后续拖动分隔线、开关侧栏或切换单双栏会重新适配宽度。
- 对齐校准按两栏实际 PDF ID 成对保存；切换附加 PDF 后使用该文档对的偏移。同一阅读会话中，各栏切换过的 PDF 分别保留位置和缩放。
- 新增功能应通过 `LibraryChange` 标记受影响论文和字段，避免触发所有阅读器的全量刷新。

首次启动优先使用已选择的文献库，再查找 app 或工作目录旁已有的 `PaperLibrary`，最后使用文稿目录下的 `DualPDF_PaperLibrary`。代码不包含个人开发目录。

## 性能策略

封面仅为可见条目、邻近条目和当前选中论文请求，后台最多并行处理两个 PDF，缩略图缓存上限为 256 项、24 MiB。读取已有摘要不会触发隐藏条目的封面任务。

阅读标签页在激活时加载 PDF。高亮按批注 ID 比较，仅更新修改或删除的对象。笔记与关联抽屉在打开后刷新；搜索输入延迟 200 毫秒启动，并取消之前的查询。

测试覆盖文件失败回滚、同名附件、旧元数据兼容、阅读进度合并、跨页批注、异步搜索取消、资源释放、Markdown 代码块保护和元数据延迟保存。测试使用生成的 PDF 和临时文献库，不修改个人文献。

`Tests/ReaderCoreTests.swift` 覆盖布局事务、快速连续操作、加载期间导航、后台标签隔离、页尾钳制和文档对校准；`Tests/PDFWidthLayoutTests.swift` 直接测量渲染页面的宽度和中心，覆盖实时拖拽、极窄栏、横版、旋转、裁切框和侧栏压缩。真实鼠标拖拽及空白点击回归位于 `Tests/BugAudit/main.swift`。当前布局行为与验证记录见 [PDF_WIDTH_LAYOUT.md](docs/PDF_WIDTH_LAYOUT.md)，前一轮事务重构记录见 [PDF_VIEWPORT_REFACTOR.md](docs/PDF_VIEWPORT_REFACTOR.md)。

两栏独立缩放的后续修正和验证记录见 [INDEPENDENT_COLUMN_ZOOM.md](docs/INDEPENDENT_COLUMN_ZOOM.md)。栏内工具栏、页码胶囊与鼠标所在栏 ⌘+滚轮缩放的实现记录见 [READER_COLUMN_TOOLBARS.md](docs/READER_COLUMN_TOOLBARS.md)。
