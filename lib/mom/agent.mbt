pub fn MomAgentRuntime::new(
  workspace_runtime : @coding_agent.WorkspaceRuntime,
  command_runtime : @coding_agent.CommandRuntime,
  now_iso? : () -> String = fn() { "" },
  stream_fn? : @agent.AgentStreamFn? = None
) -> MomAgentRuntime {
  { workspace_runtime, command_runtime, now_iso, stream_fn }
}

pub fn MomAgentConfig::new(
  workspace_dir : String,
  sandbox : SandboxConfig,
  model : @ai.Model,
  runtime : MomAgentRuntime,
  thinking_level? : @agent.AgentThinkingLevel = @agent.AgentThinkingLevel::Off,
  global_memory? : String? = None,
  tools? : Array[@agent.AgentTool] = [],
  extensions? : Array[@coding_agent.CodingExtension] = [],
) -> MomAgentConfig {
  {
    workspace_dir,
    sandbox,
    model,
    thinking_level,
    global_memory,
    tools: if tools.length() == 0 { create_default_mom_tools(runtime) } else { tools.copy() },
    extensions: extensions.copy(),
    runtime,
  }
}

pub fn MomAgent::new(config : MomAgentConfig) -> MomAgent {
  { config, channel_store: InMemoryChannelStore::new(), sessions: [] }
}

pub fn create_default_mom_tools(runtime : MomAgentRuntime) -> Array[@agent.AgentTool] {
  [
    @coding_agent.create_read_tool(runtime.workspace_runtime),
    @coding_agent.create_write_tool(runtime.workspace_runtime),
    @coding_agent.create_edit_tool(runtime.workspace_runtime),
    @coding_agent.create_bash_tool(runtime.command_runtime),
  ]
}

pub fn MomAgent::get_session(
  self : MomAgent,
  qualified_id : String
) -> Ref[MomChannelSession]? {
  match parse_qualified_channel_id(qualified_id) {
    Some((adapter, channel_id)) => find_session(self.sessions, adapter, channel_id)
    None => None
  }
}

pub fn MomAgent::is_running(self : MomAgent, qualified_id : String) -> Bool {
  match self.get_session(qualified_id) {
    Some(session_ref) => session_ref.val.running
    None => false
  }
}

pub fn MomAgent::abort(self : MomAgent, qualified_id : String) -> Bool {
  match self.get_session(qualified_id) {
    Some(session_ref) => {
      session_ref.val.session.agent.abort()
      true
    }
    None => false
  }
}

pub fn MomAgent::handle_message(
  self : MomAgent,
  message : ChannelMessage,
  context : ChannelContext,
  channel_memory? : String? = None,
  skills? : Array[MomSkill] = [],
  on_event? : ((@agent.AgentEvent) -> Unit)? = None,
) -> Result[MomRunResult, MomAgentError] {
  let channel = find_context_channel(context, message.channel_id)
  let persisted_log = match load_channel_log_from_workspace(
    self.config.runtime.workspace_runtime,
    self.config.workspace_dir,
    context.adapter,
    message.channel_id,
  ) {
    Ok(value) => value
    Err(message) => return Err(WorkspaceReadFailed(message))
  }
  self.channel_store.replace_log(context.adapter, message.channel_id, persisted_log)
  let session_ref = match self.ensure_session(context.adapter, channel) {
    Ok(value) => value
    Err(message) => return Err(SessionInitFailed(message))
  }

  ignore(self.channel_store.append_message(context.adapter, message))
  match save_channel_log_to_workspace(
    self.config.runtime.workspace_runtime,
    self.config.workspace_dir,
    context.adapter,
    message.channel_id,
    self.channel_store.get_log(context.adapter, message.channel_id),
  ) {
    Ok(_) => ()
    Err(message) => return Err(WorkspaceWriteFailed(message))
  }
  let log_messages = self.channel_store.get_log(context.adapter, message.channel_id)
  ignore(sync_channel_log_to_session_manager(
    session_ref.val.session.session_manager,
    log_messages,
    exclude_message_id=Some(message.id),
  ))

  let loaded_memory = match load_workspace_memory_sections(
    self.config.runtime.workspace_runtime,
    self.config.workspace_dir,
    context.adapter,
    message.channel_id,
  ) {
    Ok(value) => value
    Err(message) => return Err(WorkspaceReadFailed(message))
  }
  let (workspace_global_memory, workspace_channel_memory) = loaded_memory
  let memory = build_memory_text(
    global_memory=merge_mom_memory_sections(workspace_global_memory, self.config.global_memory),
    channel_memory=merge_mom_memory_sections(workspace_channel_memory, channel_memory),
  )
  session_ref.val.session.agent.state.system_prompt = build_mom_system_prompt(
    self.config.workspace_dir,
    channel,
    memory,
    self.config.sandbox,
    context,
    skills~,
  )

  let listener = match on_event {
    Some(handler) => Some(session_ref.val.session.agent.subscribe(handler))
    None => None
  }

  session_ref.val.running = true
  let prompt_result = session_ref.val.session.prompt_message(
    @ai.Message::User(channel_message_to_user_message(message)),
  )
  session_ref.val.running = false

  match listener {
    Some(handle) => session_ref.val.session.agent.unsubscribe(handle)
    None => ()
  }

  match prompt_result {
    Err(error) => Err(AgentError(error))
    Ok(_) => {
      let result = build_run_result(session_ref.val.session.session_manager.build_transcript_messages())
      maybe_append_assistant_log(self.channel_store, context.adapter, message.channel_id, result, self.config.runtime.now_iso)
      match save_channel_log_to_workspace(
        self.config.runtime.workspace_runtime,
        self.config.workspace_dir,
        context.adapter,
        message.channel_id,
        self.channel_store.get_log(context.adapter, message.channel_id),
      ) {
        Ok(_) => ()
        Err(message) => return Err(WorkspaceWriteFailed(message))
      }
      match save_channel_context_to_workspace(
        self.config.runtime.workspace_runtime,
        self.config.workspace_dir,
        context.adapter,
        message.channel_id,
        session_ref.val.session.session_manager,
      ) {
        Ok(_) => ()
        Err(message) => return Err(WorkspaceWriteFailed(message))
      }
      Ok(result)
    }
  }
}

fn MomAgent::ensure_session(
  self : MomAgent,
  adapter : String,
  channel : ChannelInfo
) -> Result[Ref[MomChannelSession], String] {
  match find_session(self.sessions, adapter, channel.id) {
    Some(session_ref) => Ok(session_ref)
    None => {
      let timestamp = (self.config.runtime.now_iso)()
      let session_id = mom_session_id(adapter, channel.id)
      let session_manager = match load_channel_context_from_workspace(
        self.config.runtime.workspace_runtime,
        self.config.workspace_dir,
        adapter,
        channel.id,
        session_id,
        timestamp,
      ) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      let extensions = @coding_agent.ExtensionRuntime::new(extensions=self.config.extensions)
      let session = match @coding_agent.AgentSession::new(
        self.config.model,
        system_prompt="",
        thinking_level=self.config.thinking_level,
        session_manager=session_manager,
        tools=self.config.tools,
        extensions=extensions,
      ) {
        Ok(value) => value
        Err(message) => return Err(message)
      }
      match self.config.runtime.stream_fn {
        Some(stream_fn) => session.agent.set_stream_fn(stream_fn)
        None => ()
      }
      let session_ref = Ref::new({
        adapter,
        channel,
        session,
        running: false,
      })
      self.sessions.push(session_ref)
      Ok(session_ref)
    }
  }
}

fn find_session(
  sessions : Array[Ref[MomChannelSession]],
  adapter : String,
  channel_id : String
) -> Ref[MomChannelSession]? {
  for session_ref in sessions {
    if session_ref.val.adapter == adapter && session_ref.val.channel.id == channel_id {
      return Some(session_ref)
    }
  }
  None
}

fn find_context_channel(context : ChannelContext, channel_id : String) -> ChannelInfo {
  for channel in context.channels {
    if channel.id == channel_id {
      return channel
    }
  }
  { id: channel_id, name: channel_id, kind: ChannelKind::Channel }
}

fn build_run_result(messages : Array[@ai.Message]) -> MomRunResult {
  match latest_assistant_message(messages) {
    Some(message) => {
      let assistant_text = assistant_message_text(message)
      {
        stop_reason: message.stop_reason,
        error_message: message.error_message,
        assistant_text,
        usage: Some(message.usage),
      }
    }
    None => {
      stop_reason: @ai.StopReason::Stop,
      error_message: None,
      assistant_text: "",
      usage: None,
    }
  }
}

fn maybe_append_assistant_log(
  store : InMemoryChannelStore,
  adapter : String,
  channel_id : String,
  result : MomRunResult,
  now_iso : () -> String
) -> Unit {
  let text = match result.error_message {
    Some(message) if result.assistant_text.length() == 0 => message
    _ => result.assistant_text
  }
  if text.length() == 0 {
    return
  }
  ignore(store.append_message(adapter, {
    id: "bot-" + mom_safe_id((now_iso)()),
    channel_id,
    timestamp: (now_iso)(),
    sender: {
      id: "bot",
      username: "mom",
      display_name: Some("mom"),
      is_bot: true,
    },
    text,
    raw_text: None,
    attachments: [],
    is_mention: false,
    reply_to: None,
    metadata: None,
  }))
}

fn latest_assistant_message(messages : Array[@ai.Message]) -> @ai.AssistantMessage? {
  let mut i = messages.length()
  while i > 0 {
    i = i - 1
    match messages[i] {
      @ai.Message::Assistant(message) => return Some(message)
      _ => ()
    }
  }
  None
}

fn assistant_message_text(message : @ai.AssistantMessage) -> String {
  let parts : Array[String] = []
  for block in message.content {
    match block {
      @ai.ContentBlock::Text(text) => parts.push(text)
      _ => ()
    }
  }
  parts.join("")
}

fn merge_mom_memory_sections(left : String?, right : String?) -> String? {
  let parts : Array[String] = []
  match mom_memory_part(left) {
    Some(value) => parts.push(value)
    None => ()
  }
  match mom_memory_part(right) {
    Some(value) => parts.push(value)
    None => ()
  }
  if parts.length() == 0 {
    None
  } else {
    Some(parts.join("\n\n"))
  }
}

fn mom_memory_part(text : String?) -> String? {
  match text {
    Some(value) => {
      let trimmed = value.trim().to_string()
      if trimmed.length() == 0 {
        None
      } else {
        Some(trimmed)
      }
    }
    None => None
  }
}

fn mom_session_id(adapter : String, channel_id : String) -> String {
  "mom-" + mom_safe_id(adapter) + "-" + mom_safe_id(channel_id)
}

fn mom_safe_id(value : String) -> String {
  value
    .replace_all(old="/", new="-")
    .replace_all(old=":", new="-")
    .replace_all(old=" ", new="-")
}
