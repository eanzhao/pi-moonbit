// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn slack_test_channels() -> Array[ChannelInfo] {
  [
    { id: "C100", name: "general", kind: ChannelKind::Channel },
    { id: "C200", name: "engineering", kind: ChannelKind::Channel },
  ]
}

fn slack_test_users() -> Array[UserInfo] {
  [
    { id: "U1", username: "alice", display_name: Some("Alice") },
    { id: "U2", username: "bob", display_name: None },
  ]
}

fn slack_test_message(text : String) -> ChannelMessage {
  {
    id: "m-slack-1",
    channel_id: "C100",
    timestamp: "2026-04-15T10:00:00.000Z",
    sender: { id: "U1", username: "alice", display_name: Some("Alice"), is_bot: false },
    text,
    raw_text: None,
    attachments: [],
    is_mention: true,
    reply_to: None,
    metadata: None,
  }
}

// ---------------------------------------------------------------------------
// Tests — SlackPlatformAdapter basics
// ---------------------------------------------------------------------------

test "SlackPlatformAdapter::new stores config and adapter_name" {
  let adapter = SlackPlatformAdapter::new("xapp-tok", "xoxb-tok")
  assert_eq(adapter.adapter_name, "slack")
  assert_eq(adapter.config.app_token, "xapp-tok")
  assert_eq(adapter.config.bot_token, "xoxb-tok")
  assert_eq(adapter.config.base_url, "https://slack.com/api")
  assert_eq(adapter.connected, false)
}

test "SlackPlatformAdapter custom adapter_name and base_url" {
  let adapter = SlackPlatformAdapter::new(
    "xapp-tok",
    "xoxb-tok",
    base_url="http://localhost:9999",
    adapter_name="slack-acme",
  )
  assert_eq(adapter.adapter_name, "slack-acme")
  assert_eq(adapter.config.base_url, "http://localhost:9999")
}

test "SlackPlatformAdapter::connect returns stub error" {
  let adapter = SlackPlatformAdapter::new("xapp-tok", "xoxb-tok")
  match adapter.connect() {
    Err(message) => assert_true(message.contains("not yet implemented"))
    Ok(_) => fail("expected connect to fail as a stub")
  }
}

test "SlackPlatformAdapter start/stop toggles connected flag" {
  let adapter = SlackPlatformAdapter::new("xapp-tok", "xoxb-tok")
  assert_eq(adapter.connected, false)
  adapter.start()
  assert_eq(adapter.connected, true)
  adapter.stop()
  assert_eq(adapter.connected, false)
}

test "SlackPlatformAdapter PlatformAdapter::name returns adapter_name" {
  let adapter = SlackPlatformAdapter::new("a", "b", adapter_name="slack-test")
  let name : String = adapter.name()
  assert_eq(name, "slack-test")
}

test "SlackPlatformAdapter get_channels and get_users with metadata" {
  let adapter = slack_adapter_with_metadata(
    "a",
    "b",
    slack_test_channels(),
    slack_test_users(),
  )
  let channels = adapter.get_channels()
  assert_eq(channels.length(), 2)
  assert_eq(channels[0].id, "C100")
  assert_eq(channels[1].name, "engineering")
  let users = adapter.get_users()
  assert_eq(users.length(), 2)
  assert_eq(users[0].username, "alice")
  assert_eq(users[1].display_name, None)
}

test "SlackPlatformAdapter send_message records sent messages" {
  let adapter = slack_adapter_with_metadata(
    "a",
    "b",
    slack_test_channels(),
    slack_test_users(),
  )
  adapter.start()
  let outbound : AdapterOutboundMessage = {
    channel_id: "C100",
    text: "hello from adapter",
    reply_to: Some("thread-1"),
  }
  let sent = adapter.send_message(outbound).unwrap()
  assert_eq(sent.channel_id, "C100")
  assert_eq(sent.text, "hello from adapter")
  assert_eq(sent.reply_to, Some("thread-1"))
  assert_eq(adapter.sent_messages.length(), 1)
}

test "SlackPlatformAdapter disconnect resets connected" {
  let adapter = SlackPlatformAdapter::new("a", "b")
  adapter.start()
  assert_eq(adapter.connected, true)
  adapter.disconnect()
  assert_eq(adapter.connected, false)
}

// ---------------------------------------------------------------------------
// Tests — Slack adapter works with run_mom_turn_with_adapter
// ---------------------------------------------------------------------------

test "run_mom_turn_with_adapter works with SlackPlatformAdapter" {
  let workspace = Ref::new(@coding_agent.InMemoryWorkspace::new())
  let runtime = MomAgentRuntime::new(
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
    now_iso=fn() { "2026-04-15T12:00:00.000Z" },
    stream_fn=Some(slack_test_stream_fn()),
  )
  let model : @ai.Model = {
    id: "mock-slack",
    name: "mock-slack",
    api: @ai.ApiId("mock"),
    provider: @ai.ProviderId("mock"),
    base_url: None,
    reasoning: false,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 8192,
    max_tokens: 2048,
  }
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    model,
    runtime,
  ))
  let adapter = slack_adapter_with_metadata(
    "xapp-tok",
    "xoxb-tok",
    slack_test_channels(),
    slack_test_users(),
  )
  let result = run_mom_turn_with_adapter(
    adapter,
    mom,
    slack_test_message("ping"),
  ).unwrap()
  assert_eq(result.assistant_text, "echo:[alice]: ping")
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(adapter.sent_messages[0].channel_id, "C100")
}

fn slack_test_stream_fn() -> @agent.AgentStreamFn {
  @agent.AgentStreamFn(fn(model, context, _options, handler) {
    let text = slack_test_latest_user_text(context.messages).unwrap_or("(none)")
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

fn slack_test_latest_user_text(messages : Array[@ai.Message]) -> String? {
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
