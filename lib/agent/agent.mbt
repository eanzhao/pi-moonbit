struct ListenerEntry {
  id : ListenerHandle
  listener : (AgentEvent) -> Unit
}

///| 订阅句柄。
pub(all) struct ListenerHandle(Int) derive(Eq)

///| 状态化的 Agent 包装。
pub(all) struct Agent {
  mut state : AgentState
  mut stream_options : @ai.StreamOptions
  mut tool_execution : ToolExecutionMode
  mut convert_to_llm : ((Array[@ai.Message]) -> Array[@ai.Message])?
  mut transform_context : ((Array[@ai.Message]) -> Array[@ai.Message])?
  mut before_tool_call : ((BeforeToolCallContext) -> BeforeToolCallResult?)?
  mut after_tool_call : ((AfterToolCallContext) -> AfterToolCallResult?)?
  mut stream_fn : AgentStreamFn?
  mut listeners : Array[ListenerEntry]
  mut next_listener_id : Int
  mut steering_queue : PendingMessageQueue
  mut follow_up_queue : PendingMessageQueue
}

///| 创建一个默认 Agent。
pub fn Agent::new(
  system_prompt? : String = "",
  model? : @ai.Model = unknown_model(),
  thinking_level? : AgentThinkingLevel = Off,
  tools? : Array[AgentTool] = [],
  messages? : Array[@ai.Message] = [],
) -> Agent {
  {
    state: AgentState::new(system_prompt~, model~, thinking_level~, tools~, messages~),
    stream_options: @ai.StreamOptions::default(),
    tool_execution: Parallel,
    convert_to_llm: None,
    transform_context: None,
    before_tool_call: None,
    after_tool_call: None,
    stream_fn: None,
    listeners: [],
    next_listener_id: 0,
    steering_queue: PendingMessageQueue::new(),
    follow_up_queue: PendingMessageQueue::new(),
  }
}

///| 设置底层 stream 选项。
pub fn Agent::set_stream_options(self : Agent, options : @ai.StreamOptions) -> Unit {
  self.stream_options = options
}

///| 设置 convert_to_llm 钩子。
pub fn Agent::set_convert_to_llm(
  self : Agent,
  convert : (Array[@ai.Message]) -> Array[@ai.Message]
) -> Unit {
  self.convert_to_llm = Some(convert)
}

///| 设置 transform_context 钩子。
pub fn Agent::set_transform_context(
  self : Agent,
  transform : (Array[@ai.Message]) -> Array[@ai.Message]
) -> Unit {
  self.transform_context = Some(transform)
}

///| 设置 before_tool_call 钩子。
pub fn Agent::set_before_tool_call(
  self : Agent,
  hook : (BeforeToolCallContext) -> BeforeToolCallResult?
) -> Unit {
  self.before_tool_call = Some(hook)
}

///| 设置 after_tool_call 钩子。
pub fn Agent::set_after_tool_call(
  self : Agent,
  hook : (AfterToolCallContext) -> AfterToolCallResult?
) -> Unit {
  self.after_tool_call = Some(hook)
}

///| 设置自定义 stream 函数。
pub fn Agent::set_stream_fn(self : Agent, stream_fn : AgentStreamFn) -> Unit {
  self.stream_fn = Some(stream_fn)
}

///| 设置多工具执行模式。
pub fn Agent::set_tool_execution(self : Agent, mode : ToolExecutionMode) -> Unit {
  self.tool_execution = mode
}

///| 设置 steering 队列取出模式。
pub fn Agent::set_steering_mode(self : Agent, mode : QueueMode) -> Unit {
  self.steering_queue.mode = mode
}

///| 设置 follow-up 队列取出模式。
pub fn Agent::set_follow_up_mode(self : Agent, mode : QueueMode) -> Unit {
  self.follow_up_queue.mode = mode
}

///| 订阅 agent 生命周期事件。
pub fn Agent::subscribe(self : Agent, listener : (AgentEvent) -> Unit) -> ListenerHandle {
  let handle = ListenerHandle(self.next_listener_id)
  self.next_listener_id = self.next_listener_id + 1
  self.listeners.push({ id: handle, listener })
  handle
}

///| 取消订阅。
pub fn Agent::unsubscribe(self : Agent, handle : ListenerHandle) -> Unit {
  let retained : Array[ListenerEntry] = []
  for entry in self.listeners {
    if entry.id != handle {
      retained.push(entry)
    }
  }
  self.listeners = retained
}

///| 在当前 turn 结束后注入一条 steering 消息。
pub fn Agent::steer(self : Agent, message : @ai.Message) -> Unit {
  self.steering_queue.enqueue(message)
}

///| 在 agent 将要停止时注入 follow-up 消息。
pub fn Agent::follow_up(self : Agent, message : @ai.Message) -> Unit {
  self.follow_up_queue.enqueue(message)
}

///| 是否仍有队列消息。
pub fn Agent::has_queued_messages(self : Agent) -> Bool {
  self.steering_queue.has_items() || self.follow_up_queue.has_items()
}

///| 清空 steering 队列。
pub fn Agent::clear_steering_queue(self : Agent) -> Unit {
  self.steering_queue.clear()
}

///| 清空 follow-up 队列。
pub fn Agent::clear_follow_up_queue(self : Agent) -> Unit {
  self.follow_up_queue.clear()
}

///| 清空所有队列。
pub fn Agent::clear_all_queues(self : Agent) -> Unit {
  self.clear_steering_queue()
  self.clear_follow_up_queue()
}

///| 重置 transcript 和运行态。
pub fn Agent::reset(self : Agent) -> Unit {
  self.state.messages = []
  self.state.is_streaming = false
  self.state.streaming_message = None
  self.state.pending_tool_calls = []
  self.state.error_message = None
  self.clear_all_queues()
}

///| 同步模型下无需等待，保留 API 以兼容后续异步扩展。
pub fn Agent::wait_for_idle(_self : Agent) -> Unit {
}

///| 当前实现为同步执行，abort 暂时是 no-op。
pub fn Agent::abort(_self : Agent) -> Unit {
}

///| 用一条纯文本 user 消息启动 agent。
pub fn Agent::prompt_text(self : Agent, text : String) -> Result[Unit, AgentError] {
  self.prompt_message(user_text_message(text))
}

///| 用一条消息启动 agent。
pub fn Agent::prompt_message(self : Agent, message : @ai.Message) -> Result[Unit, AgentError] {
  self.prompt_messages([message])
}

///| 用多条消息启动 agent。
pub fn Agent::prompt_messages(self : Agent, messages : Array[@ai.Message]) -> Result[Unit, AgentError] {
  self.run_with_lifecycle(fn() {
    run_agent_loop(
      messages,
      self.create_context_snapshot(),
      self.create_loop_config(),
      fn(event) { self.process_event(event) },
    )
  })
}

///| 从当前 transcript 继续执行。
pub fn Agent::continue_run(self : Agent) -> Result[Unit, AgentError] {
  if self.state.is_streaming {
    return Err(AlreadyRunning)
  }
  if self.state.messages.length() == 0 {
    return Err(ContinueWithoutMessages)
  }
  guard last_state_message(self.state.messages) is Some(last_message) else {
    return Err(ContinueWithoutMessages)
  }
  if last_message is @ai.Message::Assistant(_) {
    let queued_steering = self.steering_queue.drain()
    if queued_steering.length() > 0 {
      return self.run_prompt_messages_with_options(queued_steering, skip_initial_steering_poll=true)
    }
    let queued_follow_ups = self.follow_up_queue.drain()
    if queued_follow_ups.length() > 0 {
      return self.prompt_messages(queued_follow_ups)
    }
    return Err(ContinueFromAssistant)
  }
  self.run_with_lifecycle(fn() {
    run_agent_loop_continue(
      self.create_context_snapshot(),
      self.create_loop_config(),
      fn(event) { self.process_event(event) },
    )
  })
}

fn Agent::run_prompt_messages_with_options(
  self : Agent,
  messages : Array[@ai.Message],
  skip_initial_steering_poll? : Bool = false
) -> Result[Unit, AgentError] {
  self.run_with_lifecycle(fn() {
    run_agent_loop(
      messages,
      self.create_context_snapshot(),
      self.create_loop_config(skip_initial_steering_poll~),
      fn(event) { self.process_event(event) },
    )
  })
}

fn Agent::run_with_lifecycle(self : Agent, executor : () -> Result[Array[@ai.Message], AgentError]) -> Result[Unit, AgentError] {
  if self.state.is_streaming {
    return Err(AlreadyRunning)
  }
  self.state.is_streaming = true
  self.state.streaming_message = None
  self.state.error_message = None
  self.state.pending_tool_calls = []
  let result = executor()
  match result {
    Ok(_) => ()
    Err(error) => self.handle_run_failure(error)
  }
  self.finish_run()
  Ok(())
}

fn Agent::handle_run_failure(self : Agent, error : AgentError) -> Unit {
  let message = failure_message(self.state.model, error)
  self.process_event(MessageStart(@ai.Message::Assistant(message)))
  self.process_event(MessageEnd(@ai.Message::Assistant(message)))
  self.process_event(TurnEnd({ message, tool_results: [] }))
  self.process_event(AgentEnd([@ai.Message::Assistant(message)]))
}

fn Agent::finish_run(self : Agent) -> Unit {
  self.state.is_streaming = false
  self.state.streaming_message = None
  self.state.pending_tool_calls = []
}

fn Agent::process_event(self : Agent, event : AgentEvent) -> Unit {
  match event {
    MessageStart(message) => self.state.streaming_message = Some(message)
    MessageUpdate(payload) => self.state.streaming_message = Some(payload.message)
    MessageEnd(message) => {
      self.state.streaming_message = None
      self.state.messages.push(message)
    }
    ToolExecutionStart(payload) => agent_add_pending_tool_call(self.state, payload.tool_call_id)
    ToolExecutionEnd(payload) => agent_remove_pending_tool_call(self.state, payload.tool_call_id)
    TurnEnd(payload) => {
      if payload.message.error_message is Some(message) {
        self.state.error_message = Some(message)
      }
    }
    AgentEnd(_) => self.state.streaming_message = None
    _ => ()
  }
  for entry in self.listeners {
    (entry.listener)(event)
  }
}

fn Agent::create_context_snapshot(self : Agent) -> AgentContext {
  {
    system_prompt: self.state.system_prompt,
    messages: self.state.messages.copy(),
    tools: self.state.tools.copy(),
  }
}

fn Agent::create_loop_config(self : Agent, skip_initial_steering_poll? : Bool = false) -> AgentLoopConfig {
  let skip_ref : Ref[Bool] = Ref::new(skip_initial_steering_poll)
  {
    model: self.state.model,
    options: stream_options_with_reasoning(self.stream_options, self.state.thinking_level),
    convert_to_llm: self.convert_to_llm,
    transform_context: self.transform_context,
    get_steering_messages: Some(fn() {
      if skip_ref.val {
        skip_ref.val = false
        []
      } else {
        self.steering_queue.drain()
      }
    }),
    get_follow_up_messages: Some(fn() { self.follow_up_queue.drain() }),
    tool_execution: self.tool_execution,
    before_tool_call: self.before_tool_call,
    after_tool_call: self.after_tool_call,
    stream_fn: self.stream_fn,
  }
}

fn user_text_message(text : String) -> @ai.Message {
  @ai.Message::User({ content: [@ai.ContentBlock::Text(text)] })
}

fn failure_message(model : @ai.Model, error : AgentError) -> @ai.AssistantMessage {
  {
    content: [@ai.ContentBlock::Text("")],
    api: model.api,
    provider: model.provider,
    model: model.id,
    usage: @ai.Usage::zero(),
    stop_reason: @ai.StopReason::Error,
    error_message: Some(agent_error_message(error)),
    timestamp: 0.0,
  }
}

fn agent_error_message(error : AgentError) -> String {
  match error {
    AlreadyRunning => "agent is already running"
    ContinueWithoutMessages => "no messages to continue from"
    ContinueFromAssistant => "cannot continue from assistant message"
    StreamFailed(message) => message
  }
}

fn stream_options_with_reasoning(
  options : @ai.StreamOptions,
  level : AgentThinkingLevel
) -> @ai.StreamOptions {
  {
    temperature: options.temperature,
    max_tokens: options.max_tokens,
    top_p: options.top_p,
    api_key: options.api_key,
    cache_retention: options.cache_retention,
    retry_count: options.retry_count,
    retry_delay_ms: options.retry_delay_ms,
    thinking_mode: options.thinking_mode,
    thinking_budget_tokens: options.thinking_budget_tokens,
    reasoning: to_ai_reasoning(level),
  }
}

fn agent_add_pending_tool_call(state : AgentState, tool_call_id : String) -> Unit {
  for pending in state.pending_tool_calls {
    if pending == tool_call_id {
      return
    }
  }
  state.pending_tool_calls.push(tool_call_id)
}

fn agent_remove_pending_tool_call(state : AgentState, tool_call_id : String) -> Unit {
  let retained : Array[String] = []
  for pending in state.pending_tool_calls {
    if pending != tool_call_id {
      retained.push(pending)
    }
  }
  state.pending_tool_calls = retained
}

fn last_state_message(messages : Array[@ai.Message]) -> @ai.Message? {
  if messages.length() == 0 {
    None
  } else {
    Some(messages[messages.length() - 1])
  }
}
