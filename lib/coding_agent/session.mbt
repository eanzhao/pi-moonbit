///| 把 `agent`、`session_manager`、`extensions` 接起来的高层入口。
pub(all) struct AgentSession {
  agent : @agent.Agent
  session_manager : SessionManager
  extensions : ExtensionRuntime
  mut agent_listener : @agent.ListenerHandle?
}

///| 创建一个带会话管理和扩展钩子的 AgentSession。
pub fn AgentSession::new(
  model : @ai.Model,
  system_prompt? : String = "",
  thinking_level? : @agent.AgentThinkingLevel = @agent.AgentThinkingLevel::Off,
  session_manager? : SessionManager = SessionManager::new(),
  tools? : Array[@agent.AgentTool] = [],
  extensions? : ExtensionRuntime = ExtensionRuntime::new(),
) -> Result[AgentSession, String] {
  let loaded_context = session_manager.build_session_context()
  let effective_model = match loaded_context.model {
    Some(saved_model) => saved_model
    None => model
  }
  let effective_thinking = match loaded_context.thinking_level {
    Some(saved_level) => saved_level
    None => thinking_level
  }
  let agent = @agent.Agent::new(
    system_prompt=system_prompt,
    model=effective_model,
    thinking_level=effective_thinking,
    tools=merge_tools(tools, extensions.collect_tools()),
    messages=session_manager.build_transcript_messages(),
  )
  let session : AgentSession = {
    agent,
    session_manager,
    extensions,
    agent_listener: None,
  }
  session.bind_agent()
  match session.extensions.run_start({
    session_manager: session.session_manager,
    agent: session.agent,
  }) {
    Ok(_) => Ok(session)
    Err(message) => Err(message)
  }
}

///| 清理事件绑定。
pub fn AgentSession::dispose(self : AgentSession) -> Unit {
  match self.agent_listener {
    Some(handle) => {
      self.agent.unsubscribe(handle)
      self.agent_listener = None
    }
    None => ()
  }
}

///| 发送纯文本 prompt。
pub fn AgentSession::prompt_text(self : AgentSession, text : String) -> Result[Unit, @agent.AgentError] {
  self.refresh_agent_state_from_session()
  self.agent.prompt_text(text)
}

///| 发送单条消息 prompt。
pub fn AgentSession::prompt_message(
  self : AgentSession,
  message : @ai.Message
) -> Result[Unit, @agent.AgentError] {
  self.refresh_agent_state_from_session()
  self.agent.prompt_message(message)
}

///| 发送多条消息 prompt。
pub fn AgentSession::prompt_messages(
  self : AgentSession,
  messages : Array[@ai.Message]
) -> Result[Unit, @agent.AgentError] {
  self.refresh_agent_state_from_session()
  self.agent.prompt_messages(messages)
}

///| 继续当前 transcript。
pub fn AgentSession::continue_run(self : AgentSession) -> Result[Unit, @agent.AgentError] {
  self.refresh_agent_state_from_session()
  self.agent.continue_run()
}

///| 在当前 turn 结束后插入 steering 文本。
pub fn AgentSession::steer_text(self : AgentSession, text : String) -> Unit {
  self.agent.steer(user_text_message(text))
}

///| 在 agent 停止前插入 follow-up 文本。
pub fn AgentSession::follow_up_text(self : AgentSession, text : String) -> Unit {
  self.agent.follow_up(user_text_message(text))
}

///| 追加一个自定义上下文消息。
pub fn AgentSession::append_custom_message(
  self : AgentSession,
  custom_type : String,
  content : Array[@ai.ContentBlock],
  display? : Bool = true,
  details? : Json? = None
) -> String {
  self.session_manager.append_custom_message(custom_type, content, display~, details~)
}

///| 追加一条 bash 执行上下文消息。
pub fn AgentSession::append_bash_execution(
  self : AgentSession,
  command : String,
  output : String,
  exit_code? : Int? = None,
  cancelled? : Bool = false,
  truncated? : Bool = false,
  full_output_path? : String? = None
) -> String {
  self.session_manager.append_bash_execution(
    command,
    output,
    exit_code~,
    cancelled~,
    truncated~,
    full_output_path~,
  )
}

///| 追加扩展私有状态 entry。
pub fn AgentSession::append_custom_entry(
  self : AgentSession,
  custom_type : String,
  data? : Json? = None
) -> String {
  self.session_manager.append_custom_entry(custom_type, data~)
}

///| 切换模型，并把变更记入会话。
pub fn AgentSession::set_model(self : AgentSession, model : @ai.Model) -> String {
  self.agent.state.model = model
  self.session_manager.append_model_change(model)
}

///| 切换 thinking level，并把变更记入会话。
pub fn AgentSession::set_thinking_level(
  self : AgentSession,
  thinking_level : @agent.AgentThinkingLevel
) -> String {
  self.agent.state.thinking_level = thinking_level
  self.session_manager.append_thinking_level_change(thinking_level)
}

///| 切到某个分支节点。
pub fn AgentSession::branch(self : AgentSession, entry_id : String?) -> Result[Unit, String] {
  match self.session_manager.branch(entry_id) {
    Ok(_) => {
      self.refresh_agent_state_from_session()
      Ok(())
    }
    Err(message) => Err(message)
  }
}

///| 获取当前会话上下文快照。
pub fn AgentSession::build_session_context(self : AgentSession) -> SessionContext {
  self.session_manager.build_session_context()
}

fn AgentSession::bind_agent(self : AgentSession) -> Unit {
  self.agent.set_transform_context(fn(_messages) {
    self.session_manager.build_session_context().messages
  })
  self.agent.set_before_tool_call(fn(tool_context) {
    self.extensions.before_tool_call(tool_context, {
      session_manager: self.session_manager,
      agent: self.agent,
    })
  })
  self.agent.set_after_tool_call(fn(tool_context) {
    self.extensions.after_tool_call(tool_context, {
      session_manager: self.session_manager,
      agent: self.agent,
    })
  })
  self.agent_listener = Some(self.agent.subscribe(fn(event) {
    self.persist_agent_event(event)
  }))
}

fn AgentSession::persist_agent_event(self : AgentSession, event : @agent.AgentEvent) -> Unit {
  match event {
    @agent.AgentEvent::MessageEnd(message) => {
      let _ = self.session_manager.append_message(message)
    }
    _ => ()
  }
}

fn AgentSession::refresh_agent_state_from_session(self : AgentSession) -> Unit {
  if self.agent.state.is_streaming {
    return
  }
  let context = self.session_manager.build_session_context()
  self.agent.state.messages = self.session_manager.build_transcript_messages()
  match context.model {
    Some(model) => self.agent.state.model = model
    None => ()
  }
  match context.thinking_level {
    Some(level) => self.agent.state.thinking_level = level
    None => ()
  }
}

fn merge_tools(
  base_tools : Array[@agent.AgentTool],
  extension_tools : Array[@agent.AgentTool]
) -> Array[@agent.AgentTool] {
  let tools = base_tools.copy()
  for tool in extension_tools {
    tools.push(tool)
  }
  tools
}

fn user_text_message(text : String) -> @ai.Message {
  @ai.Message::User({ content: [@ai.ContentBlock::Text(text)] })
}
