# pi-moonbit

用 [MoonBit](https://www.moonbitlang.com/) 语言从零重建 [pi-mono](https://github.com/badlogic/pi-mono) —— 一个 AI 编程助手工具包。CLI 命令名 `pimbt`。

## 这是什么？

pi-mono 是 libGDX 作者 Mario Zechner 用 TypeScript 写的 AI Agent 工具包。pi-moonbit 是它的 MoonBit 重写版，目的是：

- **学 MoonBit** —— 通过造一个真实项目，掌握类型系统、trait、泛型、模式匹配等特性
- **学架构** —— 逐包拆解重建，理解 AI Agent 从底层 LLM 调用到上层交互界面的完整设计

## 当前进度

**26 个规划 issue 全部完成**，323 个测试通过，~30K 行 MoonBit 代码。

| 包 | 状态 | 说明 |
|---|---|---|
| `lib/ai` | ✅ 完整 | 7 个 LLM Provider (OpenAI/Anthropic/Mistral/Gemini/Bedrock/Vertex/Azure)、NyxID gateway、OAuth + PKCE 基础设施、env-api-keys、model registry、overflow 检测 |
| `lib/tui` | ✅ 完整 | Component trait、差分渲染、组件库（Input/SelectList/Loader/Box/Container）、Markdown 渲染、fuzzy 搜索、autocomplete、undo stack |
| `lib/agent` | ✅ 完整 | Agent 引擎：回合循环、工具三阶段执行、事件系统、steering/follow-up 队列 |
| `lib/coding_agent` | ✅ 完整 | 会话树、compaction、扩展系统、6 内置工具、slash commands、skills、HTML export、path/mime/git/frontmatter 工具 |
| `src/main` (pimbt CLI) | ✅ 完整 | 3 模式 (Print/Interactive/RPC)、多 target (JS/Native/WASM)、主题系统、**NyxID OAuth 登录 + 自动 token 刷新** |
| `lib/web_ui` | ✅ 完整 | Web transcript、storage、6 dialogs、12 artifact 类型、tool renderers、IndexedDB backend 接口 |
| `lib/mom` | ✅ 完整 | 平台无关 channel 模型、Slack 适配器、事件循环/定时器/watcher/host driver |
| `lib/pods` | ✅ 完整 | PodRegistry、SSH/SCP 命令构建、vLLM 部署命令 |

## 快速开始

需要先安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)。

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 运行全部 323 个测试
moon test lib/ai    # 运行某个包的测试

# 运行 CLI（JS target）
moon run src/main --target js -- --help
```

## NyxID 集成（推荐用法）

[NyxID](https://nyx.chrono-ai.fun) 是凭证代理：用户在 NyxID 面板存 LLM API key，pimbt 通过 NyxID 代理调用，不直接接触 key。

```bash
# 一次性登录（自动打开浏览器，PKCE + OAuth 2.0）
pimbt login --client-id <your-nyxid-client-id>

# 之后直接用，NyxID 自动注入 key，access token 自动刷新
pimbt --api nyxid-gateway --model gpt-4o "write a fib function"
pimbt --api nyxid-gateway --model claude-sonnet-4-5-20250929 "explain quicksort"
```

## 直连 Provider

```bash
export OPENAI_API_KEY=sk-...
pimbt --api openai-responses --model gpt-4o "hello"

export ANTHROPIC_API_KEY=sk-ant-...
pimbt --api anthropic-messages --model claude-sonnet-4-5 "hello"

export GOOGLE_API_KEY=...
pimbt --api google-generativeai --model gemini-2.0-flash "hello"
```

## 项目结构

```
pi-moonbit/
├── moon.mod.json          # 模块定义
├── docs/                  # 架构文档（每阶段一篇）
├── lib/
│   ├── ai/                # Phase 01 — LLM Provider 抽象层
│   ├── tui/               # Phase 02 — 终端 UI 库
│   ├── agent/             # Phase 03 — Agent 循环引擎
│   ├── coding_agent/      # Phase 04 — 编码助手核心
│   ├── web_ui/            # Phase 06 — Web UI 支撑层
│   ├── mom/               # Phase 07 — Mom 运行层
│   └── pods/              # GPU Pod 管理
├── src/main/              # Phase 05 — pimbt CLI 入口
└── pi-mono/               # 原始 TS 实现（只读参考，gitignored）
```

## 架构文档

- [00 - 项目总览](docs/00-project-overview.md) — 架构分析与实现计划
- [01 - LLM API 层](docs/01-ai.md) — 消息、模型、Provider、流式事件
- [02 - 终端 UI 层](docs/02-tui.md) — 组件系统、差分渲染、键盘输入
- [03 - Agent 引擎](docs/03-agent.md) — 回合循环、工具执行、事件与状态
- [04 - Coding Agent](docs/04-coding-agent.md) — 会话管理、扩展系统、内置工具
- [05 - CLI 入口](docs/05-cli.md) — 参数解析、多 session JSONL、continue/resume、REPL
- [06 - Web UI 支撑层](docs/06-web-ui.md) — Web transcript、storage、artifacts、tool renderers
- [07 - Mom 运行层](docs/07-mom.md) — 统一 channel 模型、Slack 适配器

## 参考

- [pi-mono](https://github.com/badlogic/pi-mono) — 原始 TypeScript 实现
- [NyxID](https://github.com/eanzhao/NyxID) — 凭证代理 / OAuth IdP
- [MoonBit 文档](https://docs.moonbitlang.com/) — 语言参考
