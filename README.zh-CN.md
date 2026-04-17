# pi-moonbit

用 [MoonBit](https://www.moonbitlang.com/) 语言从零重建 [pi-mono](https://github.com/badlogic/pi-mono) —— 一个 AI 编程助手工具包。CLI 命令名 `pimbt`。

> English version: [README.md](README.md)

## 这是什么？

pi-mono 是 libGDX 作者 Mario Zechner 用 TypeScript 写的 AI Agent 工具包。pi-moonbit 是它的 MoonBit 重写版，目的是：

- **学 MoonBit** —— 通过造一个真实项目，掌握类型系统、trait、泛型、模式匹配等特性
- **学架构** —— 逐包拆解重建，理解 AI Agent 从底层 LLM 调用到上层交互界面的完整设计

## 当前进度

**26 个规划 issue 全部完成**，343 个测试通过，~30K 行 MoonBit 代码。

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

## 关于 NyxID

[NyxID](https://github.com/ChronoAIProject/NyxID) 是一个开源的凭证代理与服务网关：一次连好外部服务（LLM providers、SSH 主机、MCP 服务器、OAuth 应用），之后从任何客户端——CLI、IDE、AI agent——都能直接用，不用在本地到处配 key。对 pimbt 来说，NyxID 的 LLM 网关是默认通道：你的各家 LLM API key 存在 NyxID 服务端，pimbt 通过 OAuth 登录，每次调用由 NyxID 按 model id 路由到对应 provider 并注入凭证。

## 安装

### 前置要求

- [MoonBit 工具链](https://www.moonbitlang.com/download/)
- Node.js 18+（pimbt 目前在 JS target 下运行）

### 一键安装

```bash
git clone https://github.com/eanzhao/pi-moonbit.git
cd pi-moonbit
./scripts/install.sh
```

默认安装到 `~/.local/bin/pimbt`（把 `~/.local/bin` 加到 PATH 即可用）。

其他选项：

```bash
PREFIX=/usr/local ./scripts/install.sh   # 系统级安装（可能需要 sudo）
./scripts/install.sh --symlink           # 开发模式：symlink main.js，重新 moon build 后自动生效
./scripts/install.sh --uninstall         # 卸载
```

安装后：

```bash
pimbt --help
pimbt login                              # 浏览器登录 NyxID
pimbt providers connect openai           # 添加 LLM key
pimbt --api nyxid-gateway --model gpt-5.4 "hello"
```

### 开发者命令

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 运行全部测试
moon test lib/ai    # 运行某个包的测试

# 不走 install 直接运行
moon run src/main --target js -- --help
```

## NyxID 集成（推荐用法）

好处：一次登录用遍所有已在 NyxID 配好的 provider；key 集中放服务端，轮换/吊销更容易；多设备同步，无需到处 `export OPENAI_API_KEY=...`。**pimbt 本地不接触任何 LLM API key**。

### 注册 NyxID 账号

NyxID 目前**需要邀请码**才能注册：

- 注册入口：<https://nyx.chrono-ai.fun/register>
- 邀请码：`NYX-S6SBEA4X`（共 20 个名额，先到先得）

### 用 pimbt 登录并配置（首次三步即可使用）

```bash
# 1. 浏览器登录 NyxID（无需 client_id，使用 NyxID 官方 CLI 流程）
pimbt login

# 2. login 成功后会自动检查你已连接哪些 provider。如果一个都没有：
pimbt providers connect openai       # 命令行内提示你贴 sk-... key
pimbt providers connect anthropic    # 也可以 --api-key sk-ant-... 直接传

# 3. 最简单的用法：直接 `pimbt`，进入 provider → 模型 两层交互选择器
#    （TTY 下方向键导航，真实 model id 从各 provider 的 /models 端点实时拉取）
pimbt

# 或者直接传 --model，NyxID 按 model id 自动路由到对应 provider：
pimbt --api nyxid-gateway --model gpt-5.4 "write a fib function"
pimbt --api nyxid-gateway --model claude-sonnet-4-5-20250929 "explain quicksort"

# 查看已连接 provider 和网关的前缀路由规则：
pimbt providers list
pimbt models
```

`--model` 可以填任何你在 NyxID 上配过 provider 的模型 id，pimbt 这边没有写死白名单。

凭证保存到 `~/.pimbt/nyxid-credentials.json`。当 NyxID 返回 401 时（token 过期或被吊销），pimbt 会提示你重新 `pimbt login`。

## 直连 Provider

```bash
export OPENAI_API_KEY=sk-...
pimbt --api openai-responses --model gpt-5.4 "hello"

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
- [NyxID](https://github.com/ChronoAIProject/NyxID) — 凭证代理 / OAuth IdP
- [MoonBit 文档](https://docs.moonbitlang.com/) — 语言参考
