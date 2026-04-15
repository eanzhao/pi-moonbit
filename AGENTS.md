# AGENTS.md — pi-moonbit

> AI 助手工作指南。详细版见 [CLAUDE.md](CLAUDE.md)。

## 这是什么？

用 MoonBit 重写 [pi-mono](https://github.com/badlogic/pi-mono)（AI Agent 工具包）。学习项目。

## 构建 & 测试

```bash
moon check          # 类型检查
moon build          # 编译
moon test           # 全部测试
moon test lib/ai    # 指定包测试
```

## 实现规则

1. **按依赖顺序**：ai、tui（并行） → agent → coding_agent → main
2. **每阶段一篇 doc + 一次 commit**：`docs/NN-*.md`
3. **先读 pi-mono 源码再实现**：`lib/ai` ←→ `pi-mono/packages/ai/src/`
4. **不要修改 `pi-mono/` 下的任何文件**
5. **MoonBit 风格**：数据用 `struct`，联合类型用 `enum`，行为用 `trait`，错误用 `Result`
6. **每个包都要有 `*_test.mbt` 测试**
7. **编译目标**：Native 为主，仅 web_ui 用 WASM

## 包结构

每个包遵循统一布局：

```
lib/<package>/
├── moon.pkg          # 包配置（依赖等）
├── types.mbt         # 核心类型定义
├── <module>.mbt      # 功能模块
└── *_test.mbt        # 测试
```

## 命名规范

- 包名：`snake_case`（如 `coding_agent`）
- 类型/Enum：`PascalCase`（如 `Message`、`StopReason`）
- 函数/方法：`snake_case`（如 `stream_simple`）
- 常量：`snake_case`（如 `api_anthropic_messages`）
- 测试：`test "描述性文字"` 块

## 提交格式

```
feat(ai): add Message enum and Provider trait
docs(00): project overview and architecture plan
feat(agent): implement agent loop with tool calling
```
