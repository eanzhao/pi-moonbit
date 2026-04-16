///| 扩展回调可见的上下文。
pub(all) struct ExtensionContext {
  session_manager : SessionManager
  agent : @agent.Agent
  cwd : String
}

///| 扩展可执行的动作接口。
pub(all) struct ExtensionActions {
  /// 注入一条自定义上下文消息到 session。
  send_message : (String, Array[@ai.ContentBlock]) -> String
  /// 追加一条纯文本 user 消息到 steering 队列。
  steer : (String) -> Unit
  /// 追加一条纯文本 user 消息到 follow-up 队列。
  follow_up : (String) -> Unit
  /// 追加扩展私有 entry 到 session。
  append_entry : (String, Json?) -> String
  /// 获取当前模型。
  get_model : () -> @ai.Model
  /// 切换模型。
  set_model : (@ai.Model) -> Unit
  /// 获取当前 thinking level。
  get_thinking_level : () -> @agent.AgentThinkingLevel
  /// 切换 thinking level。
  set_thinking_level : (@agent.AgentThinkingLevel) -> Unit
  /// 当前 agent 是否空闲。
  is_idle : () -> Bool
}

///| 扩展注册的斜杠命令。
pub(all) struct ExtensionCommand {
  name : String
  description : String
  handler : (String, ExtensionContext, ExtensionActions) -> Result[Unit, String]
}

///| 扩展定义。
pub(all) struct CodingExtension {
  name : String
  /// 扩展注册的工具。
  tools : Array[@agent.AgentTool]
  /// 扩展注册的斜杠命令。
  commands : Array[ExtensionCommand]
  /// 启动时调用。
  on_start : ((ExtensionContext, ExtensionActions) -> Result[Unit, String])?
  /// 每条消息到达时调用。
  on_message : ((@ai.Message, ExtensionContext) -> Unit)?
  /// Agent 开始运行时调用。
  on_agent_start : ((ExtensionContext) -> Unit)?
  /// Agent 结束运行时调用（携带本次新增消息）。
  on_agent_end : ((Array[@ai.Message], ExtensionContext) -> Unit)?
  /// 工具调用前调用，可阻止执行。
  before_tool_call : ((@agent.BeforeToolCallContext, ExtensionContext) -> @agent.BeforeToolCallResult?)?
  /// 工具调用后调用，可覆盖结果。
  after_tool_call : ((@agent.AfterToolCallContext, ExtensionContext) -> @agent.AfterToolCallResult?)?
  /// 上下文发送给 LLM 前调用，可修改消息列表。
  transform_context : ((Array[@ai.Message], ExtensionContext) -> Array[@ai.Message])?
}

///| 创建一个只有名称的空扩展（方便测试和渐进构建）。
pub fn CodingExtension::empty(name : String) -> CodingExtension {
  {
    name,
    tools: [],
    commands: [],
    on_start: None,
    on_message: None,
    on_agent_start: None,
    on_agent_end: None,
    before_tool_call: None,
    after_tool_call: None,
    transform_context: None,
  }
}

///| 扩展运行时。
pub(all) struct ExtensionRuntime {
  mut extensions : Array[CodingExtension]
}

///| 创建扩展运行时。
pub fn ExtensionRuntime::new(extensions? : Array[CodingExtension] = []) -> ExtensionRuntime {
  { extensions: extensions.copy() }
}

///| 动态注册一个扩展。
pub fn ExtensionRuntime::register(self : ExtensionRuntime, extension : CodingExtension) -> Unit {
  self.extensions.push(extension)
}

///| 收集所有扩展注册的工具。
pub fn ExtensionRuntime::collect_tools(self : ExtensionRuntime) -> Array[@agent.AgentTool] {
  let tools : Array[@agent.AgentTool] = []
  for extension in self.extensions {
    for tool in extension.tools {
      tools.push(tool)
    }
  }
  tools
}

///| 收集所有扩展注册的命令。
pub fn ExtensionRuntime::collect_commands(self : ExtensionRuntime) -> Array[ExtensionCommand] {
  let commands : Array[ExtensionCommand] = []
  for extension in self.extensions {
    for command in extension.commands {
      commands.push(command)
    }
  }
  commands
}

///| 运行扩展启动钩子。
pub fn ExtensionRuntime::run_start(
  self : ExtensionRuntime,
  context : ExtensionContext,
  actions : ExtensionActions
) -> Result[Unit, String] {
  for extension in self.extensions {
    match extension.on_start {
      Some(handler) =>
        match handler(context, actions) {
          Ok(_) => ()
          Err(message) => return Err("extension \{extension.name}: " + message)
        }
      None => ()
    }
  }
  Ok(())
}

///| 广播消息事件到所有扩展。
pub fn ExtensionRuntime::notify_message(
  self : ExtensionRuntime,
  message : @ai.Message,
  context : ExtensionContext
) -> Unit {
  for extension in self.extensions {
    match extension.on_message {
      Some(handler) => handler(message, context)
      None => ()
    }
  }
}

///| 广播 agent start 事件。
pub fn ExtensionRuntime::notify_agent_start(
  self : ExtensionRuntime,
  context : ExtensionContext
) -> Unit {
  for extension in self.extensions {
    match extension.on_agent_start {
      Some(handler) => handler(context)
      None => ()
    }
  }
}

///| 广播 agent end 事件。
pub fn ExtensionRuntime::notify_agent_end(
  self : ExtensionRuntime,
  messages : Array[@ai.Message],
  context : ExtensionContext
) -> Unit {
  for extension in self.extensions {
    match extension.on_agent_end {
      Some(handler) => handler(messages, context)
      None => ()
    }
  }
}

///| 聚合 before_tool_call 钩子，阻塞优先。
pub fn ExtensionRuntime::before_tool_call(
  self : ExtensionRuntime,
  tool_context : @agent.BeforeToolCallContext,
  context : ExtensionContext
) -> @agent.BeforeToolCallResult? {
  let mut latest_allow : @agent.BeforeToolCallResult? = None
  for extension in self.extensions {
    match extension.before_tool_call {
      Some(handler) =>
        match handler(tool_context, context) {
          Some(result) if result.block => return Some(result)
          Some(result) => latest_allow = Some(result)
          None => ()
        }
      None => ()
    }
  }
  latest_allow
}

///| 聚合 after_tool_call 钩子，后注册扩展覆盖前者。
pub fn ExtensionRuntime::after_tool_call(
  self : ExtensionRuntime,
  tool_context : @agent.AfterToolCallContext,
  context : ExtensionContext
) -> @agent.AfterToolCallResult? {
  let mut any_override = false
  let mut content : Array[@ai.ContentBlock]? = None
  let mut details : Json? = None
  let mut is_error : Bool? = None

  for extension in self.extensions {
    match extension.after_tool_call {
      Some(handler) =>
        match handler(tool_context, context) {
          Some(result) => {
            any_override = true
            match result.content {
              Some(next_content) => content = Some(next_content)
              None => ()
            }
            match result.details {
              Some(next_details) => details = Some(next_details)
              None => ()
            }
            match result.is_error {
              Some(next_is_error) => is_error = Some(next_is_error)
              None => ()
            }
          }
          None => ()
        }
      None => ()
    }
  }

  if any_override {
    Some({ content, details, is_error })
  } else {
    None
  }
}

///| 聚合 transform_context 钩子，链式调用。
pub fn ExtensionRuntime::transform_context(
  self : ExtensionRuntime,
  messages : Array[@ai.Message],
  context : ExtensionContext
) -> Array[@ai.Message] {
  let mut result = messages
  for extension in self.extensions {
    match extension.transform_context {
      Some(handler) => result = handler(result, context)
      None => ()
    }
  }
  result
}
