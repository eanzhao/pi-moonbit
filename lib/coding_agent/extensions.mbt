///| 扩展回调可见的上下文。
pub(all) struct ExtensionContext {
  session_manager : SessionManager
  agent : @agent.Agent
}

///| phase 04 的扩展定义。先用回调结构体把运行时接起来。
pub(all) struct CodingExtension {
  name : String
  tools : Array[@agent.AgentTool]
  on_start : ((ExtensionContext) -> Result[Unit, String])?
  before_tool_call : ((@agent.BeforeToolCallContext, ExtensionContext) -> @agent.BeforeToolCallResult?)?
  after_tool_call : ((@agent.AfterToolCallContext, ExtensionContext) -> @agent.AfterToolCallResult?)?
}

///| 扩展运行时。
pub(all) struct ExtensionRuntime {
  mut extensions : Array[CodingExtension]
}

///| 创建扩展运行时。
pub fn ExtensionRuntime::new(extensions? : Array[CodingExtension] = []) -> ExtensionRuntime {
  { extensions: extensions.copy() }
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

///| 运行扩展启动钩子。
pub fn ExtensionRuntime::run_start(
  self : ExtensionRuntime,
  context : ExtensionContext
) -> Result[Unit, String] {
  for extension in self.extensions {
    match extension.on_start {
      Some(handler) =>
        match handler(context) {
          Ok(_) => ()
          Err(message) => return Err("extension \{extension.name}: " + message)
        }
      None => ()
    }
  }
  Ok(())
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
