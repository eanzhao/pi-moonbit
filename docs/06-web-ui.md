# 06 - Web UI 支撑层：lib/web_ui

## 这一阶段做了什么？

phase 06 没有直接去硬写浏览器组件树，而是把 `pi-web-ui` 里最稳定、最可复用、也最适合 MoonBit 迁移的部分抽成一个新的 `lib/web_ui` 包：

- 定义 Web Chat 侧的扩展消息类型
- 定义附件与 artifact 的持久化 shape
- 实现默认的 `convert_to_llm` 转换逻辑
- 实现 session metadata / session data / session list 逻辑
- 实现 storage backend 抽象、app storage 与各类 store
- 实现代理设置、usage/cost 格式化、模型筛选与 custom provider 辅助函数
- 实现纯 MoonBit 的组件视图层和 HTML renderer

对应源码：

```text
lib/web_ui/
├── moon.pkg
├── types.mbt
├── messages.mbt
├── session_store.mbt
├── storage.mbt
├── app_storage.mbt
├── settings_store.mbt
├── provider_keys_store.mbt
├── custom_providers_store.mbt
├── sessions_store.mbt
├── proxy.mbt
├── format.mbt
├── html.mbt
├── components.mbt
├── providers.mbt
├── model_selector.mbt
├── html_test.mbt
├── components_test.mbt
├── messages_test.mbt
├── session_store_test.mbt
├── storage_test.mbt
├── stores_test.mbt
├── proxy_test.mbt
├── format_test.mbt
└── providers_test.mbt
```

这意味着仓库里现在已经有了 Web UI 层的一整套“数据、存储、筛选、配置和视图支撑层”，而不再只是 README 里的占位目录。

## 为什么不是先做浏览器组件？

`pi-mono/packages/web-ui` 的表面上最显眼的是：

- `ChatPanel`
- `AgentInterface`
- `MessageList`
- 各种 Lit components / dialogs / sandbox providers

但这些实现强依赖：

- DOM / Custom Elements
- lit / mini-lit
- CSS / Tailwind
- 浏览器存储（IndexedDB）
- sandbox iframe runtime

MoonBit 版如果第一步就照着这些组件写，会立刻卡在平台绑定和渲染层细节里，反而把真正可迁移的核心抽象埋掉。

所以 phase 06 做的是 **UI 下面那层稳定支撑层**：

- Web Chat 需要保存什么消息
- 这些消息怎么映射回 `lib/ai` 的标准消息
- session 元数据怎么生成
- 存储接口和 store API 应该长什么样
- model selector / proxy / provider 管理里哪些逻辑不依赖 DOM
- 哪些组件可以先用纯数据视图树表达，而不是立刻绑定浏览器 API

这是一个刻意的“先数据、后渲染”的顺序。

## 对照 pi-web-ui，先移植了哪些抽象？

### 1. 扩展消息类型

`pi-web-ui` 在 TypeScript 里通过声明合并扩展了 `AgentMessage`，新增了两类消息：

- `user-with-attachments`
- `artifact`

MoonBit 没有声明合并，所以这里改成显式 ADT：

```moonbit
enum ChatMessage {
  Standard(@ai.Message)
  UserWithAttachments(UserMessageWithAttachments)
  Artifact(ArtifactMessage)
}
```

这也是这一阶段最关键的设计点：Web UI 的 transcript 不再假装“所有消息都已经是标准 LLM 消息”。

### 2. 附件模型

这一版先保留 `pi-web-ui` 最核心的附件字段：

- `id`
- `kind`
- `file_name`
- `mime_type`
- `size`
- `content_base64`
- `extracted_text`
- `preview_base64`

并区分：

- `Image`
- `Document`

这样后续不管是接浏览器上传、WASM 文件 API，还是外部 host 注入，都能复用同一份持久化结构。

### 3. 默认 convert_to_llm

`pi-web-ui` 里有一条很关键的逻辑：Web transcript 不是直接发给模型，而是要先做一次过滤和转换。

MoonBit 版目前实现的规则是：

- `Standard(@ai.Message)`：直接透传
- `UserWithAttachments`：转成 `@ai.Message::User`
  - 原始文本保留
  - 图片附件转成 `Image` block
  - 带 `extracted_text` 的文档转成 `Text` block
- `Artifact`：过滤掉，不进入 LLM 上下文

这和 `pi-web-ui` 的默认思路是一致的：artifact 用于 UI / session reconstruction，不是给模型看的。

### 4. SessionData / SessionMetadata

这一层也对齐了 `pi-web-ui` 的两层 session 结构：

- `SessionData`：完整会话内容
- `SessionMetadata`：列表页和搜索用的轻量信息

其中 metadata 目前会自动生成：

- `message_count`
- `usage`
- `preview`
- `thinking_level`

`usage` 通过 transcript 中 assistant 消息的 usage 累加得到，`preview` 则从 user / assistant 文本拼接截断而来。

### 5. StorageBackend / AppStorage / Stores

这一版把 `pi-web-ui/src/storage` 下面那组抽象一并迁了过来，只是把真正的 IndexedDB API 绑定留空：

- `StorageBackend`
- `StorageTransaction`
- `AppStorage`
- `SettingsStore`
- `ProviderKeysStore`
- `CustomProvidersStore`
- `SessionsStore`

同时给了一个完全可测试的 `InMemoryStorageBackend`，所以现在能在 MoonBit 里完整验证：

- 多 store 读写
- cross-store transaction
- session data / metadata 双表同步
- quota / persistence API 入口

也就是说，phase 06 不只是“有个内存 session store”，而是已经把 web storage 层整体搭起来了。

### 6. Proxy / Format / Model Selector 辅助逻辑

`pi-web-ui` 里还有几类逻辑本身不依赖 DOM，但和 Web 使用体验强相关：

- CORS proxy 规则
- usage / token / cost 格式化
- session 列表日期格式
- model selector 的 subsequence 搜索和 capability filter
- custom provider 的模型归一化

这些现在也都进入了 `lib/web_ui`，后面无论是做浏览器 UI、WASM host，还是别的前端壳，都能直接复用。

### 7. 纯 MoonBit 组件与 HTML 视图树

在把 storage 和辅助逻辑补齐之后，这一版继续往上走了一层，但仍然刻意停在“宿主无关”的边界：

- `html.mbt` 提供轻量 `HtmlNode` / `HtmlElement` / `WebComponent`
- `components.mbt` 提供一组纯展示组件，把 Web UI 状态渲染成 HTML 字符串

当前已经覆盖的组件包括：

- `AttachmentTileView`
- `ThinkingBlockView`
- `CustomProviderCardView`
- `MessageListView`
- `SessionListView`
- `ModelSelectorView`

这层不是浏览器里的 custom elements，也不负责事件绑定；它的价值在于先把组件输出 shape 固定下来，让后面接 JS/WASM 宿主时只需要把动作和状态连上。

## 关键设计决策

### 为什么 `lib/web_ui` 依赖 `lib/agent`？

虽然当前实现没有直接移植浏览器组件，但 session metadata 里需要记录：

- `thinking_level`

而这属于 `lib/agent` 的概念，不是 `lib/ai`。因此 `lib/web_ui` 现在的包依赖是合理的：

```text
lib/web_ui -> lib/ai + lib/agent
```

这也和总架构文档里 “web-ui 依赖 ai 和 tui/agent 侧能力” 的方向一致，只是 MoonBit 版目前先落了更靠近数据层的部分。

### 为什么先不用 `@agent.AgentState` 直接做 session？

当前 `lib/agent` 里的 `AgentState.messages` 还是标准 `@ai.Message[]`，并不能直接承载：

- `UserWithAttachments`
- `Artifact`

所以 phase 06 暂时没有强行把 Web transcript 塞进 `AgentState`，而是单独定义了 `ChatMessage`。这能把问题讲清楚：

- Agent runtime 的标准消息
- Web UI 的扩展消息

是两层不同的数据模型，中间需要显式转换。

### 为什么这里做的是组件视图层，不是浏览器 custom elements？

真正难搬的不是消息 shape，而是浏览器宿主绑定：

- DOM / Custom Elements
- lit / mini-lit
- iframe sandbox
- 文件上传 / 文档解析 / 浏览器权限
- IndexedDB / navigator.storage / fetch 等浏览器 API

这些都强依赖浏览器宿主。MoonBit 版 phase 06 现在的取舍是：

- 组件结构和 HTML 输出先固定
- DOM、事件、浏览器 API 继续留在宿主绑定层

这样后面的 Web 壳子只是“接线”，不是“重新发明 session / storage / model filter / proxy / component output 逻辑”。

## 测试覆盖

`lib/web_ui` 当前测试覆盖五条主线：

### messages_test.mbt

- `default_convert_to_llm` 会过滤 artifact
- 附件会被正确映射成 LLM content blocks
- 文本提取会忽略图片与 artifact

### session_store_test.mbt

- title 会从第一条 user-like 消息生成
- session 是否值得持久化有明确判定
- metadata 会自动累积 usage 和 preview
- 内存 store 能保存、排序、重命名、删除 session

### storage / stores / proxy / format / selector tests

- storage backend 支持 prefix / index / transaction
- app storage 与四类 store 共用同一 backend
- custom provider 能归一化模型与 API/base URL
- proxy 规则和 settings 读写可独立验证
- model selector 的搜索、排序、vision/filter 规则可独立验证

### html / components tests

- HTML renderer 会正确 escape 文本和属性
- 组件 trait 可以直接输出 HTML
- attachment / provider card / message list / session list / model selector 都有稳定快照行为

## 当前状态

phase 06 之后，`lib/web_ui` 已经具备：

- Web transcript 的消息模型
- 附件 / artifact 的持久化结构
- 默认 LLM 转换逻辑
- session metadata、preview、usage 聚合
- storage backend 抽象与内存 backend
- app storage 与四类 domain stores
- proxy / format / model filtering / custom provider 辅助逻辑
- 纯 MoonBit 组件和 HTML 视图树

但还没有直接进入 MoonBit 仓库的部分仍然是浏览器宿主相关能力：

- `ChatPanel` / `AgentInterface` 这样的 DOM 组件
- 真实 IndexedDB / `navigator.storage` 绑定
- iframe sandbox / artifacts panel renderer
- 文件上传与文档解析 runtime

也就是说，这一阶段已经把 **Web UI 里可迁移的支撑层和纯视图层做完整了**；缺的不是 session/store/proxy/model/component-output 这些基础设施，而是浏览器端 DOM、事件和宿主 API 绑定。
