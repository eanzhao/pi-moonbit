///| 基于 ANSI 流式输出的交互模式。
/// 订阅 Agent 事件，实时显示 LLM 响应和工具执行状态。
fn run_tui_interactive_mode(app : CliApp, initial_messages : Array[String]) -> Int {
  let display = StreamingDisplay::new(app.runtime)
  let listener = app.session.agent.subscribe(fn(event) {
    display.handle_event(event)
  })
  tui_print_welcome(app)
  let mut exit_code = 0
  for message in initial_messages {
    let code = run_tui_prompt(app, display, message)
    if code != 0 { exit_code = code }
  }
  while true {
    match (app.runtime.read_line)(@tui.ansi_user_prompt()) {
      None => {
        app.session.agent.unsubscribe(listener)
        return exit_code
      }
      Some(line) =>
        match handle_tui_repl_command(app, display, line) {
          Continue => ()
          Exit(code) => {
            app.session.agent.unsubscribe(listener)
            return if code != 0 { code } else { exit_code }
          }
          Prompt(prompt) => {
            let code = run_tui_prompt(app, display, prompt)
            if code != 0 { exit_code = code }
          }
        }
    }
  }
  app.session.agent.unsubscribe(listener)
  exit_code
}

fn tui_print_welcome(app : CliApp) -> Unit {
  let write = app.runtime.stdout_write
  write(
    @tui.ansi_bold() + "pi-moonbit" + @tui.ansi_reset() +
    @tui.ansi_info(" — interactive mode") + "\n",
  )
  write(
    @tui.ansi_info(
      "model: " + app.session.agent.state.model.id +
      "  thinking: " + thinking_level_name(app.session.agent.state.thinking_level),
    ) + "\n",
  )
  write(@tui.ansi_info("Type :help for commands, :quit to exit.") + "\n\n")
}

fn run_tui_prompt(app : CliApp, display : StreamingDisplay, prompt : String) -> Int {
  if prompt == "" { return 0 }
  display.reset()
  match app.session.prompt_text(prompt) {
    Err(error) => {
      (app.runtime.stderr_write)(@tui.ansi_error(agent_error_text(error)) + "\n")
      1
    }
    Ok(_) => {
      display.finish()
      match persist_session(app) {
        Err(message) => {
          (app.runtime.stderr_write)(@tui.ansi_error(message) + "\n")
          1
        }
        Ok(_) => {
          if display.had_error { 1 } else { 0 }
        }
      }
    }
  }
}

fn handle_tui_repl_command(
  app : CliApp,
  display : StreamingDisplay,
  line : String
) -> ReplCommandResult {
  if line == "" { return Continue }
  if !line.has_prefix(":") { return Prompt(line) }
  if line == ":quit" || line == ":exit" { return Exit(0) }
  let write = app.runtime.stdout_write
  if line == ":help" {
    write(@tui.ansi_section_header("Commands") + "\n")
    write("  :help              Show this help\n")
    write("  :session           Show session info\n")
    write("  :model <id>        Switch model\n")
    write("  :thinking <level>  Switch thinking level (off|minimal|low|medium|high|xhigh)\n")
    write("  :quit              Exit\n\n")
    return Continue
  }
  if line == ":session" {
    let path = match app.session_path {
      Some(path) => path
      None => @tui.ansi_info("(ephemeral)")
    }
    write(@tui.ansi_section_header("Session") + "\n")
    write("  path:     " + path + "\n")
    write("  model:    " + app.session.agent.state.model.id + "\n")
    write("  thinking: " + thinking_level_name(app.session.agent.state.thinking_level) + "\n")
    write("  entries:  " + app.session.session_manager.get_entries().length().to_string() + "\n\n")
    return Continue
  }
  if line.has_prefix(":model ") {
    let next_id = line[7:].to_string()
    if next_id.length() == 0 {
      (app.runtime.stderr_write)(@tui.ansi_error("missing model id") + "\n")
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
    write(@tui.ansi_info("model → " + next_id) + "\n")
    return Continue
  }
  if line.has_prefix(":thinking ") {
    let raw = line[10:].to_string()
    match parse_thinking_level(raw) {
      Some(level) => {
        ignore(app.session.set_thinking_level(level))
        ignore(persist_session(app))
        write(@tui.ansi_info("thinking → " + raw) + "\n")
      }
      None => (app.runtime.stderr_write)(@tui.ansi_error("unknown level: " + raw) + "\n")
    }
    return Continue
  }
  (app.runtime.stderr_write)(@tui.ansi_error("unknown command: " + line) + "\n")
  Continue
}

// --- Streaming Display ---

struct StreamingDisplay {
  write : (String) -> Unit
  mut streaming : Bool
  mut had_error : Bool
  mut in_tool : Bool
  mut printed_assistant_label : Bool
}

fn StreamingDisplay::new(runtime : CliHostRuntime) -> StreamingDisplay {
  { write: runtime.stdout_write, streaming: false, had_error: false, in_tool: false, printed_assistant_label: false }
}

fn StreamingDisplay::reset(self : StreamingDisplay) -> Unit {
  self.streaming = false
  self.had_error = false
  self.in_tool = false
  self.printed_assistant_label = false
}

fn StreamingDisplay::finish(self : StreamingDisplay) -> Unit {
  if self.streaming {
    (self.write)("\n")
    self.streaming = false
  }
}

fn StreamingDisplay::handle_event(self : StreamingDisplay, event : @agent.AgentEvent) -> Unit {
  match event {
    @agent.AgentEvent::MessageStart(message) =>
      match message {
        @ai.Message::Assistant(_) => {
          self.streaming = true
          self.printed_assistant_label = false
        }
        _ => ()
      }
    @agent.AgentEvent::MessageUpdate(payload) =>
      match payload.assistant_event {
        @ai.AssistantMessageEvent::TextDelta(_, delta) => {
          if !self.printed_assistant_label {
            (self.write)(@tui.ansi_assistant_label())
            self.printed_assistant_label = true
          }
          (self.write)(delta)
        }
        _ => ()
      }
    @agent.AgentEvent::MessageEnd(message) =>
      match message {
        @ai.Message::Assistant(msg) => {
          if !self.printed_assistant_label {
            let text = streaming_display_extract_text(msg.content)
            if text.length() > 0 {
              (self.write)(@tui.ansi_assistant_label() + text + "\n")
              self.streaming = false
            }
          } else if self.streaming {
            (self.write)("\n")
            self.streaming = false
          }
          if msg.stop_reason == @ai.StopReason::Error {
            self.had_error = true
            match msg.error_message {
              Some(err) => (self.write)(@tui.ansi_error(err) + "\n")
              None => ()
            }
          }
        }
        _ => ()
      }
    @agent.AgentEvent::ToolExecutionStart(payload) => {
      if self.streaming {
        (self.write)("\n")
        self.streaming = false
      }
      self.in_tool = true
      (self.write)(@tui.ansi_tool_start(payload.tool_name) + "\n")
    }
    @agent.AgentEvent::ToolExecutionEnd(payload) => {
      self.in_tool = false
      if payload.is_error {
        (self.write)(@tui.ansi_tool_error(payload.tool_name) + "\n")
      } else {
        (self.write)(@tui.ansi_tool_success(payload.tool_name) + "\n")
      }
    }
    _ => ()
  }
}

fn streaming_display_extract_text(content : Array[@ai.ContentBlock]) -> String {
  let parts : Array[String] = []
  for block in content {
    match block {
      @ai.ContentBlock::Text(text) => parts.push(text)
      _ => ()
    }
  }
  parts.join("")
}
