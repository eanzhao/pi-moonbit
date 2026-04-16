struct TestRunnerWorkspace {
  mut files : Array[(String, String, String?)]
}

fn test_runner_workspace(
  files : Array[(String, String, String?)]
) -> Ref[TestRunnerWorkspace] {
  Ref::new({ files: files })
}

fn test_runner_runtime(
  workspace : Ref[TestRunnerWorkspace]
) -> MomEventWorkspaceRuntime {
  MomEventWorkspaceRuntime::new(
    fn(path) {
      for item in workspace.val.files {
        let (file_path, content, _modified_at) = item
        if file_path == path {
          return Ok(content)
        }
      }
      Err("missing file: " + path)
    },
    fn(dir) {
      let prefix = if dir.has_suffix("/") { dir } else { dir + "/" }
      let listed : Array[String] = []
      for item in workspace.val.files {
        let (path, _content, _modified_at) = item
        if path.has_prefix(prefix) {
          listed.push(path)
        }
      }
      Ok(listed)
    },
    read_modified_at=fn(path) {
      for item in workspace.val.files {
        let (file_path, _content, modified_at) = item
        if file_path == path {
          return Ok(modified_at)
        }
      }
      Err("missing file: " + path)
    },
    delete_file=fn(path) {
      let retained : Array[(String, String, String?)] = []
      let mut removed = false
      for item in workspace.val.files {
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
      workspace.val.files = retained
      Ok(())
    },
  )
}

fn runner_test_model() -> @ai.Model {
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

fn runner_test_agent_runtime() -> MomAgentRuntime {
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
    stream_fn=Some(runner_test_stream_fn()),
  )
}

fn runner_test_stream_fn() -> @agent.AgentStreamFn {
  @agent.AgentStreamFn(fn(model, context, _options, handler) {
    let text = runner_test_latest_user_text(context.messages).unwrap_or("(none)")
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

fn runner_test_latest_user_text(messages : Array[@ai.Message]) -> String? {
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

fn runner_test_channels() -> Array[ChannelInfo] {
  [{ id: "C123", name: "build", kind: ChannelKind::Channel }]
}

fn runner_test_users() -> Array[UserInfo] {
  [{ id: "U1", username: "mario", display_name: Some("Mario") }]
}

fn runner_test_message(text : String) -> ChannelMessage {
  {
    id: "m1",
    channel_id: "C123",
    timestamp: "2026-04-16T12:05:00.000Z",
    sender: { id: "U1", username: "mario", display_name: Some("Mario"), is_bot: false },
    text,
    raw_text: None,
    attachments: [],
    is_mention: true,
    reply_to: Some("thread-1"),
    metadata: None,
  }
}

test "runner sync_handles applies event state into handle runtime" {
  let runner = MomRunner::new("/workspace", "2026-04-16T12:00:00Z")
  let workspace = test_runner_workspace([
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
  let event_runtime = test_runner_runtime(workspace)
  let handle_runtime = InMemoryEventHandleRuntime::new()

  let result = runner.sync_handles(
    event_runtime,
    handle_runtime,
    "2026-04-17T09:00:00+08:00",
  ).unwrap()

  assert_eq(result.sync.changed_plans.length(), 2)
  assert_true(result.handle_plan.has_changes())
  let snapshot = handle_runtime.snapshot()
  assert_eq(snapshot.watched_dir, Some("/workspace/events"))
  assert_eq(
    snapshot.wakeup_due_at_ms,
    Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
  )
  assert_eq(snapshot.registered_periodics.length(), 1)
  assert_eq(snapshot.registered_periodics[0].filename, "daily.json")
}

test "runner handle_message refreshes handles after channel turn" {
  let runner = MomRunner::new("/workspace", "2026-04-16T12:00:00Z")
  let workspace = test_runner_workspace([
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let event_runtime = test_runner_runtime(workspace)
  let handle_runtime = InMemoryEventHandleRuntime::new()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    runner_test_model(),
    runner_test_agent_runtime(),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
  )

  let result = runner.handle_message(
    event_runtime,
    handle_runtime,
    adapter,
    mom,
    runner_test_message("hello"),
  ).unwrap()

  assert_eq(result.run.assistant_text, "echo:[mario]: hello")
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(
    handle_runtime.snapshot().wakeup_due_at_ms,
    Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
  )
}

test "runner tick dispatches due file changes and resyncs handles" {
  let runner = MomRunner::new("/workspace", "2026-04-16T12:00:00Z", debounce_ms=100UL)
  let workspace = test_runner_workspace([
    (
      "/workspace/events/immediate.json",
      "{\"type\":\"immediate\",\"channelId\":\"slack-acme/C123\",\"text\":\"ping\"}",
      Some("2026-04-16T12:04:59.950Z"),
    ),
    (
      "/workspace/events/future.json",
      "{\"type\":\"one-shot\",\"channelId\":\"slack-acme/C123\",\"text\":\"future\",\"at\":\"2026-04-17T10:00:00+08:00\"}",
      None,
    ),
  ])
  let event_runtime = test_runner_runtime(workspace)
  let handle_runtime = InMemoryEventHandleRuntime::new()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    runner_test_model(),
    runner_test_agent_runtime(),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
  )

  runner.note_file_change(
    "immediate.json",
    parse_mom_timestamp_ms("2026-04-16T12:04:59.900Z").unwrap(),
  )
  runner.note_file_change(
    "future.json",
    parse_mom_timestamp_ms("2026-04-16T12:04:59.900Z").unwrap(),
  )
  let result = runner.tick(
    event_runtime,
    handle_runtime,
    adapter,
    mom,
    "2026-04-16T12:05:00.000Z",
  ).unwrap()

  assert_eq(result.tick.flushed_files, ["future.json", "immediate.json"])
  assert_eq(result.tick.workspace_results.length(), 2)
  assert_eq(result.tick.one_shot_results.length(), 0)
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(
    handle_runtime.snapshot().wakeup_due_at_ms,
    Some(parse_mom_timestamp_ms("2026-04-17T10:00:00+08:00").unwrap()),
  )
}

test "runner dispatch_periodic keeps handle state synced" {
  let runner = MomRunner::new("/workspace", "2026-04-16T12:00:00Z")
  let workspace = test_runner_workspace([
    (
      "/workspace/events/daily.json",
      "{\"type\":\"periodic\",\"channelId\":\"slack-acme/C123\",\"text\":\"daily\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
      None,
    ),
  ])
  let event_runtime = test_runner_runtime(workspace)
  let handle_runtime = InMemoryEventHandleRuntime::new()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    runner_test_model(),
    runner_test_agent_runtime(),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    runner_test_channels(),
    runner_test_users(),
  )

  ignore(runner.sync_handles(event_runtime, handle_runtime, "2026-04-16T12:05:00.000Z").unwrap())
  let result = runner.dispatch_periodic(
    event_runtime,
    handle_runtime,
    adapter,
    mom,
    "daily.json",
    "2026-04-16T12:05:00.000Z",
  ).unwrap()

  match result.dispatch {
    Triggered(run) =>
      assert_eq(
        run.assistant_text,
        "echo:[event]: [EVENT:daily.json:periodic:0 9 * * 1-5] daily",
      )
    _ => fail("expected periodic dispatch")
  }
  assert_false(result.handle_plan.has_changes())
}
