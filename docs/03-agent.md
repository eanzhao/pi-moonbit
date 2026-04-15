# 03 - Agent 引擎：lib/agent

## 这一阶段做了什么？

`lib/agent` 是把 `lib/ai` 变成“会干活的 Agent”的那一层。它负责：

- 驱动 LLM 回合循环
- 解析 assistant 发出的 tool call
- 执行工具并把结果回灌给下一轮 LLM
- 对外发出 UI 可消费的生命周期事件
- 提供一个有状态的 `Agent` 包装，管理 transcript、队列和订阅

这一版已经把 **phase 03 的核心骨架** 搭起来了：低层 loop、工具抽象、事件系统、状态管理、steering / follow-up 队列、测试。

## 要解决什么问题？

只有 `lib/ai` 还不够。LLM 只能“说”要调用工具，不能自己执行；也不知道什么时候该继续下一轮。`lib/agent` 做的是这层编排：

1. 先把用户消息送给 LLM
2. 如果 assistant 回复里有 tool call，就执行对应工具
3. 把工具结果包成 `ToolResultMessage`
4. 再次调用 LLM，让它基于工具结果继续
5. 直到没有工具调用、没有 steering、没有 follow-up 为止

## 核心概念

### AgentTool

Agent 工具不是只有一个 `execute()`。为了把“模型生成的 JSON 参数”变成“可执行的调用”，这一版拆成三步：

```moonbit
pub(all) struct AgentTool {
  name : String
  label : String
  description : String
  parameters : Json
  prepare_arguments : ((Json) -> Result[Json, String])?
  validate_arguments : ((Json) -> Result[Unit, String])?
  execute : (String, Json, AgentToolUpdateHandler) -> Result[AgentToolResult, String]
}
```

- `prepare_arguments`：兼容旧参数形状，先做重写
- `validate_arguments`：做最小校验
- `execute`：真正执行工具，并可通过回调推送增量更新

这里没有照抄 pi-mono 的 TypeBox 泛型，而是先用 `Json` + 回调落地。原因很现实：MoonBit 里先把 phase 03 的运行时跑通，比先硬搬一套复杂 schema 泛型更重要。

### AgentEvent

UI 需要知道 Agent 现在在做什么，所以 loop 会持续发事件：

```moonbit
enum AgentEvent {
  AgentStart
  AgentEnd(Array[@ai.Message])
  TurnStart
  TurnEnd(TurnEndPayload)
  MessageStart(@ai.Message)
  MessageUpdate(MessageUpdatePayload)
  MessageEnd(@ai.Message)
  ToolExecutionStart(ToolExecutionStartPayload)
  ToolExecutionUpdate(ToolExecutionUpdatePayload)
  ToolExecutionEnd(ToolExecutionEndPayload)
}
```

事件顺序和 pi-mono 保持同一思路：

- `agent_start`
- `turn_start`
- prompt 的 `message_start / message_end`
- assistant 的 `message_start / message_update* / message_end`
- 若有工具：
  - `tool_execution_start`
  - `tool_execution_update*`
  - `tool_execution_end`
  - tool result 的 `message_start / message_end`
- `turn_end`
- `agent_end`

### PendingMessageQueue

pi-mono 里有 steering queue 和 follow-up queue。这一版也保留了，而且支持两种 drain 语义：

```moonbit
enum QueueMode {
  All
  OneAtATime
}
```

- `OneAtATime`：一次只取一条，适合“边工作边插话”
- `All`：一次取完，适合批量补充上下文

### AgentState

高层 `Agent` 维护一份可观察状态：

```moonbit
pub(all) struct AgentState {
  mut system_prompt : String
  mut model : @ai.Model
  mut thinking_level : AgentThinkingLevel
  mut tools : Array[AgentTool]
  mut messages : Array[@ai.Message]
  mut is_streaming : Bool
  mut streaming_message : @ai.Message?
  mut pending_tool_calls : Array[String]
  mut error_message : String?
}
```

这让上层 UI 不用自己重建状态机，直接盯着 `Agent.state` 就够了。

### run_agent_loop 与 Agent

这一层分成两档 API：

#### 低层：`run_agent_loop` / `run_agent_loop_continue`

纯函数式入口，接收上下文、配置和事件回调，返回本次新增消息：

```moonbit
run_agent_loop(prompts, context, config, emit) -> Result[Array[@ai.Message], AgentError]
```

适合之后的 `coding_agent` 直接控制 loop。

#### 高层：`Agent`

有状态包装，封装了：

- transcript
- listener 订阅
- steering / follow-up 队列
- hook 配置
- prompt / continue_run 入口

```moonbit
let agent = Agent::new(model=model)
agent.prompt_text("hello")
agent.steer(user_message)
agent.continue_run()
```

注意这里不是 `continue()`，而是 `continue_run()`，因为 `continue` 在 MoonBit 里是关键字。

## 文件结构

```
lib/agent/
├── moon.pkg
├── types.mbt       # 工具、事件、状态、错误、配置
├── queue.mbt       # steering / follow-up 队列
├── loop.mbt        # 低层 loop：LLM 调用、tool call 执行、事件发射
├── agent.mbt       # 有状态 Agent 包装
├── queue_test.mbt
├── loop_test.mbt
└── agent_test.mbt
```

## 设计决策

### 1. 暂时不做 CustomAgentMessages

pi-mono 的 `AgentMessage` 可以通过声明合并扩展。MoonBit 没这个机制，所以 phase 03 先直接复用 `@ai.Message`。

这意味着：

- 当前 loop 只处理标准消息类型：`User / Assistant / ToolResult`
- 自定义 app 消息留到 phase 04 的扩展系统里解决

这是刻意收敛，不是遗漏。

### 2. tool arguments / details 统一先走 `Json`

TypeScript 版靠 TypeBox + 泛型维持 schema 和执行参数的强类型。MoonBit 先落地更直接的版本：

- 输入参数：`Json`
- 校验失败：`Result[Unit, String]`
- 结果 details：`Json`

先把运行时协议打通，后面再按需要引入更强的类型层。

### 3. `Parallel` 目前只对齐 API，不做真正并发

`ToolExecutionMode::Parallel` 目前是“先全部预检，再按源顺序同步执行”。这样做有两个原因：

1. 先把 phase 03 的行为接口和事件语义定住
2. MoonBit Native 这条线当前仍以同步实现最稳

也就是说，现在的 `Parallel` 更像“并行预留位”。后续如果要接线程、任务系统或 runtime，可以直接替换执行层，不用再改外部 API。

### 4. 失败路径编码进 transcript

如果低层 stream 函数直接返回错误，高层 `Agent` 不会把这当成“调用失败就中断 API”，而是会补一条 assistant error message 进 transcript，并更新 `state.error_message`。

这和 pi-mono 的方向一致：UI 更适合消费“对话里出现一条错误消息”，而不是消费一次裸异常。

## 测试覆盖

本阶段新增了 8 个测试，覆盖三类核心风险：

- `queue_test.mbt`
  - 默认 one-at-a-time drain
  - drain-all 模式
- `loop_test.mbt`
  - prompt → assistant 的基础事件与消息流
  - tool call 执行并进入下一轮
  - `before_tool_call` 阻止执行
- `agent_test.mbt`
  - `Agent.prompt_text()` 更新 transcript 并发事件
  - `continue_run()` 从 assistant 尾部消费 steering 队列
  - stream 失败时写入 assistant error message

## 和 pi-mono 的差异

| 还没做的 | 当前处理 |
|---------|---------|
| `CustomAgentMessages` 扩展 | phase 03 先直接复用 `@ai.Message` |
| 真正并行工具执行 | 先对齐 `ToolExecutionMode` API，内部仍同步 |
| abort signal / async listener | 当前实现是同步 loop，`abort()` 先保留为 no-op |
| tool `details` 写回 transcript | 先只保留在 runtime/event 层 |
| proxy / transport / session id | 后续按 `coding_agent` 真实需求补 |

## 当前状态

phase 03 的“最小可用 Agent 引擎”已经具备：

- 能跑消息循环
- 能执行工具
- 能发 UI 事件
- 能维护有状态 transcript
- 能处理 steering / follow-up
- 有测试兜底

下一步就是在 phase 04 里，把它和真正的 coding tools、扩展钩子、会话管理接起来。
