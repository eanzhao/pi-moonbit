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
| `pods` | `@mariozechner/pi-pods` | GPU Pod 管理 CLI，vLLM 部署 |

### 依赖关系

```
tui (无内部依赖)
 ↑
ai (无内部依赖)
 ↑
agent → ai
 ↑
coding-agent → agent, ai, tui
 ↑         ↑
mom         web-ui → ai, agent
 ↑
pods → ai, agent
```

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
│   └── pods/            ← pi-pods: GPU Pod 管理
└── src/
    └── main/            ← CLI 入口
```

### 实现顺序

按照依赖关系从底向上：

| 阶段 | 包 | 要点 |
|------|-----|------|
| 01 | `lib/ai` | 消息类型、Provider trait、流式 API |
| 02 | `lib/agent` | Agent 循环、工具类型、事件系统 |
| 03 | `lib/tui` | 终端抽象、组件系统、差分渲染 |
| 04 | `lib/coding_agent` | 内置工具、会话管理、扩展 API |
| 05 | `src/main` | CLI 入口，串联所有模块 |
| 06 | `lib/web_ui` | Web UI 组件（WASM 后端） |
| 07 | `lib/mom` | Slack 集成 |
| 08 | `lib/pods` | GPU Pod 管理 |

### 关键设计决策

| 维度 | TypeScript (pi-mono) | MoonBit (pi-moonbit) |
|------|----------------------|----------------------|
| 类型系统 | 接口 + 联合类型 | Trait + Enum (ADT) |
| 泛型 | 泛型参数 + 条件类型 | 泛型参数 + Trait 约束 |
| 错误处理 | try/catch + Result | `Result[T, E]` + `!` 语法 |
| 异步 | async/await + EventStream | `Async` + `Channel` |
| 序列化 | JSON 原生 | `@json` 库 |
| 扩展机制 | 动态导入 + 声明合并 | Trait 对象 + 动态派发 |
| 编译目标 | Node.js / 浏览器 | WASM / Native |
| 包管理 | npm workspaces | MoonBit 单模块多包 |

### MoonBit 特性对应

- **Provider 系统** → 定义 `Provider` trait，每个 LLM 提供商实现该 trait
- **消息类型** → 用 `enum Message` (ADT) 表示 User / Assistant / ToolResult
- **工具系统** → `Tool` trait + `ToolResult` 类型
- **Agent 循环** → 基于 `Iter` 或自定义事件流
- **TUI 组件** → `Component` trait，render 返回渲染树
- **扩展 API** → `Extension` trait，生命周期回调

## 文档计划

每个实现阶段对应一篇文档：

| 编号 | 主题 |
|------|------|
| 00 | 项目总览（本文） |
| 01 | LLM API 层：消息、模型、Provider |
| 02 | Agent 引擎：循环、工具、事件 |
| 03 | 终端 UI：组件、渲染、键盘 |
| 04 | 编码智能体：工具、会话、扩展 |
| 05 | CLI 入口与集成 |
| 06+ | Web UI / Slack / Pods |

每篇文档包含：
- 对应 pi-mono 包的架构分析
- MoonBit 实现的设计决策
- 关键类型和接口定义
- 与 TypeScript 版的对照
