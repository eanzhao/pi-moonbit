struct TestEventWorkspace {
  mut files : Array[(String, String, String?)]
}

fn TestEventWorkspace::read_text(self : TestEventWorkspace, path : String) -> Result[String, String] {
  for item in self.files {
    let (file_path, content, _modified_at) = item
    if file_path == path {
      return Ok(content)
    }
  }
  Err("missing file: " + path)
}

fn TestEventWorkspace::list_files(
  self : TestEventWorkspace,
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

fn TestEventWorkspace::read_modified_at(
  self : TestEventWorkspace,
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

fn TestEventWorkspace::delete_file(
  self : TestEventWorkspace,
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

fn test_event_workspace(
  files : Array[(String, String, String?)]
) -> Ref[TestEventWorkspace] {
  Ref::new({ files: files })
}

fn test_event_workspace_runtime(
  workspace : Ref[TestEventWorkspace]
) -> MomEventWorkspaceRuntime {
  MomEventWorkspaceRuntime::new(
    fn(path) { workspace.val.read_text(path) },
    fn(dir) { workspace.val.list_files(dir) },
    read_modified_at=fn(path) { workspace.val.read_modified_at(path) },
    delete_file=fn(path) { workspace.val.delete_file(path) },
  )
}

fn event_host_test_model() -> @ai.Model {
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

fn event_host_test_workspace() -> Ref[@coding_agent.InMemoryWorkspace] {
  Ref::new(@coding_agent.InMemoryWorkspace::new())
}

fn event_host_test_runtime(
  workspace : Ref[@coding_agent.InMemoryWorkspace]
) -> MomAgentRuntime {
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
    stream_fn=Some(event_host_test_stream_fn()),
  )
}

fn event_host_test_stream_fn() -> @agent.AgentStreamFn {
  @agent.AgentStreamFn(fn(model, context, _options, handler) {
    let text = event_host_test_latest_user_text(context.messages).unwrap_or("(none)")
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

fn event_host_test_latest_user_text(messages : Array[@ai.Message]) -> String? {
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

fn event_host_test_channels() -> Array[ChannelInfo] {
  [{ id: "C123", name: "build", kind: ChannelKind::Channel }]
}

fn event_host_test_users() -> Array[UserInfo] {
  [{ id: "U1", username: "mario", display_name: Some("Mario") }]
}

test "load_workspace_mom_event_files filters json files and sorts filenames" {
  let workspace = test_event_workspace([
    (
      "/workspace/events/b.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"b\"}",
      Some("2026-04-16T12:00:02Z"),
    ),
    (
      "/workspace/events/a.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"a\"}",
      Some("2026-04-16T12:00:01Z"),
    ),
    ("/workspace/events/notes.txt", "ignore", None),
  ])
  let runtime = test_event_workspace_runtime(workspace)

  let files = load_workspace_mom_event_files(runtime, "/workspace").unwrap()

  assert_eq(files.length(), 2)
  assert_eq(files[0].filename, "a.json")
  assert_eq(files[0].modified_at, Some("2026-04-16T12:00:01Z"))
  assert_eq(files[1].filename, "b.json")
  assert_eq(files[1].modified_at, Some("2026-04-16T12:00:02Z"))
}

test "plan_workspace_mom_events uses workspace file metadata" {
  let workspace = test_event_workspace([
    (
      "/workspace/events/a.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"stale\"}",
      Some("2026-04-16T11:59:59Z"),
    ),
    (
      "/workspace/events/b.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let runtime = test_event_workspace_runtime(workspace)

  let plans = plan_workspace_mom_events(
    runtime,
    "/workspace",
    "2026-04-16T12:00:00Z",
    "2026-04-16T12:05:00Z",
  ).unwrap()

  assert_eq(plans.length(), 2)
  match plans[0] {
    Delete(filename) => assert_eq(filename, "a.json")
    _ => fail("expected delete")
  }
  match plans[1] {
    ScheduleOneShot(value) => assert_eq(value.filename, "b.json")
    _ => fail("expected schedule")
  }
}

test "event_trigger_to_channel_message validates qualified channel ids" {
  let message = event_trigger_to_channel_message(
    {
      filename: "daily.json",
      event: Immediate({ channel_id: "slack-acme/C123", text: "ping" }),
      message: "[EVENT:daily.json:immediate] ping",
      delete_after: true,
    },
    "slack-acme",
    "2026-04-16T12:00:00.000Z",
  ).unwrap()

  assert_eq(message.channel_id, "C123")
  assert_eq(message.sender.username, "event")
  assert_eq(message.text, "[EVENT:daily.json:immediate] ping")
  assert_eq(message.raw_text, Some("[EVENT:daily.json:immediate] ping"))

  let invalid = event_trigger_to_channel_message(
    {
      filename: "bad.json",
      event: Immediate({ channel_id: "C123", text: "ping" }),
      message: "[EVENT:bad.json:immediate] ping",
      delete_after: true,
    },
    "slack-acme",
    "2026-04-16T12:00:00.000Z",
  )
  match invalid {
    Err(InvalidChannelId("C123")) => ()
    _ => fail("expected invalid channel id")
  }
}

test "dispatch_mom_event_plan_with_adapter runs trigger plans through mom" {
  let workspace = event_host_test_workspace()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_host_test_model(),
    event_host_test_runtime(workspace),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_host_test_channels(),
    event_host_test_users(),
  )

  let result = dispatch_mom_event_plan_with_adapter(
    adapter,
    mom,
    Trigger({
      filename: "daily.json",
      event: Immediate({ channel_id: "slack-acme/C123", text: "ping" }),
      message: "[EVENT:daily.json:immediate] ping",
      delete_after: true,
    }),
    "2026-04-16T12:00:00.000Z",
  ).unwrap()

  match result {
    Triggered(run_result) => {
      assert_eq(run_result.assistant_text, "echo:[event]: [EVENT:daily.json:immediate] ping")
      assert_eq(adapter.sent_messages.length(), 1)
      assert_eq(adapter.sent_messages[0].channel_id, "C123")
      assert_eq(adapter.sent_messages[0].text, "echo:[event]: [EVENT:daily.json:immediate] ping")
    }
    _ => fail("expected triggered result")
  }
}

test "dispatch_mom_event_plan_with_adapter rejects mismatched adapters" {
  let workspace = event_host_test_workspace()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_host_test_model(),
    event_host_test_runtime(workspace),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_host_test_channels(),
    event_host_test_users(),
  )

  let result = dispatch_mom_event_plan_with_adapter(
    adapter,
    mom,
    Trigger({
      filename: "daily.json",
      event: Immediate({ channel_id: "discord/C123", text: "ping" }),
      message: "[EVENT:daily.json:immediate] ping",
      delete_after: true,
    }),
    "2026-04-16T12:00:00.000Z",
  )

  match result {
    Err(AdapterMismatch(message)) => assert_true(message.contains("discord"))
    _ => fail("expected adapter mismatch")
  }
}

test "event host poll suppresses unchanged plans and tracks periodic registrations" {
  let workspace = test_event_workspace([
    (
      "/workspace/events/a.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"ping\"}",
      Some("2026-04-16T12:00:01Z"),
    ),
    (
      "/workspace/events/b.json",
      "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"check\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      None,
    ),
  ])
  let runtime = test_event_workspace_runtime(workspace)
  let host = MomEventHost::new("/workspace", "2026-04-16T12:00:00Z")

  let first = host.poll(runtime, "2026-04-16T12:05:00Z").unwrap()
  assert_eq(first.length(), 2)
  match first[0] {
    Trigger(_) => ()
    _ => fail("expected trigger")
  }
  match first[1] {
    RegisterPeriodic(_) => ()
    _ => fail("expected periodic registration")
  }
  assert_eq(host.list_registered_periodics().length(), 1)

  let second = host.poll(runtime, "2026-04-16T12:05:00Z").unwrap()
  assert_eq(second.length(), 0)
  assert_eq(host.list_registered_periodics().length(), 1)
}

test "event host poll promotes scheduled one-shot to trigger when due" {
  let workspace = test_event_workspace([
    (
      "/workspace/events/reminder.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"remind\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let runtime = test_event_workspace_runtime(workspace)
  let host = MomEventHost::new("/workspace", "2026-04-16T12:00:00Z")

  let first = host.poll(runtime, "2026-04-17T09:00:00+08:00").unwrap()
  assert_eq(first.length(), 1)
  match first[0] {
    ScheduleOneShot(value) => assert_eq(value.filename, "reminder.json")
    _ => fail("expected one-shot scheduling")
  }
  assert_eq(host.list_scheduled_one_shots().length(), 1)

  let second = host.poll(runtime, "2026-04-17T10:00:00+08:00").unwrap()
  assert_eq(second.length(), 1)
  match second[0] {
    Trigger(value) => assert_eq(value.filename, "reminder.json")
    _ => fail("expected trigger")
  }
  assert_eq(host.list_scheduled_one_shots().length(), 0)

  let third = host.poll(runtime, "2026-04-17T10:00:00+08:00").unwrap()
  assert_eq(third.length(), 0)
}

test "event host poll_sync reports added and removed timer registry entries" {
  let event_workspace = test_event_workspace([
    (
      "/workspace/events/daily.json",
      "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"check\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      None,
    ),
    (
      "/workspace/events/reminder.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"remind\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let runtime = test_event_workspace_runtime(event_workspace)
  let host = MomEventHost::new("/workspace", "2026-04-16T12:00:00Z")

  let first = host.poll_sync(runtime, "2026-04-17T09:00:00+08:00").unwrap()
  assert_eq(first.changed_plans.length(), 2)
  assert_eq(first.added_one_shots.length(), 1)
  assert_eq(first.removed_one_shots.length(), 0)
  assert_eq(first.added_periodics.length(), 1)
  assert_eq(first.removed_periodics.length(), 0)
  assert_eq(first.added_one_shots[0].filename, "reminder.json")
  assert_eq(first.added_periodics[0].event.schedule, "0 9 * * 1-5")

  event_workspace.val.files = [
    (
      "/workspace/events/daily.json",
      "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"check\",\"schedule\":\"0 10 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      None,
    ),
  ]

  let second = host.poll_sync(runtime, "2026-04-17T09:00:00+08:00").unwrap()
  assert_eq(second.changed_plans.length(), 1)
  assert_eq(second.added_one_shots.length(), 0)
  assert_eq(second.removed_one_shots.length(), 1)
  assert_eq(second.removed_one_shots[0].filename, "reminder.json")
  assert_eq(second.added_periodics.length(), 1)
  assert_eq(second.removed_periodics.length(), 1)
  assert_eq(second.added_periodics[0].event.schedule, "0 10 * * 1-5")
  assert_eq(second.removed_periodics[0].event.schedule, "0 9 * * 1-5")

  let third = host.poll_sync(runtime, "2026-04-17T09:00:00+08:00").unwrap()
  assert_eq(third.changed_plans.length(), 0)
  assert_eq(third.added_one_shots.length(), 0)
  assert_eq(third.removed_one_shots.length(), 0)
  assert_eq(third.added_periodics.length(), 0)
  assert_eq(third.removed_periodics.length(), 0)
}

test "event host poll_and_dispatch suppresses duplicate trigger execution" {
  let event_workspace = test_event_workspace([
    (
      "/workspace/events/daily.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"ping\"}",
      Some("2026-04-16T12:00:01Z"),
    ),
  ])
  let runtime = test_event_workspace_runtime(event_workspace)
  let host = MomEventHost::new("/workspace", "2026-04-16T12:00:00Z")
  let workspace = event_host_test_workspace()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_host_test_model(),
    event_host_test_runtime(workspace),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_host_test_channels(),
    event_host_test_users(),
  )

  let first = host.poll_and_dispatch(
    runtime,
    adapter,
    mom,
    "2026-04-16T12:05:00.000Z",
  ).unwrap()
  assert_eq(first.length(), 1)
  match first[0] {
    Triggered(run_result) => {
      assert_eq(run_result.assistant_text, "echo:[event]: [EVENT:daily.json:immediate] ping")
      assert_eq(adapter.sent_messages.length(), 1)
    }
    _ => fail("expected triggered result")
  }

  let second = host.poll_and_dispatch(
    runtime,
    adapter,
    mom,
    "2026-04-16T12:05:00.000Z",
  ).unwrap()
  assert_eq(second.length(), 0)
  assert_eq(adapter.sent_messages.length(), 1)
}

test "event host poll_dispatch_and_cleanup removes processed event files" {
  let event_workspace = test_event_workspace([
    (
      "/workspace/events/daily.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"ping\"}",
      Some("2026-04-16T12:00:01Z"),
    ),
    (
      "/workspace/events/stale.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"stale\"}",
      Some("2026-04-16T11:59:59Z"),
    ),
  ])
  let runtime = test_event_workspace_runtime(event_workspace)
  let host = MomEventHost::new("/workspace", "2026-04-16T12:00:00Z")
  let workspace = event_host_test_workspace()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    event_host_test_model(),
    event_host_test_runtime(workspace),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    event_host_test_channels(),
    event_host_test_users(),
  )

  let results = host.poll_dispatch_and_cleanup(
    runtime,
    adapter,
    mom,
    "2026-04-16T12:05:00.000Z",
  ).unwrap()
  assert_eq(results.length(), 2)
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(event_workspace.val.list_files("/workspace/events").unwrap().length(), 0)
}
