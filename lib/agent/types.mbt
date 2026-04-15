///| Agent 侧的思维级别。`Off` 表示不向底层 ai 包传递 reasoning 配置。
pub(all) enum AgentThinkingLevel {
  Off
  Minimal
  Low
  Medium
  High
  XHigh
} derive(Eq, ToJson, FromJson)

///| 多工具调用的执行模式。
pub(all) enum ToolExecutionMode {
  Sequential
  Parallel
} derive(Eq)

///| 队列取出模式。
pub(all) enum QueueMode {
  All
  OneAtATime
} derive(Eq)

///| Agent 运行期错误。
pub(all) enum AgentError {
  AlreadyRunning
  ContinueWithoutMessages
  ContinueFromAssistant
  StreamFailed(String)
} derive(Eq)

///| 工具执行的最终结果。
pub(all) struct AgentToolResult {
  content : Array[@ai.ContentBlock]
  details : Json
}

///| 工具执行中的增量更新回调。
pub(all) struct AgentToolUpdateHandler((AgentToolResult) -> Unit)

///| Agent 可调用工具定义。
pub(all) struct AgentTool {
  name : String
  label : String
  description : String
  parameters : Json
  prepare_arguments : ((Json) -> Result[Json, String])?
  validate_arguments : ((Json) -> Result[Unit, String])?
  execute : (String, Json, AgentToolUpdateHandler) -> Result[AgentToolResult, String]
}

///| Agent 当前循环使用的上下文快照。
pub(all) struct AgentContext {
  system_prompt : String
  mut messages : Array[@ai.Message]
  tools : Array[AgentTool]
}

///| `before_tool_call` 钩子的返回值。
pub(all) struct BeforeToolCallResult {
  block : Bool
  reason : String?
} derive(Eq)

///| `after_tool_call` 钩子的覆盖值。
pub(all) struct AfterToolCallResult {
  content : Array[@ai.ContentBlock]?
  details : Json?
  is_error : Bool?
}

///| `before_tool_call` 的上下文。
pub(all) struct BeforeToolCallContext {
  assistant_message : @ai.AssistantMessage
  tool_call : @ai.ToolCall
  args : Json
  context : AgentContext
}

///| `after_tool_call` 的上下文。
pub(all) struct AfterToolCallContext {
  assistant_message : @ai.AssistantMessage
  tool_call : @ai.ToolCall
  args : Json
  result : AgentToolResult
  is_error : Bool
  context : AgentContext
}

///| 底层 LLM stream 函数的可替换包装。
pub(all) struct AgentStreamFn(
  (@ai.Model, @ai.Context, @ai.StreamOptions, @ai.EventHandler) -> Result[Unit, String]
)

///| 低层 agent loop 的配置。
pub(all) struct AgentLoopConfig {
  mut model : @ai.Model
  mut options : @ai.StreamOptions
  mut convert_to_llm : ((Array[@ai.Message]) -> Array[@ai.Message])?
  mut transform_context : ((Array[@ai.Message]) -> Array[@ai.Message])?
  mut get_steering_messages : (() -> Array[@ai.Message])?
  mut get_follow_up_messages : (() -> Array[@ai.Message])?
  mut tool_execution : ToolExecutionMode
  mut before_tool_call : ((BeforeToolCallContext) -> BeforeToolCallResult?)?
  mut after_tool_call : ((AfterToolCallContext) -> AfterToolCallResult?)?
  mut stream_fn : AgentStreamFn?
}

///| turn 结束事件的载荷。
pub(all) struct TurnEndPayload {
  message : @ai.AssistantMessage
  tool_results : Array[@ai.ToolResultMessage]
}

///| assistant 增量事件的载荷。
pub(all) struct MessageUpdatePayload {
  message : @ai.Message
  assistant_event : @ai.AssistantMessageEvent
}

///| 工具开始执行事件。
pub(all) struct ToolExecutionStartPayload {
  tool_call_id : String
  tool_name : String
  args : Json
}

///| 工具执行增量事件。
pub(all) struct ToolExecutionUpdatePayload {
  tool_call_id : String
  tool_name : String
  args : Json
  partial_result : AgentToolResult
}

///| 工具执行结束事件。
pub(all) struct ToolExecutionEndPayload {
  tool_call_id : String
  tool_name : String
  result : AgentToolResult
  is_error : Bool
}

///| Agent 对外抛出的生命周期事件。
pub(all) enum AgentEvent {
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

///| Agent 的可观察状态。
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

///| 创建默认的 tool call 前置结果。
pub fn BeforeToolCallResult::allow() -> BeforeToolCallResult {
  { block: false, reason: None }
}

///| 创建阻止工具执行的结果。
pub fn BeforeToolCallResult::block(reason? : String = "") -> BeforeToolCallResult {
  if reason == "" {
    { block: true, reason: None }
  } else {
    { block: true, reason: Some(reason) }
  }
}

///| 默认的 agent loop 配置。
pub fn AgentLoopConfig::new(model : @ai.Model, options? : @ai.StreamOptions = @ai.StreamOptions::default()) -> AgentLoopConfig {
  {
    model,
    options,
    convert_to_llm: None,
    transform_context: None,
    get_steering_messages: None,
    get_follow_up_messages: None,
    tool_execution: Parallel,
    before_tool_call: None,
    after_tool_call: None,
    stream_fn: None,
  }
}

///| 创建未知模型占位符，便于先搭建 Agent 状态。
pub fn unknown_model() -> @ai.Model {
  {
    id: "unknown",
    name: "unknown",
    api: @ai.ApiId("unknown"),
    provider: @ai.ProviderId("unknown"),
    base_url: None,
    reasoning: false,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 0,
    max_tokens: 0,
  }
}

///| 创建一个空的 JSON object，作为工具结果 details 的默认值。
pub fn empty_json_object() -> Json {
  Json::object({})
}

///| 创建默认的 AgentState。
pub fn AgentState::new(
  system_prompt? : String = "",
  model? : @ai.Model = unknown_model(),
  thinking_level? : AgentThinkingLevel = Off,
  tools? : Array[AgentTool] = [],
  messages? : Array[@ai.Message] = [],
) -> AgentState {
  {
    system_prompt,
    model,
    thinking_level,
    tools: tools.copy(),
    messages: messages.copy(),
    is_streaming: false,
    streaming_message: None,
    pending_tool_calls: [],
    error_message: None,
  }
}

///| 将 Agent 级别的思维配置映射到底层 ai 包。
pub fn to_ai_reasoning(level : AgentThinkingLevel) -> @ai.ThinkingLevel? {
  match level {
    Off => None
    Minimal => Some(@ai.ThinkingLevel::Minimal)
    Low => Some(@ai.ThinkingLevel::Low)
    Medium => Some(@ai.ThinkingLevel::Medium)
    High => Some(@ai.ThinkingLevel::High)
    XHigh => Some(@ai.ThinkingLevel::XHigh)
  }
}
