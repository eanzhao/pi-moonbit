# CLAUDE.md — pi-moonbit

> 给 AI 编程助手的项目指南。AGENTS.md 是精简版。

## 项目简介

pi-moonbit 是 [pi-mono](https://github.com/badlogic/pi-mono)（AI Agent 工具包）的 MoonBit 重写。
`pi-mono/` 目录是原始 TypeScript 代码（只读，不要修改）。

**当前状态**：核心路径（Phase 01-07）已完成，106 个测试全部通过。

## 工具链

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 运行全部测试
moon test lib/ai    # 指定包测试
```

## 目录结构

```
pi-moonbit/
├── docs/               # 架构文档（编号，每阶段一篇）
├── lib/
│   ├── ai/             # Phase 01 — LLM Provider 抽象层
│   ├── tui/            # Phase 02 — 终端 UI 库
│   ├── agent/          # Phase 03 — Agent 引擎
│   ├── coding_agent/   # Phase 04 — 编码助手核心
│   ├── web_ui/         # Phase 06 — Web UI 支撑层
│   ├── mom/            # Phase 07 — Mom 支撑层
│   └── pods/           # (待开发) GPU Pod 管理
├── src/main/           # Phase 05 — CLI 入口（JS target 可运行）
└── pi-mono/            # 原始 TypeScript（只读）
```

## 已完成的 Phase

| Phase | 包 | 核心内容 |
|-------|-----|---------|
| 01 | `lib/ai` | Message/ContentBlock/StopReason enum, Model, Provider 注册, stream/complete |
| 02 | `lib/tui` | Component trait, 差分渲染, Container/Input/SelectList/Loader 等组件 |
| 03 | `lib/agent` | Agent 回合循环, 工具三阶段执行, 事件系统, steering/follow-up 队列 |
| 04 | `lib/coding_agent` | append-only 会话树, 分支/compaction, 扩展钩子, read/write/edit/bash 工具 |
| 05 | `src/main` | CLI 参数解析, 多 session JSONL 持久化, continue/resume, Print/REPL 模式, JS host FFI |
| 06 | `lib/web_ui` | Web transcript, storage/store, proxy/format, model selector, custom provider 支撑层 |
| 07 | `lib/mom` | 统一 channel 模型, log/context sync, sandbox/event/prompt 抽象, 内存 store |

## MoonBit 编码规范

### 类型选择

- **数据容器**用 `struct`：`StreamOptions`、`Tool`、`Context`
- **可区分类型**用 `enum`（ADT）：`Message`、`StopReason`、`AssistantMessageEvent`
- **行为抽象**用 `trait`（跨包扩展时用 `pub(open) trait`）：`Component`、`Terminal`
- **开放标识符**用单字段 struct：`pub(all) struct ApiId(String)`
- **错误处理**用 `Result[T, E]` 和 `suberror`

### 可见性

- 需要外部构造的 struct/enum 用 `pub(all)`（不是 `pub`，后者只允许读取）
- 内部类型用 `priv struct` 或不加修饰符

### derive 注意事项

- 当前使用 `derive(Show)` —— 有弃用警告，但 `Json` 类型不支持 `derive(Debug)`，暂无法迁移
- Session 类型需要 `derive(Eq, ToJson, FromJson)` 支持 JSONL 持久化

### 命名

- 包名：`snake_case`（如 `coding_agent`）
- 类型/Enum：`PascalCase`（如 `Message`、`StopReason`）
- 函数/方法：`snake_case`（如 `calculate_cost`）
- 常量：`snake_case`（如 `api_anthropic_messages`）
- 测试：`test "描述性文字"` 块

### 包配置

- 包配置文件是 `moon.pkg`（自定义 DSL 格式，不是 JSON）
- 依赖声明示例：`import { "eanzhao/pi-moonbit/lib/ai" @ai, }`
- 多 target 文件选择通过 `options(targets: { ... })` 配置

## 开发流程

1. **按依赖顺序开发**：ai、tui（并行） → agent → coding_agent → main
2. **每阶段一篇文档 + 一次提交**：`docs/NN-topic.md`
3. **实现前先读 pi-mono 对应源码**
4. **编译目标**：JS（主要，Phase 05 可运行）、Native/WASM（placeholder）
5. **提交格式**：`feat(ai): add Message enum and Provider trait`

## TypeScript → MoonBit 关键映射

| TypeScript | MoonBit | 例子 |
|-----------|---------|------|
| `interface`（纯数据） | `pub(all) struct` | `StreamOptions`、`Context`、`Tool` |
| `interface`（有方法） | `pub(open) trait` | `Component.render()`、`Terminal.present()` |
| 联合类型 `A \| B` | `pub(all) enum` | `Message`、`StopReason`、`AssistantMessageEvent` |
| `string & {}` | 单字段 struct `struct ApiId(String)` | `ApiId`、`ProviderId` |
| 声明合并 | 注册表模式 | `register_provider()` |
| `async/await` | 回调 | `EventHandler` 包装回调函数 |
| `AsyncIterable` | 回调推送 | `stream()` 通过 handler 推送事件 |
| JSON 原生 | 内置 `Json` 枚举 | 在 builtin 中，无需导入 |
| npm workspaces | MoonBit 单模块多包 | `moon.mod.json` + 各包 `moon.pkg` |

## 架构要点

### lib/ai — Provider 注册表

函数式注册（非 trait）：`register_provider(api_id, stream_fn)`。
`stream()` 按 model.api 查找已注册函数并委托。`complete()` 基于 `stream()` 收集终止事件。

### lib/agent — 双层 API

- 低层 `run_agent_loop()` — 纯函数式，接收 context/config/emit 回调
- 高层 `Agent` — 有状态包装，管理 transcript/listener/queue

### lib/coding_agent — Session 树

- `SessionManager` 维护 append-only entry 数组 + leaf_id（当前分支叶节点）
- `build_transcript_messages()` 只返回标准消息（给 UI）
- `build_session_context()` 返回完整上下文（给 LLM，含 compaction/branch summary）
- `AgentSession.bind_agent()` 通过 `set_transform_context` 注入 session context

### src/main — 多 target 架构

- `host_js.mbt` — 完整 Node.js FFI 实现（fs/child_process/stdin）
- `host_native.mbt` / `host_wasm.mbt` — placeholder，返回明确错误
- `session_store.mbt` — JSONL 格式持久化（header 行 + entry 行）
