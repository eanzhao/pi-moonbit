struct TestFile {
  path : String
  content : String
}

struct TestFiles {
  files : Array[TestFile]
}

struct TestInputs {
  mut lines : Array[String]
}

fn TestFiles::new() -> TestFiles {
  { files: [] }
}

fn TestFiles::read_text(self : TestFiles, path : String) -> Result[String, String] {
  for file in self.files {
    if file.path == path {
      return Ok(file.content)
    }
  }
  Err("file not found: " + path)
}

fn TestFiles::write_text(self : TestFiles, path : String, content : String) -> Result[Unit, String] {
  for i in 0..<self.files.length() {
    if self.files[i].path == path {
      self.files[i] = { path, content }
      return Ok(())
    }
  }
  self.files.push({ path, content })
  Ok(())
}

fn TestFiles::exists(self : TestFiles, path : String) -> Bool {
  for file in self.files {
    if file.path == path {
      return true
    }
  }
  false
}

fn TestInputs::new(lines : Array[String]) -> TestInputs {
  { lines: lines.copy() }
}

fn TestInputs::next(self : TestInputs) -> String? {
  if self.lines.length() == 0 {
    return None
  }
  let next = self.lines[0]
  let remaining : Array[String] = []
  for i in 1..<self.lines.length() {
    remaining.push(self.lines[i])
  }
  self.lines = remaining
  Some(next)
}

fn test_model() -> @ai.Model {
  {
    id: "mock-cli",
    name: "mock-cli",
    api: @ai.ApiId("mock"),
    provider: @ai.ProviderId("mock"),
    base_url: None,
    reasoning: false,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 8192,
    max_tokens: 2048,
  }
}

fn test_runtime(
  files : Ref[TestFiles],
  inputs : Ref[TestInputs],
  stdout : Ref[Array[String]],
  stderr : Ref[Array[String]]
) -> CliHostRuntime {
  {
    read_text: fn(path) { files.val.read_text(path) },
    write_text: fn(path, content) { files.val.write_text(path, content) },
    file_exists: fn(path) { files.val.exists(path) },
    run_command: fn(_command, _cwd) {
      Ok({
        stdout: "",
        stderr: "",
        exit_code: 0,
        cancelled: false,
        truncated: false,
        full_output_path: None,
      })
    },
    stdout_write: fn(text) { stdout.val.push(text) },
    stderr_write: fn(text) { stderr.val.push(text) },
    read_line: fn(_prompt) { inputs.val.next() },
    current_dir: fn() { "/tmp/project" },
    now_iso: fn() { "2026-04-15T00:00:00.000Z" },
    agent_stream: Some(test_stream_fn()),
  }
}

fn test_stream_fn() -> @agent.AgentStreamFn {
  @agent.AgentStreamFn(fn(model, context, _options, handler) {
    let text = latest_user_text(context.messages).unwrap_or("(none)")
    let message : @ai.AssistantMessage = {
      content: [@ai.ContentBlock::Text("echo:" + text)],
      api: model.api,
      provider: model.provider,
      model: model.id,
      usage: @ai.Usage::zero(),
      stop_reason: @ai.StopReason::Stop,
      error_message: None,
      timestamp: 0.0,
    }
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    Ok(())
  })
}

fn latest_user_text(messages : Array[@ai.Message]) -> String? {
  let mut i = messages.length()
  while i > 0 {
    i = i - 1
    match messages[i] {
      @ai.Message::User(message) =>
        for block in message.content {
          match block {
            @ai.ContentBlock::Text(text) => return Some(text)
            _ => ()
          }
        }
      _ => ()
    }
  }
  None
}

test "parse_cli_args handles print mode and session path" {
  let result = parse_cli_args(
    ["pi-moonbit", "--print", "--session", "state.jsonl", "--thinking", "high", "hello"],
    cwd="/workspace",
  )
  match result {
    Ok(CliParseResult::Run(config)) => {
      assert_true(config.mode == CliMode::Print)
      assert_eq(config.session_path, Some("/workspace/state.jsonl"))
      assert_true(config.thinking_level == @agent.AgentThinkingLevel::High)
      assert_eq(config.messages, ["hello"])
    }
    _ => fail("expected runnable config")
  }
}

test "session store round-trips transcript and session context" {
  let files = Ref::new(TestFiles::new())
  let stdout : Ref[Array[String]] = Ref::new([])
  let stderr : Ref[Array[String]] = Ref::new([])
  let inputs = Ref::new(TestInputs::new([]))
  let runtime = test_runtime(files, inputs, stdout, stderr)

  let session_manager = @coding_agent.SessionManager::new(
    session_id="session-test",
    timestamp="2026-04-15T00:00:00.000Z",
  )
  ignore(session_manager.append_message(@ai.Message::User({
    content: [@ai.ContentBlock::Text("hello")],
  })))
  ignore(session_manager.append_model_change(test_model()))
  ignore(session_manager.append_thinking_level_change(@agent.AgentThinkingLevel::Medium))

  let save_result = save_session_to_file(
    runtime,
    session_manager,
    "/tmp/project/.pi-moonbit/session.jsonl",
    "/tmp/project",
  )
  assert_true(save_result is Ok(_))

  let loaded = load_session_from_file(runtime, "/tmp/project/.pi-moonbit/session.jsonl")
  match loaded {
    Ok(payload) => {
      let transcript = payload.session_manager.build_transcript_messages()
      assert_eq(transcript.length(), 1)
      let context = payload.session_manager.build_session_context()
      assert_eq(context.model, Some(test_model()))
      assert_true(context.thinking_level == Some(@agent.AgentThinkingLevel::Medium))
    }
    Err(message) => fail(message)
  }
}

test "run_cli print mode persists session and prints assistant output" {
  let files = Ref::new(TestFiles::new())
  let stdout : Ref[Array[String]] = Ref::new([])
  let stderr : Ref[Array[String]] = Ref::new([])
  let inputs = Ref::new(TestInputs::new([]))
  let runtime = test_runtime(files, inputs, stdout, stderr)

  let config : CliConfig = {
    mode: CliMode::Print,
    system_prompt: default_system_prompt(),
    session_path: Some("/tmp/project/.pi-moonbit/session.jsonl"),
    persist_session: true,
    cwd: "/tmp/project",
    model: test_model(),
    thinking_level: @agent.AgentThinkingLevel::Off,
    messages: ["hello"],
  }

  let exit_code = run_cli(config, runtime)
  assert_eq(exit_code, 0)
  assert_eq(stdout.val.join(""), "echo:hello\n")
  assert_eq(stderr.val.length(), 0)
  assert_true(files.val.exists("/tmp/project/.pi-moonbit/session.jsonl"))

  let loaded = load_session_from_file(runtime, "/tmp/project/.pi-moonbit/session.jsonl")
  match loaded {
    Ok(payload) => {
      let transcript = payload.session_manager.build_transcript_messages()
      assert_eq(transcript.length(), 2)
    }
    Err(message) => fail(message)
  }
}

test "run_cli interactive mode handles prompt then quit" {
  let files = Ref::new(TestFiles::new())
  let stdout : Ref[Array[String]] = Ref::new([])
  let stderr : Ref[Array[String]] = Ref::new([])
  let inputs = Ref::new(TestInputs::new(["hello", ":quit"]))
  let runtime = test_runtime(files, inputs, stdout, stderr)

  let config : CliConfig = {
    mode: CliMode::Interactive,
    system_prompt: default_system_prompt(),
    session_path: None,
    persist_session: false,
    cwd: "/tmp/project",
    model: test_model(),
    thinking_level: @agent.AgentThinkingLevel::Off,
    messages: [],
  }

  let exit_code = run_cli(config, runtime)
  assert_eq(exit_code, 0)
  assert_true(stdout.val.join("").contains("Interactive mode."))
  assert_true(stdout.val.join("").contains("assistant> echo:hello"))
  assert_eq(stderr.val.length(), 0)
}
