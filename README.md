# pi-moonbit

用 [MoonBit](https://www.moonbitlang.com/) 语言从零重建 [pi-mono](https://github.com/badlogic/pi-mono) —— 一个 AI 编程助手工具包。

## 这是什么？

pi-mono 是 libGDX 作者 Mario Zechner 用 TypeScript 写的 AI Agent 工具包。pi-moonbit 是它的 MoonBit 重写版，目的是：

- **学 MoonBit** —— 通过造一个真实项目，掌握类型系统、trait、泛型、模式匹配等特性
- **学架构** —— 逐包拆解重建，理解 AI Agent 从底层 LLM 调用到上层交互界面的完整设计

## 当前进度

| 包 | 状态 | 说明 |
|---|---|---|
| `lib/ai` | 已完成 | 统一的多 LLM 提供商 API（消息类型、流式响应、Provider 注册） |
| `lib/tui` | 已完成（核心） | 终端 UI 框架（组件系统、差分渲染） |
| `lib/agent` | 已完成（核心） | Agent 循环引擎、工具调用、事件系统、状态管理 |
| `lib/coding_agent` | 待开发 | 编码助手：内置工具、会话管理、扩展系统 |
| `lib/web_ui` | 待开发 | Web 聊天界面（WASM） |
| `lib/mom` | 待开发 | Slack 机器人集成 |
| `lib/pods` | 待开发 | GPU Pod 管理 |

## 快速开始

需要先安装 [MoonBit 工具链](https://www.moonbitlang.com/download/)。

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 运行所有测试
moon test lib/ai    # 运行某个包的测试
```

## 项目结构

```
pi-moonbit/
├── moon.mod.json       # 模块定义
├── docs/               # 架构文档（每个阶段一篇）
├── lib/                # 库代码
│   ├── ai/             # LLM Provider 抽象层
│   ├── tui/            # 终端 UI 库
│   └── ...             # 其余待开发
└── pi-mono/            # 原始 TypeScript 实现（只读参考，不修改）
```

## 架构文档

每个开发阶段对应 `docs/` 下的一篇文档：

- [00 - 项目总览](docs/00-project-overview.md)
- [01 - LLM API 层](docs/01-ai.md)
- [02 - 终端 UI 层](docs/02-tui.md)
- [03 - Agent 引擎](docs/03-agent.md)

## 参考

- [pi-mono](https://github.com/badlogic/pi-mono) —— 原始 TypeScript 实现
- [MoonBit 文档](https://docs.moonbitlang.com/) —— 语言参考
