# 00 - 项目总览

## 一句话介绍

pi-moonbit 是 [pi-mono](https://github.com/badlogic/pi-mono) 的 MoonBit 重写版。pi-mono 是一个 AI 编程助手工具包（TypeScript），我们用 MoonBit 把它从零重建一遍，边做边学。

## 为什么要做这个项目？

两个目的：

1. **学 MoonBit** —— 通过一个有真实复杂度的项目，掌握 MoonBit 的类型系统、trait、泛型、模式匹配、FFI 等核心能力。
2. **学架构** —— 逐包拆解重建 pi-mono，理解一个 AI Agent 从"调用 LLM API"到"在终端里渲染界面"的完整链路。

## pi-mono 是什么？

pi-mono 是 libGDX 作者 Mario Zechner 开源的 AI Agent 工具包，用 TypeScript 写的。它的设计哲学是"给积木不给框架"——提供可组合的基础组件，而不是一个全包的框架。它包含：

- **统一的 LLM API**：一套接口对接 13+ 家 LLM 提供商（Anthropic、OpenAI、Google、Mistral 等）
- **极简 Agent 引擎**：核心只有 5 个源文件
- **扩展系统**：自定义工具、UI 组件、子 Agent
- **内置编码工具**：文件读写、执行命令、搜索代码等
- **终端 UI 库**：差分渲染（只重绘变化的部分）
- **Web UI 组件库**：浏览器端的聊天界面

## pi-mono 的包结构

pi-mono 有 7 个包，各自负责一块明确的职责：

| 包 | npm 包名 | 做什么的 |
|---|---------|----------|
| `ai` | `@mariozechner/pi-ai` | 统一多 Provider LLM API：流式响应、模型发现 |
| `agent` | `@mariozechner/pi-agent-core` | Agent 循环引擎：工具调用、状态管理 |
| `coding-agent` | `@mariozechner/pi-coding-agent` | 编码助手 CLI：内置工具、会话管理、扩展系统 |
| `tui` | `@mariozechner/pi-tui` | 终端 UI 库：差分渲染、组件系统 |
| `web-ui` | `@mariozechner/pi-web-ui` | Web 聊天组件库 |
| `mom` | `@mariozechner/pi-mom` | Chat bot 支撑层：消息、workspace、event 统一抽象 |
| `pods` | `@mariozechner/pi` | GPU Pod 管理 CLI：vLLM 部署 |

它们的依赖关系长这样：

```
        ┌─── ai ────┐
        │            │
        ▼            ▼
      agent      web-ui ◄── tui
        │            ▲
        ├──► pods    │
        ▼            │
   coding-agent ─────┘
        │
        ▼
       mom
```

用人话说：

- **ai** 和 **tui** 是最底层的两个包，不依赖任何其他包（叶子包）
- **agent** 依赖 ai（Agent 需要 LLM API）
- **web-ui** 依赖 ai 和 tui（Web 界面需要 LLM API 和 UI 组件）
- **coding-agent** 依赖 ai、agent、tui（编码助手需要全部基础能力）
- **mom** 依赖 ai、agent、coding-agent（chat 平台消息会被整理后委派给编码助手处理）
- **pods** 依赖 agent（GPU Pod 管理需要 Agent 引擎）

## 我们怎么重写？

### 目录映射

pi-mono 的每个包对应 pi-moonbit 的 `lib/` 下的一个目录：

```
pi-mono/packages/          →    pi-moonbit/lib/
  ai/                      →      ai/
  agent/                   →      agent/
  coding-agent/            →      coding_agent/   (MoonBit 用下划线)
  tui/                     →      tui/
  web-ui/                  →      web_ui/
  mom/                     →      mom/
  pods/                    →      pods/
```

另外加一个 `src/main/` 作为 CLI 入口。

### 开发顺序

按照依赖关系从底向上开发：

| 阶段 | 包 | 做什么 |
|------|-----|------|
| 01 | `lib/ai` | 消息类型、模型定义、Provider trait、流式 API |
| 02 | `lib/tui` | 终端抽象、组件 trait、差分渲染（和 01 没有依赖，可以并行） |
| 03 | `lib/agent` | Agent 循环、工具类型、事件系统 |
| 04 | `lib/coding_agent` | 内置工具、会话管理、扩展 API |
| 05 | `src/main` | CLI 入口，把所有模块串起来 |
| 06 | `lib/web_ui` | Web transcript、storage/store、proxy、component/html view layer |
| 07 | `lib/mom` | channel 消息模型、log/context sync、sandbox/event/prompt 支撑层 |
| 08+ | 其他 | Pods / Slack adapter / 其他宿主接线 |

每个阶段写一篇文档（就是你正在读的这个系列），记录设计决策和实现细节。

## TypeScript 到 MoonBit：怎么翻译？

这是重写的核心问题。两种语言差别很大，以下是最重要的对应关系：

### 用 struct 代替数据接口

TypeScript 的 `interface` 大多是纯数据形状。MoonBit 中用 `struct`：

```typescript
// TypeScript
interface StreamOptions {
  temperature?: number;
  max_tokens?: number;
}
```

```moonbit
// MoonBit
pub(all) struct StreamOptions {
  temperature : Double?
  max_tokens : Int?
}
```

### 用 trait 代替行为接口

只有需要多态行为（不同实现有不同做法）的接口才用 `trait`：

```moonbit
pub(open) trait Provider {
  stream(Self, Model, Context, StreamOptions, EventHandler) -> Unit!StreamError
}
```

### 用 enum 代替联合类型

TypeScript 的联合类型 `A | B | C` 用 MoonBit 的 `enum`：

```typescript
// TypeScript
type Message = UserMessage | AssistantMessage | ToolResultMessage
```

```moonbit
// MoonBit
enum Message {
  User(UserMessage)
  Assistant(AssistantMessage)
  ToolResult(ToolResultMessage)
}
```

### 用 newtype 代替开放标识符

TypeScript 可以用任意字符串做 API/Provider 标识符。MoonBit 用包装类型：

```moonbit
pub(all) struct ApiId(String) derive(Eq, Hash, Show)
pub(all) struct ProviderId(String) derive(Eq, Hash, Show)
```

### 用 Result 代替 try/catch

```moonbit
// 用 Result[T, E] + ! 语法处理错误
fn do_something() -> Result[String, MyError] {
  Ok("success")
}
```

### 完整映射总览

| 维度 | TypeScript (pi-mono) | MoonBit (pi-moonbit) |
|------|----------------------|----------------------|
| 数据型接口 | `interface`（纯数据） | `struct` |
| 行为型接口 | `interface`（方法签名） | `trait`（需跨包扩展时用 `pub(open) trait`） |
| 封闭联合类型 | 联合类型 `A \| B \| C` | `enum`（ADT） |
| 开放联合类型 | `string & {}` / 声明合并 | newtype `String` + 注册表模式 |
| 泛型 | 泛型参数 + 条件类型 | 泛型参数 + Trait 约束 |
| 错误处理 | try/catch + Result | `Result[T, E]` + `!` 语法 |
| 异步 | async/await + AsyncIterable | `async fn`（实验性，Native 优先）或回调模式 |
| 序列化 | JSON 原生 | `@json` 库 |
| 编译目标 | Node.js / 浏览器 | Native（主要）/ WASM（仅 web_ui） |
| 包管理 | npm workspaces | MoonBit 单模块多包 |
| 包配置文件 | `package.json` | `moon.pkg`（非 JSON 格式） |

## 扩展机制：最复杂的翻译点

pi-mono 的扩展系统是它最核心的设计之一，但也是翻译到 MoonBit 最难的部分，因为涉及 TypeScript 特有的能力。

扩展机制分三个层面：

### 1. 声明合并（CustomAgentMessages）→ 注册表模式

TypeScript 的声明合并允许第三方扩展消息类型，MoonBit 没有这个能力。替代方案是注册表模式：

```moonbit
// 维护一个反序列化表，扩展在初始化时注册自定义消息类型
let deserializers : Map[String, (Bytes) -> AgentMessage!] = {}
```

### 2. 动态加载（extensions/loader.ts）→ 编译期注册

TypeScript 通过 `import()` 动态加载扩展模块。MoonBit Native 不支持动态链接，可选方案：

- **编译期注册**：扩展作为 MoonBit 包，编译时静态链接
- **WASM 插件**：扩展编译为 WASM 模块，宿主通过 WASM runtime 加载

### 3. 生命周期钩子（Extension 接口）→ 直接映射为 trait

这部分可以直接翻译：

```moonbit
pub(open) trait Extension {
  name(Self) -> String
  on_start(Self, ExtensionContext) -> Unit!
  on_before_tool_call(Self, BeforeToolCallContext) -> BeforeToolCallResult?
  on_after_tool_call(Self, AfterToolCallContext) -> AfterToolCallResult?
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
| 06 | Web UI 支撑层 |
| 07 | Mom 支撑层 |
| 08+ | Pods / adapter 宿主层 |

每篇文档包含：对应 pi-mono 包的架构分析、MoonBit 实现的设计决策、关键类型和接口定义、与 TypeScript 版的对照。
