priv enum ReplCommandResult {
  Continue
  Exit(Int)
  Prompt(String)
}

priv enum CliAppStartResult {
  Exit(Int)
  Ready(CliApp)
}

priv enum ResolvedCliSessionResult {
  Exit(Int)
  Ready(ResolvedCliSession)
}

priv struct ResolvedCliSession {
  session_manager : @coding_agent.SessionManager
  session_path : String?
  cwd : String
}

fn create_cli_app(
  config : CliConfig,
  runtime : CliHostRuntime
) -> Result[CliAppStartResult, String] {
  let resolved = match resolve_cli_session(config, runtime) {
    Ok(result) => result
    Err(message) => return Err(message)
  }
  match resolved {
    Exit(code) => Ok(Exit(code))
    Ready(startup) => {
      let tools = create_default_tools(runtime, startup.cwd)
      let extensions =
        @coding_agent.ExtensionRuntime::new(extensions=[cli_bash_history_extension()])
      match @coding_agent.AgentSession::new(
        config.model,
        system_prompt=config.system_prompt,
        thinking_level=config.thinking_level,
        session_manager=startup.session_manager,
        tools=tools,
        extensions=extensions,
      ) {
        Err(message) => Err(message)
        Ok(session) => {
          match runtime.agent_stream {
            Some(stream_fn) => session.agent.set_stream_fn(stream_fn)
            None => ()
          }
          Ok(Ready({
            session,
            runtime,
            session_path: startup.session_path,
            cwd: startup.cwd,
          }))
        }
      }
    }
  }
}

pub fn run_cli(config : CliConfig, runtime : CliHostRuntime) -> Int {
  match create_cli_app(config, runtime) {
    Err(message) => {
      (runtime.stderr_write)(message + "\n")
      1
    }
    Ok(Exit(code)) => code
    Ok(Ready(app)) =>
      match config.mode {
        CliMode::Print => run_print_mode(app, config.messages)
        CliMode::Interactive => run_interactive_mode(app, config.messages)
      }
  }
}

fn run_print_mode(app : CliApp, messages : Array[String]) -> Int {
  let mut exit_code = 0
  for message in messages {
    let code = run_prompt(app, message, "")
    if code != 0 {
      exit_code = code
    }
  }
  exit_code
}

fn run_interactive_mode(app : CliApp, messages : Array[String]) -> Int {
  (app.runtime.stdout_write)("Interactive mode. Type :help for commands.\n")

  let mut exit_code = 0
  for message in messages {
    let code = run_prompt(app, message, "assistant> ")
    if code != 0 {
      exit_code = code
    }
  }

  while true {
    match (app.runtime.read_line)("pi> ") {
      None => return exit_code
      Some(line) =>
        match handle_repl_command(app, line) {
          Continue => ()
          Exit(code) => return if code != 0 { code } else { exit_code }
          Prompt(prompt) => {
            let code = run_prompt(app, prompt, "assistant> ")
            if code != 0 {
              exit_code = code
            }
          }
        }
    }
  }

  exit_code
}

fn run_prompt(app : CliApp, prompt : String, assistant_prefix : String) -> Int {
  if prompt == "" {
    return 0
  }

  match app.session.prompt_text(prompt) {
    Err(error) => {
      (app.runtime.stderr_write)(agent_error_text(error) + "\n")
      1
    }
    Ok(_) => {
      match persist_session(app) {
        Ok(_) => ()
        Err(message) => {
          (app.runtime.stderr_write)(message + "\n")
          return 1
        }
      }
      match last_assistant_message(app.session.session_manager.build_transcript_messages()) {
        Some(message) =>
          if assistant_message_failed(message) {
            (app.runtime.stderr_write)(assistant_error_text(message) + "\n")
            1
          } else {
            let rendered = assistant_message_text(message)
            if rendered.length() > 0 {
              (app.runtime.stdout_write)(assistant_prefix + rendered + "\n")
            }
            0
          }
        None => 0
      }
    }
  }
}

fn handle_repl_command(app : CliApp, line : String) -> ReplCommandResult {
  if line == "" {
    return Continue
  }
  if !line.has_prefix(":") {
    return Prompt(line)
  }
  if line == ":quit" || line == ":exit" {
    return Exit(0)
  }
  if line == ":help" {
    (app.runtime.stdout_write)([
      "Commands:",
      "  :help",
      "  :session",
      "  :model <id>",
      "  :thinking <level>",
      "  :quit",
    ].join("\n") + "\n")
    return Continue
  }
  if line == ":session" {
    let path = match app.session_path {
      Some(path) => path
      None => "(ephemeral)"
    }
    (app.runtime.stdout_write)(
      "session: " + path +
      "\nmodel: " + app.session.agent.state.model.id +
      "\nthinking: " + thinking_level_name(app.session.agent.state.thinking_level) +
      "\nentries: " + app.session.session_manager.get_entries().length().to_string() +
      "\n",
    )
    return Continue
  }
  if line.has_prefix(":model ") {
    let next_id = line[7:].to_string()
    if next_id.length() == 0 {
      (app.runtime.stderr_write)("missing model id\n")
      return Continue
    }
    let current = app.session.agent.state.model
    let next_model : @ai.Model = {
      id: next_id,
      name: next_id,
      api: current.api,
      provider: current.provider,
      base_url: current.base_url,
      reasoning: current.reasoning,
      input_modalities: current.input_modalities.copy(),
      cost: current.cost,
      context_window: current.context_window,
      max_tokens: current.max_tokens,
    }
    ignore(app.session.set_model(next_model))
    ignore(persist_session(app))
    (app.runtime.stdout_write)("model switched to " + next_id + "\n")
    return Continue
  }
  if line.has_prefix(":thinking ") {
    let raw_level = line[10:].to_string()
    match parse_thinking_level(raw_level) {
      Some(level) => {
        ignore(app.session.set_thinking_level(level))
        ignore(persist_session(app))
        (app.runtime.stdout_write)("thinking switched to " + raw_level + "\n")
      }
      None => (app.runtime.stderr_write)("unknown thinking level: " + raw_level + "\n")
    }
    return Continue
  }
  (app.runtime.stderr_write)("unknown command: " + line + "\n")
  Continue
}

fn resolve_cli_session(
  config : CliConfig,
  runtime : CliHostRuntime
) -> Result[ResolvedCliSessionResult, String] {
  if !config.persist_session {
    return Ok(Ready(new_persisted_session(runtime, config.cwd, None)))
  }

  let session_dir = match config.session_dir {
    Some(path) => path
    None => default_session_dir(config.cwd)
  }

  match config.session_path {
    Some(path) => open_or_create_session(runtime, config.cwd, path)
    None =>
      if config.resume_session {
        match select_session_to_resume(runtime, session_dir) {
          Ok(Some(path)) => open_or_create_session(runtime, config.cwd, path)
          Ok(None) => Ok(Exit(0))
          Err(message) => Err(message)
        }
      } else if config.continue_session {
        match find_most_recent_session_path(runtime, session_dir) {
          Ok(Some(path)) => open_or_create_session(runtime, config.cwd, path)
          Ok(None) => Ok(Ready(new_persisted_session(runtime, config.cwd, Some(session_dir))))
          Err(message) => Err(message)
        }
      } else {
        Ok(Ready(new_persisted_session(runtime, config.cwd, Some(session_dir))))
      }
  }
}

fn open_or_create_session(
  runtime : CliHostRuntime,
  fallback_cwd : String,
  session_path : String
) -> Result[ResolvedCliSessionResult, String] {
  if !(runtime.file_exists)(session_path) {
    return Ok(Ready(new_persisted_session(runtime, fallback_cwd, Some(session_path))))
  }

  match load_session_from_file(runtime, session_path) {
    Err(message) => Err(message)
    Ok(loaded) =>
      Ok(Ready({
        session_manager: loaded.session_manager,
        session_path: Some(session_path),
        cwd: if loaded.cwd.length() > 0 { loaded.cwd } else { fallback_cwd },
      }))
  }
}

fn new_persisted_session(
  runtime : CliHostRuntime,
  cwd : String,
  path_or_dir : String?
) -> ResolvedCliSession {
  let session_manager = new_session_manager(runtime)
  let session_path = match path_or_dir {
    Some(path) if path.has_suffix(".jsonl") => Some(path)
    Some(dir) => Some(session_file_path(dir, session_manager.get_header().id))
    None => None
  }
  { session_manager, session_path, cwd }
}

fn select_session_to_resume(
  runtime : CliHostRuntime,
  session_dir : String
) -> Result[String?, String] {
  let sessions = match list_sessions(runtime, session_dir) {
    Ok(items) => items
    Err(message) => return Err(message)
  }
  if sessions.length() == 0 {
    (runtime.stdout_write)("No saved sessions found in " + session_dir + "\n")
    return Ok(None)
  }

  (runtime.stdout_write)("Saved sessions:\n")
  for i in 0..<sessions.length() {
    (runtime.stdout_write)(render_session_choice(i + 1, sessions[i]) + "\n")
  }
  (runtime.stdout_write)("Enter a number to resume, or press Enter to cancel.\n")

  while true {
    match (runtime.read_line)("resume> ") {
      None => return Ok(None)
      Some(line) => {
        let choice = line.trim().to_string()
        if choice == "" || choice == "q" || choice == "quit" {
          return Ok(None)
        }
        match parse_positive_int(choice) {
          Some(index) if index >= 1 && index <= sessions.length() => {
            return Ok(Some(sessions[index - 1].path))
          }
          _ => {
            (runtime.stderr_write)(
              "invalid selection: " + choice + " (expected 1-" +
              sessions.length().to_string() + ")\n",
            )
          }
        }
      }
    }
  }

  Ok(None)
}

fn render_session_choice(index : Int, info : SessionInfo) -> String {
  let parts : Array[String] = [
    index.to_string() + ". " + info.session_id,
  ]
  if info.timestamp.length() > 0 {
    parts.push(info.timestamp)
  }
  parts.push(info.cwd)
  let mut rendered = parts.join("  ")
  if info.preview.length() > 0 {
    rendered = rendered + "\n   " + info.preview
  }
  rendered
}

fn create_default_tools(
  runtime : CliHostRuntime,
  cwd : String
) -> Array[@agent.AgentTool] {
  let workspace_runtime : @coding_agent.WorkspaceRuntime = {
    read_text: fn(path) {
      (runtime.read_text)(resolve_workspace_path(cwd, path))
    },
    write_text: fn(path, content) {
      (runtime.write_text)(resolve_workspace_path(cwd, path), content)
    },
  }
  let command_runtime : @coding_agent.CommandRuntime = {
    run: fn(command) {
      (runtime.run_command)(command, cwd)
    },
  }
  [
    @coding_agent.create_read_tool(workspace_runtime),
    @coding_agent.create_write_tool(workspace_runtime),
    @coding_agent.create_edit_tool(workspace_runtime),
    @coding_agent.create_bash_tool(command_runtime),
  ]
}

fn cli_bash_history_extension() -> @coding_agent.CodingExtension {
  {
    name: "cli-bash-history",
    tools: [],
    on_start: None,
    before_tool_call: None,
    after_tool_call: Some(fn(tool_context, context) {
      if tool_context.tool_call.name != "bash" {
        return None
      }

      let command = json_string_field(tool_context.args, "command").unwrap_or("")
      let output = content_blocks_text(tool_context.result.content)
      let exit_code = json_int_field(tool_context.result.details, "exit_code")
      let cancelled = json_bool_field(tool_context.result.details, "cancelled").unwrap_or(false)
      let truncated = json_bool_field(tool_context.result.details, "truncated").unwrap_or(false)
      let full_output_path = json_string_field(tool_context.result.details, "full_output_path")
      ignore(context.session_manager.append_bash_execution(
        command,
        output,
        exit_code~,
        cancelled~,
        truncated~,
        full_output_path~,
      ))
      None
    }),
  }
}

fn new_session_manager(runtime : CliHostRuntime) -> @coding_agent.SessionManager {
  let timestamp = (runtime.now_iso)()
  @coding_agent.SessionManager::new(
    session_id=session_id_from_timestamp(timestamp),
    timestamp=timestamp,
  )
}

fn session_id_from_timestamp(timestamp : String) -> String {
  "session-" +
  timestamp.replace(old=":", new="-").replace(old=".", new="-")
}

fn parse_positive_int(text : String) -> Int? {
  let parsed : Result[Int, Error] = try? @string.parse_int(text)
  match parsed {
    Ok(value) if value > 0 => Some(value)
    _ => None
  }
}

fn resolve_workspace_path(cwd : String, path : String) -> String {
  if path.has_prefix("/") || path.has_prefix("~") {
    path
  } else if cwd.has_suffix("/") {
    cwd + path
  } else {
    cwd + "/" + path
  }
}

fn persist_session(app : CliApp) -> Result[Unit, String] {
  match app.session_path {
    Some(path) => save_session_to_file(app.runtime, app.session.session_manager, path, app.cwd)
    None => Ok(())
  }
}

fn last_assistant_message(messages : Array[@ai.Message]) -> @ai.AssistantMessage? {
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

fn assistant_message_failed(message : @ai.AssistantMessage) -> Bool {
  message.stop_reason == @ai.StopReason::Error ||
  message.stop_reason == @ai.StopReason::Aborted
}

fn assistant_error_text(message : @ai.AssistantMessage) -> String {
  match message.error_message {
    Some(text) if text.length() > 0 => text
    _ => "assistant request failed"
  }
}

fn agent_error_text(error : @agent.AgentError) -> String {
  match error {
    @agent.AgentError::AlreadyRunning => "agent is already running"
    @agent.AgentError::ContinueWithoutMessages => "cannot continue without prior messages"
    @agent.AgentError::ContinueFromAssistant => "cannot continue from the current assistant state"
    @agent.AgentError::StreamFailed(message) => "agent stream failed: " + message
  }
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

fn content_blocks_text(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => parts.push(text)
      _ => ()
    }
  }
  parts.join("")
}

fn json_string_field(json : Json, key : String) -> String? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(String(value)) => Some(value)
      _ => None
    }
  } else {
    None
  }
}

fn json_bool_field(json : Json, key : String) -> Bool? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(True) => Some(true)
      Some(False) => Some(false)
      _ => None
    }
  } else {
    None
  }
}

fn json_int_field(json : Json, key : String) -> Int? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Number(value, ..)) => Some(value.to_int())
      _ => None
    }
  } else {
    None
  }
}
