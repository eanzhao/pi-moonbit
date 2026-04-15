# pi-moonbit

用 [MoonBit](https://www.moonbitlang.com/) 语言从零重建 [pi-mono](https://github.com/badlogic/pi-mono) —— 一个 AI 编程助手工具包。

## 这是什么？

pi-mono 是 libGDX 作者 Mario Zechner 用 TypeScript 写的 AI Agent 工具包。pi-moonbit 是它的 MoonBit 重写版，目的是：

- **学 MoonBit** —— 通过造一个真实项目，掌握类型系统、trait、泛型、模式匹配等特性
- **学架构** —— 逐包拆解重建，理解 AI Agent 从底层 LLM 调用到上层交互界面的完整设计

## 当前进度

**核心路径已完成**：5 个阶段、55 个源文件、7200+ 行代码、67 个测试全部通过。

| 包 | 状态 | 说明 |
|---|---|---|
| `lib/ai` | ✅ 已完成 | 统一 LLM API：消息类型、流式事件、Model/Provider 注册、cost 计算 |
| `lib/tui` | ✅ 已完成 | 终端 UI 框架：Component trait、差分渲染、Input/SelectList/Loader 等组件 |
| `lib/agent` | ✅ 已完成 | Agent 引擎：回合循环、工具三阶段执行、事件系统、steering/follow-up 队列 |
| `lib/coding_agent` | ✅ 已完成 | 编码助手核心：append-only 会话树、分支/compaction、扩展钩子、4 个内置工具 |
| `src/main` | ✅ 已完成 | CLI 入口：参数解析、JSONL session 持久化、Print/REPL 模式、JS host runtime |
| `lib/web_ui` | 🔲 待开发 | Web 聊天界面（WASM） |
| `lib/mom` | 🔲 待开发 | Slack 机器人集成 |
| `lib/pods` | 🔲 待开发 | GPU Pod 管理 |

## 快速开始

需要先安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)。

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 运行全部 67 个测试
moon test lib/ai    # 运行某个包的测试
```

## 项目结构

```
pi-moonbit/
├── moon.mod.json          # 模块定义
├── docs/                  # 架构文档（每个阶段一篇）
├── lib/
│   ├── ai/                # Phase 01 — LLM Provider 抽象层
│   ├── tui/               # Phase 02 — 终端 UI 库
│   ├── agent/             # Phase 03 — Agent 循环引擎
│   └── coding_agent/      # Phase 04 — 编码助手核心
├── src/main/              # Phase 05 — CLI 入口
└── pi-mono/               # 原始 TS 实现（只读参考，gitignored）
```

## 架构文档

每个阶段对应 `docs/` 下的一篇文档，记录"做了什么、为什么这样做、和 pi-mono 有什么不同"：

- [00 - 项目总览](docs/00-project-overview.md) — 架构分析与实现计划
- [01 - LLM API 层](docs/01-ai.md) — 消息、模型、Provider、流式事件
- [02 - 终端 UI 层](docs/02-tui.md) — 组件系统、差分渲染、键盘输入
- [03 - Agent 引擎](docs/03-agent.md) — 回合循环、工具执行、事件与状态
- [04 - Coding Agent](docs/04-coding-agent.md) — 会话管理、扩展系统、内置工具
- [05 - CLI 入口](docs/05-cli.md) — 参数解析、JSONL session、REPL

## 参考

- [pi-mono](https://github.com/badlogic/pi-mono) — 原始 TypeScript 实现
- [MoonBit 文档](https://docs.moonbitlang.com/) — 语言参考
