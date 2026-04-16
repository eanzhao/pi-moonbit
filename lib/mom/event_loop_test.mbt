struct TestLoopWorkspace {
  mut files : Array[(String, String, String?)]
}

fn TestLoopWorkspace::read_text(self : TestLoopWorkspace, path : String) -> Result[String, String] {
  for item in self.files {
    let (file_path, content, _modified_at) = item
    if file_path == path {
      return Ok(content)
    }
  }
  Err("missing file: " + path)
}

fn TestLoopWorkspace::list_files(
  self : TestLoopWorkspace,
  dir : String
) -> Result[Array[String], String] {
  let prefix = if dir.has_suffix("/") { dir } else { dir + "/" }
  let files : Array[String] = []
  for item in self.files {
    let (path, _content, _modified_at) = item
    if path.has_prefix(prefix) {
      files.push(path)
    }
  }
  Ok(files)
}

fn TestLoopWorkspace::read_modified_at(
  self : TestLoopWorkspace,
  path : String
) -> Result[String?, String] {
  for item in self.files {
    let (file_path, _content, modified_at) = item
    if file_path == path {
      return Ok(modified_at)
    }
  }
  Err("missing file: " + path)
}

fn TestLoopWorkspace::delete_file(
  self : TestLoopWorkspace,
  path : String
) -> Result[Unit, String] {
  let retained : Array[(String, String, String?)] = []
  let mut removed = false
  for item in self.files {
    let (file_path, _content, _modified_at) = item
    if file_path == path {
      removed = true
    } else {
      retained.push(item)
    }
  }
  if !removed {
    return Err("missing file: " + path)
  }
  self.files = retained
  Ok(())
}

fn test_loop_workspace(
  files : Array[(String, String, String?)]
) -> Ref[TestLoopWorkspace] {
  Ref::new({ files: files })
}

fn test_loop_runtime(
  workspace : Ref[TestLoopWorkspace]
) -> MomEventWorkspaceRuntime {
  MomEventWorkspaceRuntime::new(
    fn(path) { workspace.val.read_text(path) },
    fn(dir) { workspace.val.list_files(dir) },
    read_modified_at=fn(path) { workspace.val.read_modified_at(path) },
    delete_file=fn(path) { workspace.val.delete_file(path) },
  )
}

fn event_loop_test_model() -> @ai.Model {
  {
    id: "mock-mom",
    name: "mock-mom",
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

fn event_loop_test_agent_runtime() -> MomAgentRuntime {
  let workspace = Ref::new(@coding_agent.InMemoryWorkspace::new())
  MomAgentRuntime::new(
    @coding_agent.in_memory_workspace_runtime(workspace),
    {
      run: fn(command) {
        Ok({
          stdout: "ran:" + command,
          stderr: "",
          exit_code: 0,
          cancelled: false,
          truncated: false,
          full_output_path: None,
        })
      },
    },
    now_iso=fn() { "2026-04-16T12:00:00.000Z" },
    stream_fn=Some(event_loop_test_stream_fn()),
  )
}

fn event_loop_test_stream_fn() -> @agent.AgentStreamFn {
  @agent.AgentStreamFn(fn(model, context, _options, handler) {
    let text = event_loop_test_latest_user_text(context.messages).unwrap_or("(none)")
    let assistant : @ai.AssistantMessage = {
      content: [@ai.ContentBlock::Text("echo:" + text)],
      api: model.api,
      provider: model.provider,
      model: model.id,
      usage: @ai.Usage::zero(),
      stop_reason: @ai.StopReason::Stop,
      error_message: None,
      timestamp: 0.0,
    }
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, assistant))
    Ok(())
  })
}

fn event_loop_test_latest_user_text(messages : Array[@ai.Message]) -> String? {
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

fn event_loop_test_channels() -> Array[ChannelInfo] {
  [{ id: "C123", name: "build", kind: ChannelKind::Channel }]
}

fn event_loop_test_users() -> Array[UserInfo] {
  [{ id: "U1", username: "mario", display_name: Some("Mario") }]
}

test "event loop sync_workspace updates registries from host sync" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z")
  let event_workspace = test_loop_workspace([
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
    (
      "/workspace/events/daily.json",
      "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      None,
    ),
  ])
  let runtime = test_loop_runtime(event_workspace)

  let sync = loop_.sync_workspace(runtime, "2026-04-17T09:00:00+08:00").unwrap()

  assert_eq(sync.changed_plans.length(), 2)
  assert_eq(loop_.list_one_shot_timers().length(), 1)
  assert_eq(loop_.list_periodic_entries().length(), 1)
}

test "event loop process_workspace dispatches immediate events and keeps future timers" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z")
  let event_workspace = test_loop_workspace([
    (
      "/workspace/events/immediate.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"ping\"}",
      Some("2026-04-16T12:00:01Z"),
    ),
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let runtime = test_loop_runtime(event_workspace)
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_loop_test_model(),
    event_loop_test_agent_runtime(),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_loop_test_channels(),
    event_loop_test_users(),
  )

  let results = loop_.process_workspace(
    runtime,
    adapter,
    mom,
    "2026-04-16T12:05:00.000Z",
  ).unwrap()

  assert_eq(results.length(), 2)
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(loop_.list_one_shot_timers().length(), 1)
  assert_eq(event_workspace.val.list_files("/workspace/events").unwrap().length(), 1)
  assert_eq(event_workspace.val.list_files("/workspace/events").unwrap()[0], "/workspace/events/future.json")
}

test "event loop flush_due_one_shots dispatches due timers and cleans files" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z")
  let event_workspace = test_loop_workspace([
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let runtime = test_loop_runtime(event_workspace)
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_loop_test_model(),
    event_loop_test_agent_runtime(),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_loop_test_channels(),
    event_loop_test_users(),
  )

  ignore(loop_.sync_workspace(runtime, "2026-04-17T09:00:00+08:00").unwrap())
  let results = loop_.flush_due_one_shots(
    runtime,
    adapter,
    mom,
    "2026-04-17T10:00:00+08:00",
  ).unwrap()

  assert_eq(results.length(), 1)
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(loop_.list_one_shot_timers().length(), 0)
  assert_eq(event_workspace.val.list_files("/workspace/events").unwrap().length(), 0)
}

test "event loop next_due_at_ms returns earliest pending wakeup" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z", debounce_ms=100UL)
  let event_workspace = test_loop_workspace([
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let runtime = test_loop_runtime(event_workspace)

  assert_eq(loop_.next_due_at_ms(), None)
  loop_.note_file_change("pending.json", 1_000UL)
  ignore(loop_.sync_workspace(runtime, "2026-04-17T09:00:00+08:00").unwrap())

  assert_eq(loop_.next_due_at_ms(), Some(1_100UL))
  ignore(loop_.flush_due_file_changes(1_100UL))
  assert_eq(
    loop_.next_due_at_ms(),
    Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
  )
}

test "event loop tick processes due workspace file changes" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z", debounce_ms=100UL)
  let event_workspace = test_loop_workspace([
    (
      "/workspace/events/immediate.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"ping\"}",
      Some("2026-04-16T12:04:59.950Z"),
    ),
  ])
  let runtime = test_loop_runtime(event_workspace)
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_loop_test_model(),
    event_loop_test_agent_runtime(),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_loop_test_channels(),
    event_loop_test_users(),
  )
  loop_.note_file_change(
    "immediate.json",
    parse_mom_timestamp_ms("2026-04-16T12:04:59.900Z").unwrap(),
  )

  let result = loop_.tick(runtime, adapter, mom, "2026-04-16T12:05:00.000Z").unwrap()

  assert_eq(result.flushed_files, ["immediate.json"])
  assert_eq(result.workspace_results.length(), 1)
  assert_eq(result.one_shot_results.length(), 0)
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(event_workspace.val.list_files("/workspace/events").unwrap().length(), 0)
}

test "event loop tick flushes due one-shot timers without workspace changes" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z")
  let event_workspace = test_loop_workspace([
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let runtime = test_loop_runtime(event_workspace)
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_loop_test_model(),
    event_loop_test_agent_runtime(),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_loop_test_channels(),
    event_loop_test_users(),
  )

  ignore(loop_.sync_workspace(runtime, "2026-04-17T09:00:00+08:00").unwrap())
  let result = loop_.tick(runtime, adapter, mom, "2026-04-17T10:00:00+08:00").unwrap()

  assert_eq(result.flushed_files.length(), 0)
  assert_eq(result.workspace_results.length(), 0)
  assert_eq(result.one_shot_results.length(), 1)
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(loop_.list_one_shot_timers().length(), 0)
  assert_eq(event_workspace.val.list_files("/workspace/events").unwrap().length(), 0)
}

test "event loop forwards debounce queue operations" {
  let loop_ = MomEventLoop::new("/workspace", "2026-04-16T12:00:00Z", debounce_ms=100UL)

  loop_.note_file_change("a.json", 1_000UL)
  loop_.note_file_change("b.json", 1_050UL)

  assert_eq(loop_.list_pending_file_changes().length(), 2)
  assert_true(loop_.clear_file_change("a.json"))
  assert_eq(loop_.flush_due_file_changes(1_149UL).length(), 0)
  assert_eq(loop_.flush_due_file_changes(1_150UL), ["b.json"])
}
