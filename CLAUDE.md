# CLAUDE.md — pi-moonbit

> 给 AI 编程助手的项目指南。AGENTS.md 是精简版。

## 项目简介

pi-moonbit 是 [pi-mono](https://github.com/badlogic/pi-mono)（AI Agent 工具包）的 MoonBit 重写。`pi-mono/` 目录是原始 TypeScript 代码（只读，不要修改）。

## 工具链

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 运行测试
moon test lib/ai    # 指定包测试
```

## 目录结构

```
pi-moonbit/
├── docs/               # 架构文档（编号，每阶段一篇）
├── lib/
│   ├── ai/             # LLM Provider 抽象层 ←→ pi-mono/packages/ai/src/
│   ├── tui/            # 终端 UI 库        ←→ pi-mono/packages/tui/src/
│   ├── agent/          # Agent 引擎         ←→ pi-mono/packages/agent/src/
│   ├── coding_agent/   # 编码助手           ←→ pi-mono/packages/coding-agent/src/
│   ├── web_ui/         # Web UI             ←→ pi-mono/packages/web-ui/src/
│   ├── mom/            # Slack 集成         ←→ pi-mono/packages/mom/src/
│   └── pods/           # GPU Pod 管理       ←→ pi-mono/packages/pods/src/
├── src/main/           # CLI 入口
└── pi-mono/            # 原始 TypeScript（只读）
```

## MoonBit 编码规范

- **数据容器**用 `struct`：`StreamOptions`、`Tool`、`Context` 等
- **可区分类型**用 `enum`（ADT）：`Message`、`StopReason`、`AssistantMessageEvent`
- **行为抽象**用 `trait`（跨包扩展时用 `pub(open) trait`）：`Provider`、`Component`
- **开放标识符**用 newtype 包装：`type ApiId String`
- **错误处理**用 `Result[T, E]` + `!` 语法
- **优先用模式匹配**而不是 if/else 链
- 测试写在 `*_test.mbt` 的 `test "..."` 块中

命名：包名 `snake_case`，类型 `PascalCase`，函数 `snake_case`。

## 开发流程

1. **按依赖顺序开发**：ai、tui（并行） → agent → coding_agent → main
2. **每阶段一篇文档 + 一次提交**：`docs/NN-topic.md`
3. **实现前先读 pi-mono 对应源码**
4. **编译目标**：Native 为主，仅 web_ui 用 WASM
5. **提交格式**：`feat(ai): add Message enum and Provider trait`

## TypeScript → MoonBit 关键映射

| TypeScript | MoonBit | 例子 |
|-----------|---------|------|
| `interface`（纯数据） | `struct` | `StreamOptions`、`Context`、`Tool` |
| `interface`（有方法） | `trait` | `Provider.stream()`、`Component.render()` |
| 联合类型 `A \| B` | `enum` | `Message`、`StopReason`、`AssistantMessageEvent` |
| `string & {}` | newtype `String` | `ApiId`、`ProviderId` |
| 声明合并 | 注册表模式 | `register_provider()`、CustomAgentMessages 反序列化表 |
| `async/await` | `async fn`（实验性）或回调 | 事件流用 `EventHandler` 回调 |
| `AsyncIterable` | 回调或 `Iter`（保底方案） | `stream()` 推送事件 |
| JSON 原生 | `@json` 库 | — |
| npm workspaces | MoonBit 单模块多包 | — |
| `package.json` | `moon.pkg`（非 JSON 格式） | — |

## pi-mono 关键抽象

实现各包时，需要从 pi-mono 移植的核心抽象：

| 抽象 | 包 | 职责 |
|------|-----|------|
| `Provider` | ai | LLM 提供商，核心方法 `stream()` / `complete()` |
| `AgentLoop` | agent | 编排 LLM 调用和工具执行的循环引擎 |
| `AgentTool` | agent | 工具定义（schema + execute） |
| `Component` | tui | UI 元素，核心方法 `render()` + 输入处理 |
| `Extension` | coding-agent | 插件，含生命周期钩子（on_start / on_before_tool_call / on_after_tool_call） |
