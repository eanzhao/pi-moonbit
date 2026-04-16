# 07 - Mom 运行层：lib/mom

## 这一阶段做了什么？

phase 07 没有直接把 `pi-mono/packages/mom` 的 Slack Socket Mode 和 Docker 执行器原样搬过来，而是先把 MoonBit 最适合承接、也最容易测试的那层平台无关运行层落成了一个新的 `lib/mom` 包：

- 统一 channel / user / attachment / message 数据模型
- 平台无关的 workspace 路径规划与 channel namespace 规则
- `log.jsonl` 的 JSONL 解析与序列化
- channel log 到 `SessionManager` 的 context 同步逻辑
- sandbox 参数解析与 host/container 路径映射
- events JSON 解析、序列化与触发消息格式化
- `event_time.mbt`：统一的 ISO 8601 timestamp 解析，供 planner 和 timer 层复用
- `event_plan.mbt`：按当前时间把 event 文件归类为 trigger / delete / schedule / register
- `event_host.mbt`：扫描 `workspace/events/`，做 poll-based delta tracking，把 trigger event 翻译成真正的 channel turn，并在成功后清理应删除的 event file
- `poll_sync(...)`：显式产出 one-shot / periodic 的 added / removed delta，供后续 timer / cron registry 直接消费
- `event_watch.mbt`：提供 watcher 侧 debounce queue，把抖动的文件变化折叠成稳定的待处理 filename 列表
- `event_timer.mbt`：one-shot timer registry，支持 register / remove / flush due
- `event_periodic.mbt`：periodic registry，承接 host sync 的 add / remove delta，并支持按 filename 查当前注册项
- `event_loop.mbt`：把 host sync、debounce queue、timer registry、periodic registry 收成一个可直接驱动宿主的 event loop，并暴露 `next_due_at_ms(...)` / `tick(...)` / `dispatch_periodic(...)`
- `event_handle.mbt`：把 event loop 当前状态翻译成宿主 watcher / wakeup timer / periodic handle 的目标状态、操作序列、closure callback runtime、`MomHostCallbacks` bundle、`from_handle_runtime` 桥接与 apply helper
- `runner.mbt`：把 adapter turn、event loop、handle runtime sync 收成统一的宿主入口
- `host.mbt`：提供 `InMemoryEventWorkspace`、`MomInMemoryHost`、`MomHostInput` / `MomHostResult` / `MomHostStep` / `MomHostStepError`，把 mock/CLI 宿主常用拼装收成即用型对象，并统一 message / file change / wakeup / periodic callback 入口、per-step callback delta、callback bundle、handle runtime bridge 与 callback apply helper
- `host_driver.mbt`：把 `MomInMemoryHost` 和 `MomHostCallbacks` 固定成一个可长期持有的 driver，对宿主直接暴露 `sync / message / file_changed / wakeup / periodic`，并提供 `new_in_memory(...)`、`new_in_memory_with_handle_runtime(...)`、watcher path 归一化与 event workspace mutation helpers
- `host_runtime.mbt`：把 `driver` 再封装成 closure-based 平台无关宿主接口，便于真实宿主只依赖 runtime 对象而不感知底层实现，并直接接收 watcher 返回的 event file path
- mom system prompt 生成与 skill 列表格式化
- 一个纯内存的 `InMemoryChannelStore`
- `MomAgentRuntime` / `MomAgentConfig` 运行时装配
- `MomAgent`：按 `adapter/channel` 复用 `AgentSession`
- channel 消息驱动 `coding_agent.AgentSession` 执行，并把 assistant 回复回写到 log
- `@agent.AgentEvent` 透传与运行状态跟踪
- `workspace.mbt`：`log.jsonl` / `context.jsonl` / `MEMORY.md` 的工作区读写与恢复
- `adapter.mbt`：`PlatformAdapter` trait、adapter outbound message、纯内存 mock adapter、端到端 dispatch helper

对应源码：

```text
lib/mom/
├── moon.pkg
├── types.mbt
├── store.mbt
├── context.mbt
├── sandbox.mbt
├── events.mbt
├── event_time.mbt
├── event_plan.mbt
├── event_host.mbt
├── event_watch.mbt
├── event_timer.mbt
├── event_periodic.mbt
├── event_loop.mbt
├── event_handle.mbt
├── runner.mbt
├── host.mbt
├── host_driver.mbt
├── host_runtime.mbt
├── prompt.mbt
├── agent.mbt
├── workspace.mbt
├── adapter.mbt
├── store_test.mbt
├── adapter_test.mbt
├── context_test.mbt
├── sandbox_test.mbt
├── events_test.mbt
├── event_time_test.mbt
├── event_plan_test.mbt
├── event_host_test.mbt
├── event_watch_test.mbt
├── event_timer_test.mbt
├── event_periodic_test.mbt
├── event_loop_test.mbt
├── event_handle_test.mbt
├── runner_test.mbt
├── host_test.mbt
├── host_driver_test.mbt
├── host_runtime_test.mbt
├── prompt_test.mbt
└── agent_test.mbt
```

这意味着仓库现在已经有了 mom 的“平台无关运行层”，而不再只是 README 里的一个待开发占位包。

## 为什么不先硬接 Slack？

`pi-mono` 当前 `mom` 的运行时高度依赖宿主：

- Slack Socket Mode / Web API
- Docker / host shell
- 文件下载
- 定时器与 cron

这些部分在 MoonBit 里如果一开始就直接做，会立刻把工作重心拖到第三方绑定和平台细节上。对这个仓库来说，更合理的顺序是先把稳定抽象讲清楚：

1. channel 消息长什么样
2. workspace 目录怎么命名
3. `log.jsonl` 如何映射回 `coding_agent` 的 `SessionManager`
4. event 文件的 shape 是什么
5. sandbox 配置如何影响 prompt 和路径翻译

这一步做完，后续无论是接 Slack、Discord，还是做 CLI/mock adapter，都会变成“接线”而不是“重新设计 mom”。

## 采用哪条架构路线？

这里没有照抄 `src/slack.ts -> agent.ts -> SlackContext` 那条 Slack-specific 结构，而是优先采用 `pi-mono/packages/mom/docs/new.md` 里提出的多平台方向：

- channel 用统一 `ChannelMessage`
- channel workspace 走 `channels/<adapter>/<channelId>/`
- events 用限定名 channel id：`adapter/channel`
- prompt 输出标准 markdown，由 adapter 自己做平台格式转换

MoonBit 版当前实现的核心类型大致是：

```moonbit
pub(all) struct ChannelMessage {
  id : String
  channel_id : String
  timestamp : String
  sender : ChannelSender
  text : String
  attachments : Array[ChannelAttachment]
  is_mention : Bool
  reply_to : String?
  metadata : Json?
}
```

以及：

```moonbit
pub(all) enum MomEvent {
  Immediate(ImmediateEvent)
  OneShot(OneShotEvent)
  Periodic(PeriodicEvent)
}
```

这两类数据基本把 mom 最核心的外部输入稳定住了。

## 这层怎么接已有 coding-agent？

这阶段最关键的桥接点有两处。

第一处是 `context.mbt`：

- `channel_message_to_context_text(...)` 把 channel 消息转成标准 user text
- `channel_message_to_user_message(...)` 把它映射为 `@ai.UserMessage`
- `sync_channel_log_to_session_manager(...)` 把未同步的非 bot 消息补进 `SessionManager`

这样 mom 不需要自己重新发明一套上下文树；它直接复用 phase 04 已经实现好的 append-only session 和 context build 逻辑。

第二处是 `agent.mbt`：

- `MomAgentRuntime` 组合 `WorkspaceRuntime`、`CommandRuntime` 和可注入 `stream_fn`
- `MomAgentConfig` 统一 model、sandbox、memory、tool/extension 装配
- `MomAgent` 为每个 `adapter/channel` 建一个 `MomChannelSession`
- `handle_message(...)` 会把当前 channel 的历史 log 同步进 `SessionManager`
- 然后重建 system prompt，调用 `AgentSession.prompt_message(...)`
- 运行完成后把最新 assistant 文本回写进 `channel_store`
- 并把 `log.jsonl` / `context.jsonl` 保存回工作区

这让 mom 已经不只是“能准备 prompt”，而是能真正接住一条 channel 消息并驱动底层 coding agent 跑完一个 turn。

第三处是 `workspace.mbt`：

- `load_channel_log_from_workspace(...)` / `save_channel_log_to_workspace(...)`
- `load_channel_context_from_workspace(...)` / `save_channel_context_to_workspace(...)`
- `load_workspace_memory_sections(...)`

也就是说，channel session 现在不再只是进程内状态；它已经可以从工作区恢复 `context.jsonl`，并在每次 turn 结束后把上下文重新写回工作区。

第四处是 `adapter.mbt`：

- `PlatformAdapter` 定义 adapter 的最小宿主接口
- `AdapterOutboundMessage` / `AdapterSentMessage` 定义平台无关的出站消息
- `run_mom_turn_with_adapter(...)` 把 adapter context 注入 `MomAgent`
- `InMemoryPlatformAdapter` 作为 mock/CLI 方向的最小可测试宿主

这一步的意义不是“已经有 Slack adapter”，而是先把 `MomAgent` 和宿主之间的边界钉死。后续接真实平台时，只需要把平台事件翻译成 `ChannelMessage`，再实现 `PlatformAdapter`。

另外，memory 也先做成纯文本组合函数：

- workspace memory
- channel memory

统一拼成 prompt 所需的 working memory 片段。

## `store.mbt` 负责什么？

这一版的 store 没去碰真实文件系统 API，而是先做三件稳定的事：

1. **路径规则**
   - `workspace/events/`
   - `workspace/channels/<adapter>/<channelId>/log.jsonl`
   - `attachments/`、`scratch/`、`skills/`
2. **JSONL 编解码**
   - 能写出 MoonBit 版统一消息格式
   - 能读回更旧的 Slack-specific log shape（如 `user/userName/displayName/original/local`）
3. **内存 store**
   - 追加消息
   - 按 channel 取 log
   - 生成 preview / message_count / last_message_at

这让 phase 07 保持纯函数和可测试，不需要先把宿主 runtime 抽象再做一遍。

在这之上，`MomAgent` 再把内存 store 当作最小可运行宿主，用它来验证：

1. 每个 channel 只初始化一次 session
2. 历史用户消息会被同步到 `SessionManager`
3. 当前 prompt 跑完后，assistant 回复会进入 channel log

## prompt 为什么改成标准 markdown？

`pi-mono` 的现有 Slack 版 system prompt 里有大量 mrkdwn 细节，比如：

- `*bold*`
- `<url|text>`
- `<@user>`

但这会把 agent 直接绑死到 Slack 上。MoonBit 版这里改成平台无关 prompt：

- agent 只输出标准 markdown
- mentions 用 `@username`
- 真正发到 Slack/Discord 时，再由 adapter 做格式转换

这和 `new.md` 的方向一致，也更适合后续扩展到多个聊天平台。

## 测试覆盖

`lib/mom` 当前新增 84 个测试，覆盖这些主线：

### store_test.mbt

- workspace 路径按 adapter/channel 命名
- `log.jsonl` 能 round-trip
- 能兼容旧的 Slack log shape
- 内存 store 去重并按最近消息排序 metadata

### context_test.mbt

- memory 文本能合并 workspace / channel 两层内容
- channel message 会把附件路径编码进上下文文本
- log sync 会跳过 bot / 当前消息，并按时间顺序追加

### sandbox / events / prompt tests

- `host` / `docker:<name>` 解析正确
- host 路径能翻译到 `/workspace/...`
- event JSON 能解析并生成 `[EVENT:...]` 触发文本
- system prompt 包含 memory、skills、events 与平台无关格式说明

### event_plan_test.mbt

- stale immediate event 会被标记为删除
- fresh immediate event 会直接触发
- one-shot event 会按当前时间区分 trigger / schedule
- periodic event 会登记为宿主侧持续调度
- 非法 event 文件会保留成 `Invalid(...)` 结果，避免静默吞掉

### event_host_test.mbt

- `workspace/events/` 只会装载 `.json` 文件，并按 filename 稳定排序
- workspace file metadata 会进入 planning，供 immediate staleness 判定使用
- `Trigger(...)` 会被翻译成真正的 `ChannelMessage`
- event target adapter 不匹配时会被宿主层直接拒绝
- trigger plan 可以直接经由 adapter 驱动 `MomAgent`
- poll host 会抑制未变化 event 的重复触发
- future one-shot event 会在到点后从 `ScheduleOneShot(...)` 自然切到 `Trigger(...)`
- immediate / stale event 在处理完成后会走宿主侧 cleanup，避免重启后重复触发
- `poll_sync(...)` 会显式给出 added / removed one-shot 与 periodic delta

### event_watch_test.mbt

- 重复文件变化会刷新 debounce deadline，而不是重复排队
- `flush_due(...)` 只返回已到期的 filename
- `next_due_at_ms(...)` 可让宿主直接计算下一次 debounce 唤醒点
- 多个 pending 文件会按 due time 和 filename 稳定排序
- `clear(...)` 可用于宿主取消已无效的待处理事件

### event_time / event_timer / event_periodic tests

- ISO timestamp 会被规范化到统一毫秒时间线
- one-shot timer registry 支持增删替换、`next_due_at_ms(...)` 和 `flush_due(...)`
- periodic registry 支持承接 host delta、按 filename 查找并稳定维护当前注册集

### event_handle_test.mbt

- loop 当前状态可以被翻译成宿主 watcher / wakeup timer / periodic handle 的目标状态
- handle plan 会显式给出需要新增和移除的 periodic 注册项
- handle plan 会输出稳定顺序的宿主操作序列
- `apply_event_handle_plan(...)` 可直接驱动平台无关 handle runtime，并把状态推进到目标值
- `apply_event_handle_operations(...)` 和 `apply_mom_host_step_handle_operations(...)` 可直接把 step delta 喂给 closure callback runtime
- `MomHostCallbacks` 可把宿主 4 个 closure 收成可复用 callback bundle
- `mom_host_callbacks_from_handle_runtime(...)` 可把现成 handle runtime 直接桥接成 callback bundle
- 当宿主状态已经和 loop 对齐时，handle plan 会稳定收敛为 no-op

### runner_test.mbt

- `MomRunner` 会把 workspace sync 和 handle apply 收成一次宿主同步
- channel turn 结束后会自动刷新 event handle 状态
- event tick 会在 dispatch 后重新同步 future timer / periodic handle
- periodic callback 也会复用同一条 runner 闭环

### host_test.mbt

- `MomInMemoryHost` 会把 event workspace、runner、adapter、handle runtime 和 mom agent 绑成一个即用宿主
- host `message / file change / sync / wakeup / periodic callback` 都可以通过统一 `handle_input(...)` 入口走同一套 runner 编排
- in-memory event workspace 会正确保留 future event、清理 consumed immediate event
- `mom_host_result_handle_plan(...)` 会只对真正推进 runner 状态的输入暴露 handle plan
- `step(...)` 会把一次宿主输入对应的 handle delta 一起返回，并在每步后 drain 已消费的 callback op
- `step_with_handle_runtime(...)`、`step_with_callbacks(...)`、`run_mom_host_input(...)` 和 `run_mom_host_input_with_callbacks(...)` 可让宿主把单步输入和 callback apply 收成一个调用

### host_driver_test.mbt

- `MomHostDriver` 会把 `MomInMemoryHost` 和 `MomHostCallbacks` 绑成长期持有的宿主 driver
- `sync / periodic / file_changed / wakeup` 会共享同一份 host 状态，而不是每次重新拼装
- `new_in_memory(...)` 和 `new_in_memory_with_handle_runtime(...)` 可直接产出可运行 driver，`file_changed_path(...)` 可把 watcher path 归一化为 event filename，`write_event / delete_event_file / clear_file_change` 可让宿主直接维护 event workspace

### host_runtime_test.mbt

- `MomHostRuntime` 会把 `driver` 收成 closure-based 宿主接口，保留同一份内部状态
- `event_filename(...)` / `file_changed_path(...)` 可让真实 watcher 直接把绝对路径喂给 runtime，而不需要宿主自己做 `events_dir` 过滤
- `mom_host_runtime_in_memory_with_handle_runtime(...)` 可直接产出只暴露 runtime API 的宿主入口

### event_loop_test.mbt

- workspace sync 会同时更新 host state、one-shot timer registry 和 periodic registry
- immediate event 会在 loop 中被直接 dispatch 并清理文件
- 到点的 one-shot timer 会在 loop 中被 flush、dispatch 并清理文件
- `next_due_at_ms(...)` 会返回 debounce queue 和 one-shot timer 里的最早唤醒点
- `tick(...)` 会把 due file change 和 due one-shot timer 收成一次宿主轮询
- `dispatch_periodic(...)` 可让 cron callback 直接按 registry filename 驱动 `MomAgent`
- watcher debounce queue 会通过 loop API 暴露给宿主

### agent_test.mbt

- `handle_message(...)` 会创建 session、透传 agent events，并写回 bot log
- 历史 channel log 会在当前 prompt 前同步进 `SessionManager`
- `is_running(...)` 会在回调期间为真，执行结束后恢复为假
- 新实例可以从 `context.jsonl` 恢复已有 session transcript
- `MEMORY.md` 会自动读入 system prompt

### adapter_test.mbt

- `run_mom_turn_with_adapter(...)` 会从 adapter 读取 users/channels 构造 context
- assistant 最终回复会通过 adapter `send_message(...)` 发出去
- raw `@agent.AgentEvent` 会转发给 adapter
- adapter 发消息失败会被提升为 `MomAgentError::AdapterFailed`

## 当前状态

phase 07 之后，`lib/mom` 已经具备：

- 平台无关消息模型
- per-channel `AgentSession` 运行层
- workspace/channel namespace 规则
- log JSONL 编解码
- workspace-backed `log.jsonl` / `context.jsonl` 持久化
- context sync 到 `SessionManager`
- sandbox 参数与路径映射
- events 解析、planning、workspace 扫描、poll-based state tracking、watcher debounce、shared time parsing、one-shot timer registry、periodic registry、event loop 编排、host handle planning / apply、runner 编排、in-memory host 拼装、统一 host step API、per-step callback delta、closure callback runtime 接线、callback bundle、handle runtime bridge、单步 callback apply helper、长期持有 host driver、driver builder、event workspace mutation helpers、closure-based host runtime、watcher path 归一化、trigger dispatch、periodic callback dispatch 与 cleanup
- mom system prompt 生成
- `PlatformAdapter` 抽象与 mock adapter 接线层

但还没有直接进入 MoonBit 仓库的部分仍然是宿主绑定：

- Slack / Discord adapter
- 实时 socket 连接
- 真实文件下载
- 真正常驻的 fs watcher / debounce 循环
- 真实 one-shot timer handle / periodic cron handle 绑定
- CLI/mock/slack 宿主入口把这些运行时拼起来
- 真实 bash executor 和容器校验

也就是说，这一版完成的是 mom 的“平台无关运行层”，而不是最终可联网运行的聊天机器人宿主。
