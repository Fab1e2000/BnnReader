# BnnReader 改进与性能优化方案

本文档梳理当前代码库可改进的方向，并给出本次将要实施的具体改动思路。改动遵循“最小侵入、不破坏现有 UX”原则。最低系统目标提升至 **macOS 26**，可放心使用新 API。

## 1. 现状速览

- 入口：`Banana_ReaderApp` + `AppDelegate`，`WindowGroup` 承载 `ContentView`。
- 阅读器：`ContentView` -> `ReaderCardView` -> `MarkdownWebView`(WKWebView) / `PDFReaderView`(PDFView)。
- 数据：`ReaderViewModel`（`@MainActor`）负责打开文件、加载内容、转换 HTML。
- Markdown 转 HTML：`MarkdownHTMLRenderer`，自实现的轻量 Markdown 解析器。

## 2. 已识别的问题

### 2.1 性能相关

1. **Markdown -> HTML 渲染发生在主线程**  
   `ReaderViewModel.applyLoadedContent(_:fileName:)` 中调用 `MarkdownHTMLRenderer.renderDocument`，对几 MB 的文档会明显卡顿（IO 已经异步，但渲染没有）。
2. **`escapeHTML` 4 次全文 `replacingOccurrences`**  
   每段 inline 文本至少 4 遍 O(n) 扫描；改为单遍扫描可显著减少分配与遍历次数。
3. **每次切换文档都重复传输完整 CSS**  
   `renderDocument` 的字符串模板每次都要重新拼接整个 `<style>...</style>`（数百行），且会被 `loadHTMLString` 拷贝到 WebView。可将 CSS / shell 模板提为 `static let` 常量，渲染时只注入 `<main>` 内容。
4. **`parseUnorderedListItem` 使用 `line.count`**  
   `String.count` 是 O(n)。对长行（接近 8 MB 单行的极端场景）多余；改用 `prefix(2)` / `count >= 3` 之外不要触发全量计数即可。其实只需要看前缀，可直接判断是否以 `"- "/"* "/"+ "` 开头。
5. **`renderInline` 中 inline code 内部仍会被加粗 / 斜体 / 链接正则破坏**  
   例如 \`\`\`**foo**\`\`\` 会被改成 `<code><strong>foo</strong></code>`。这是 correctness 问题，但在大文档中也会让 regex 多匹配很多无效片段，浪费 CPU。修复办法：先把 inline code 用占位符抽出，等其它 inline 替换做完再回填。

### 2.2 代码质量 / 工程

6. **缩放范围 `0.7~2.2` 在 ContentView 与 PDFReaderView 各写一份**  
   抽到一个共享常量，避免漂移。
7. **缺少 GB18030 / GBK 编码 fallback**  
   `loadString` 仅尝试 UTF-8 / UTF-16 / ASCII；中文 ANSI 文本会失败。
8. **`MarkdownHTMLRenderer` 的正则用 `try?` 静默失败**  
   pattern 是写死字面量，可以 `try!` 让真出错时尽早暴露；同时无需 `Optional` 解包。
9. **`renderDocument` 未在 init 时复用**  
   `ReaderViewModel.renderedHTML` 默认值在每个 `ReaderViewModel` 实例创建时都会跑一次完整渲染——可改成静态 lazy 常量复用。

### 2.3 留意但本次不动

- WKWebView 的 `WKProcessPool` 共享、`baseURL` + 资源化 CSS，可把首屏更快；但需要打包资源、调整 sandbox baseURL，改动相对大，留待后续。
- 引入正式 Markdown 库（如 `swift-markdown` / `Down`）一劳永逸，但会引入依赖、影响包大小，跟“轻量阅读器”定位不完全一致；本次保持自实现并优化。
- AppDelegate 用全局通知 + static `pendingOpenURLs` 路由打开请求，目前已有“仅空白窗口消费”的修补（见 repo memory）。结构性重构（注入 router）留待后续。

## 3. 本次改动计划

| # | 文件 | 改动 |
|---|---|---|
| C1 | `ReaderViewModel.swift` | 把 `MarkdownHTMLRenderer.renderDocument` 调用搬到后台线程；增加 GB18030 编码 fallback；初始 `renderedHTML` 改为复用静态常量。 |
| C2 | `MarkdownHTMLRenderer.swift` | (a) `escapeHTML` 改为单遍扫描；(b) inline code 占位符化保护内部内容；(c) 正则改为 `try!` 非可选；(d) HTML 模板拆成 `htmlPrefix` / `htmlSuffix` 静态常量；(e) `parseUnorderedListItem` 去掉 `line.count`。 |
| C3 | `ContentView.swift` + `PDFReaderView.swift` | 抽出 `ZoomConstants`（min 0.7、max 2.2、step 0.1），消除重复字面量。 |
| C4 | `Package.swift` / `ReaderViewModel.swift` / `ContentView.swift` | 平台升至 macOS 26、Swift tools 6.0；`ReaderViewModel` 改用 `@Observable`；`onChange` 用新双参签名；`renderInline` 中字符串处理使用 `String.replacing(_:with:)` 等 Swift 6 API（保持行为一致）。 |

每条改动都不改变对外行为（除 inline code 保护属于 bug fix，会让结果更正确），不引入新依赖，仍以 `swift build` 验证通过为完成标志。

## 4. 验证

- `swift build` 成功，无新警告。
- 手动核对：
  - 打开一份普通 Markdown，渲染外观与改动前一致。
  - 含内联代码 \`\`\`**not bold**\`\`\` 的段落：内部不再被加粗。
  - PDF 文件、缩放按钮、Pinch 手势仍工作。
