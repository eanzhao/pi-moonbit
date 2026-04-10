# 00 - 项目总览：pi-moonbit

## 目标

用 MoonBit 重新实现 [pi-mono](https://github.com/badlogic/pi-mono)（一个 AI 编程智能体工具包），
达到两个目的：

1. **学习 MoonBit** — 通过实战掌握 MoonBit 的类型系统、trait、泛型、错误处理、FFI 等核心特性。
2. **理解 pi-mono 架构** — 逐包拆解并重建，深入理解 AI Agent 从底层 LLM API 到上层交互界面的全栈设计。

## pi-mono 是什么

pi-mono 是 Mario Zechner（libGDX 作者）开源的 AI 智能体工具包，TypeScript 实现，
采用「反框架」理念——提供可组合的原语而非全家桶。核心特点：

- 统一的多 Provider LLM API（Anthropic / OpenAI / Google / Mistral / Azure / Bedrock 等 13+）
- 最小化的 Agent 循环引擎（5 个源文件）
- 强大的扩展 API（自定义工具、UI 组件、子智能体）
- 内置编码工具（read / write / edit / bash / grep / find / ls）
- 终端 UI 库（差分渲染）和 Web UI 组件库

## 原始架构：7 个包

| 包名 | npm 名 | 职责 |
|------|--------|------|
| `ai` | `@mariozechner/pi-ai` | 统一多 Provider LLM API，流式响应，模型发现 |
| `agent` | `@mariozechner/pi-agent-core` | Agent 循环引擎，工具调用，状态管理 |
| `coding-agent` | `@mariozechner/pi-coding-agent` | 编码智能体 CLI，内置工具，会话管理，扩展系统 |
| `tui` | `@mariozechner/pi-tui` | 终端 UI 库，差分渲染，组件系统 |
| `web-ui` | `@mariozechner/pi-web-ui` | Web 聊天组件库 |
| `mom` | `@mariozechner/pi-mom` | Slack 机器人，消息委派给编码智能体 |
| `pods` | `@mariozechner/pi` | GPU Pod 管理 CLI，vLLM 部署 |

### 依赖关系（根据 package.json 实际声明）

```
叶子包（无内部依赖）:
  ai
  tui

中间层:
  agent        → ai
  pods         → agent
  web-ui       → ai, tui

上层:
  coding-agent → ai, agent, tui
  mom          → ai, agent, coding-agent
```

完整依赖图（箭头表示"被依赖"方向）：

```
ai ──→ agent ──→ coding-agent ──→ mom
│        │            ↑
│        └──→ pods    │
│                     │
└──→ web-ui           │
       ↑              │
tui ───┴──────────────┘
```

读法：`ai → agent` 表示 agent 依赖 ai。
- ai, tui：无内部依赖（叶子）
- agent：依赖 ai
- pods：依赖 agent
- web-ui：依赖 ai, tui
- coding-agent：依赖 ai, agent, tui
- mom：依赖 ai, agent, coding-agent

## MoonBit 重新实现方案

### 模块映射

```
eanzhao/pi-moonbit
├── lib/
│   ├── ai/              ← pi-ai: LLM Provider 抽象层
│   ├── agent/           ← pi-agent-core: Agent 循环引擎
│   ├── coding_agent/    ← pi-coding-agent: 编码智能体核心
│   ├── tui/             ← pi-tui: 终端 UI 库
│   ├── web_ui/          ← pi-web-ui: Web UI 组件
│   ├── mom/             ← pi-mom: Slack 集成
│   └── pods/            ← pi (@mariozechner/pi): GPU Pod 管理
└── src/
    └── main/            ← CLI 入口
```

### 实现顺序

按照依赖关系从底向上（`ai` 和 `tui` 是两个独立的叶子包，可并行）：

| 阶段 | 包 | 要点 |
|------|-----|------|
| 01 | `lib/ai` | 消息类型、模型定义、Provider trait、流式 API |
| 02 | `lib/tui` | 终端抽象、组件 trait、差分渲染（与 ai 无依赖，可并行） |
| 03 | `lib/agent` | Agent 循环、工具类型、事件系统（依赖 ai） |
| 04 | `lib/coding_agent` | 内置工具、会话管理、扩展 API（依赖 ai + agent + tui） |
| 05 | `src/main` | CLI 入口，串联所有模块 |
| 06 | `lib/web_ui` | Web UI 组件（依赖 ai + tui，WASM 后端） |
| 07 | `lib/pods` | GPU Pod 管理（依赖 agent） |
| 08 | `lib/mom` | Slack 集成（依赖 ai + agent + coding_agent） |

### 关键设计决策

| 维度 | TypeScript (pi-mono) | MoonBit (pi-moonbit) |
|------|----------------------|----------------------|
| 数据型接口 | `interface` (纯数据) | `struct` |
| 行为型接口 | `interface` (方法签名) | `trait` (需跨包扩展时用 `pub(open) trait`) |
| 封闭联合类型 | 联合类型 `A \| B \| C` | `enum` (ADT) |
| 开放联合类型 | `string & {}` / 声明合并 | `String` 包装 或 注册表模式（见下方说明） |
| 泛型 | 泛型参数 + 条件类型 | 泛型参数 + Trait 约束 |
| 错误处理 | try/catch + Result | `Result[T, E]` + `!` 语法 |
| 异步 | async/await + AsyncIterable | `async fn` (实验性，Native 优先) |
| 序列化 | JSON 原生 | `@json` 库 |
| 扩展机制 | 动态导入 + 声明合并 | 注册表 + Trait 对象（见下方说明） |
| 编译目标 | Node.js / 浏览器 | Native (主要) / WASM (web_ui) |
| 包管理 | npm workspaces | MoonBit 单模块多包 |
| 包配置文件 | package.json | `moon.pkg` (非 JSON 格式) |

### TypeScript → MoonBit 映射详解

**数据型 vs 行为型接口**

pi-mono 中大部分 `interface` 是纯数据形状（如 `StreamOptions`, `Tool`, `Context`,
`ThinkingBudgets`），应映射为 MoonBit `struct`。只有需要多态行为的接口（如 `ApiProvider`
的 `stream()` 方法、TUI 的 `Component.render()`）才映射为 `trait`。

```
// 数据型 → struct
struct StreamOptions {
  temperature : Double?
  max_tokens : Int?
  stop : Array[String]?
}

// 行为型 → trait
pub(open) trait Provider {
  stream(Self, Model, Context, StreamOptions) -> EventStream[AssistantMessageEvent]!
}
```

**封闭 vs 开放联合**

封闭联合（如 `Message`, `AssistantMessageEvent`, `StopReason`）直接用 `enum`：

```
enum Message {
  User(UserMessage)
  Assistant(AssistantMessage)
  ToolResult(ToolResultMessage)
}
```

开放联合（如 `Api` 和 `Provider` 类型允许任意字符串扩展）不能用封闭 `enum`，
需要用 `String` 包装类型 + 注册表模式：

```
type ApiId String  // 允许任意值
type ProviderId String
```

**异步与事件流**

pi-mono 的核心流式 API 基于 `AsyncIterable<AssistantMessageEvent>`。
MoonBit 的 `async fn` 目前在 Native 后端支持较好，WASM 支持有限。
因此本项目采用 **Native 优先**策略：

- 核心包（ai, agent, coding_agent）以 Native 为主要编译目标
- web_ui 包单独走 WASM + 浏览器 FFI 路线
- 事件流用回调模式或 `Iter` 作为保底方案，待 async 成熟后迁移

### 扩展机制设计

pi-mono 的扩展系统是其核心特性之一，涉及三个层面：

1. **声明合并**（`CustomAgentMessages`）— TypeScript 特有，允许第三方扩展消息类型。
   MoonBit 没有声明合并，需要用 **注册表模式**：维护一个 `Map[String, (Bytes) -> AgentMessage!]`
   反序列化表，扩展在初始化时注册自定义消息类型。

2. **动态加载**（`extensions/loader.ts`）— TypeScript 通过 `import()` 动态加载扩展模块。
   MoonBit Native 不支持动态链接，可选方案：
   - 编译期注册：扩展作为 MoonBit 包，编译时静态链接
   - WASM 插件：扩展编译为 WASM 模块，宿主通过 WASM runtime 加载

3. **生命周期钩子**（`Extension` 接口）— 直接映射为 `trait Extension`，
   包含 `on_start`, `on_before_tool_call`, `on_after_tool_call` 等方法。

```
pub(open) trait Extension {
  name(Self) -> String
  on_start(Self, ExtensionContext) -> Unit!
  on_before_tool_call(Self, BeforeToolCallContext) -> BeforeToolCallResult?
  on_after_tool_call(Self, AfterToolCallContext) -> AfterToolCallResult?
  // ...
}
```

> 注意：扩展机制是最复杂的映射点，具体方案将在 04 号文档中详细展开。

## 文档计划

每个实现阶段对应一篇文档：

| 编号 | 主题 |
|------|------|
| 00 | 项目总览（本文） |
| 01 | LLM API 层：消息、模型、Provider |
| 02 | 终端 UI：组件、渲染、键盘（与 01 无依赖，可并行） |
| 03 | Agent 引擎：循环、工具、事件（依赖 01） |
| 04 | 编码智能体：工具、会话、扩展（依赖 01 + 02 + 03） |
| 05 | CLI 入口与集成 |
| 06+ | Web UI / Pods / Slack |

每篇文档包含：
- 对应 pi-mono 包的架构分析
- MoonBit 实现的设计决策
- 关键类型和接口定义
- 与 TypeScript 版的对照
