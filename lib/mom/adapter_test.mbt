fn adapter_test_model() -> @ai.Model {
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

fn adapter_test_workspace() -> Ref[@coding_agent.InMemoryWorkspace] {
  Ref::new(@coding_agent.InMemoryWorkspace::new())
}

fn adapter_test_runtime(
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
    stream_fn=Some(adapter_test_stream_fn()),
  )
}

fn adapter_test_stream_fn() -> @agent.AgentStreamFn {
  @agent.AgentStreamFn(fn(model, context, _options, handler) {
    let text = adapter_test_latest_user_text(context.messages).unwrap_or("(none)")
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

fn adapter_test_latest_user_text(messages : Array[@ai.Message]) -> String? {
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

fn adapter_test_channels() -> Array[ChannelInfo] {
  [{ id: "C123", name: "build", kind: ChannelKind::Channel }]
}

fn adapter_test_users() -> Array[UserInfo] {
  [{ id: "U1", username: "mario", display_name: Some("Mario") }]
}

fn adapter_test_message(text : String) -> ChannelMessage {
  {
    id: "m1",
    channel_id: "C123",
    timestamp: "2026-04-16T12:00:00.000Z",
    sender: { id: "U1", username: "mario", display_name: Some("Mario"), is_bot: false },
    text,
    raw_text: None,
    attachments: [],
    is_mention: true,
    reply_to: Some("thread-1"),
    metadata: None,
  }
}

test "run_mom_turn_with_adapter sends assistant reply and forwards agent events" {
  let workspace = adapter_test_workspace()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    adapter_test_model(),
    adapter_test_runtime(workspace),
  ))
  let adapter = InMemoryPlatformAdapter::new(
    "slack-acme",
    adapter_test_channels(),
    adapter_test_users(),
  )

  let result = run_mom_turn_with_adapter(
    adapter,
    mom,
    adapter_test_message("hello"),
  ).unwrap()

  assert_eq(result.assistant_text, "echo:[mario]: hello")
  assert_eq(adapter.sent_messages.length(), 1)
  assert_eq(adapter.sent_messages[0].channel_id, "C123")
  assert_eq(adapter.sent_messages[0].reply_to, Some("thread-1"))
  assert_eq(adapter.sent_messages[0].text, "echo:[mario]: hello")
  assert_true(adapter.observed_events.contains("message_start"))
  assert_true(adapter.observed_events.contains("message_end"))
}

struct FailingPlatformAdapter {
  adapter_name : String
  channels : Array[ChannelInfo]
  users : Array[UserInfo]
}

pub impl PlatformAdapter for FailingPlatformAdapter with name(self) {
  self.adapter_name
}

pub impl PlatformAdapter for FailingPlatformAdapter with get_channels(self) {
  self.channels.copy()
}

pub impl PlatformAdapter for FailingPlatformAdapter with get_users(self) {
  self.users.copy()
}

pub impl PlatformAdapter for FailingPlatformAdapter with send_message(_self, _outbound) {
  Err("send failed")
}

test "run_mom_turn_with_adapter surfaces adapter send failures" {
  let workspace = adapter_test_workspace()
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    adapter_test_model(),
    adapter_test_runtime(workspace),
  ))
  let adapter : FailingPlatformAdapter = {
    adapter_name: "slack-acme",
    channels: adapter_test_channels(),
    users: adapter_test_users(),
  }

  let result = run_mom_turn_with_adapter(
    adapter,
    mom,
    adapter_test_message("hello"),
  )

  match result {
    Err(AdapterFailed("send failed")) => ()
    _ => fail("expected adapter failure")
  }
}
