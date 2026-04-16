fn mom_test_model() -> @ai.Model {
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

fn mom_test_runtime() -> MomAgentRuntime {
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
    stream_fn=Some(mom_test_stream_fn()),
  )
}

fn mom_test_stream_fn() -> @agent.AgentStreamFn {
  @agent.AgentStreamFn(fn(model, context, _options, handler) {
    let text = latest_mom_user_text(context.messages).unwrap_or("(none)")
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

fn latest_mom_user_text(messages : Array[@ai.Message]) -> String? {
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

fn mom_test_context() -> ChannelContext {
  {
    adapter: "slack-acme",
    channels: [{ id: "C123", name: "build", kind: ChannelKind::Channel }],
    users: [{ id: "U1", username: "mario", display_name: Some("Mario") }],
  }
}

fn mom_test_message_for_agent(id : String, text : String) -> ChannelMessage {
  {
    id,
    channel_id: "C123",
    timestamp: "2026-04-16T12:00:00.000Z",
    sender: { id: "U1", username: "mario", display_name: Some("Mario"), is_bot: false },
    text,
    raw_text: None,
    attachments: [],
    is_mention: true,
    reply_to: None,
    metadata: None,
  }
}

test "mom agent handle_message creates session emits events and appends bot log" {
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    mom_test_model(),
    mom_test_runtime(),
    global_memory=Some("Use apply_patch."),
  ))
  let events : Ref[Array[String]] = Ref::new([])
  let result = mom.handle_message(
    mom_test_message_for_agent("m1", "hello"),
    mom_test_context(),
    on_event=Some(fn(event) {
      events.val.push(mom_agent_test_event_name(event))
    }),
  ).unwrap()

  assert_eq(result.stop_reason, @ai.StopReason::Stop)
  assert_eq(result.assistant_text, "echo:[mario]: hello")
  assert_true(events.val.contains("message_start"))
  assert_true(events.val.contains("message_end"))

  let log = mom.channel_store.get_log("slack-acme", "C123")
  assert_eq(log.length(), 2)
  assert_true(log[1].sender.is_bot)
  assert_eq(log[1].text, "echo:[mario]: hello")
}

test "mom agent syncs prior log messages into session context before current prompt" {
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    mom_test_model(),
    mom_test_runtime(),
  ))
  ignore(mom.channel_store.append_message("slack-acme", mom_test_message_for_agent("m0", "previous")))

  let result = mom.handle_message(
    mom_test_message_for_agent("m1", "current"),
    mom_test_context(),
  ).unwrap()

  assert_eq(result.assistant_text, "echo:[mario]: current")

  let session = mom.get_session("slack-acme/C123").unwrap()
  let transcript = session.val.session.session_manager.build_transcript_messages()
  assert_eq(transcript.length(), 3)
  match transcript[0] {
    @ai.Message::User(message) =>
      match message.content[0] {
        @ai.ContentBlock::Text(text) => assert_eq(text, "[mario]: previous")
        _ => fail("expected text")
      }
    _ => fail("expected user")
  }
}

test "mom agent exposes running state during callback and clears it afterwards" {
  let mom = MomAgent::new(MomAgentConfig::new(
    "/workspace",
    SandboxConfig::Host,
    mom_test_model(),
    mom_test_runtime(),
  ))
  let saw_running = Ref::new(false)

  let _ = mom.handle_message(
    mom_test_message_for_agent("m1", "hello"),
    mom_test_context(),
    on_event=Some(fn(_event) {
      if mom.is_running("slack-acme/C123") {
        saw_running.val = true
      }
    }),
  )

  assert_true(saw_running.val)
  assert_true(!mom.is_running("slack-acme/C123"))
}

fn mom_agent_test_event_name(event : @agent.AgentEvent) -> String {
  match event {
    @agent.AgentEvent::AgentStart => "agent_start"
    @agent.AgentEvent::AgentEnd(_) => "agent_end"
    @agent.AgentEvent::TurnStart => "turn_start"
    @agent.AgentEvent::TurnEnd(_) => "turn_end"
    @agent.AgentEvent::MessageStart(_) => "message_start"
    @agent.AgentEvent::MessageUpdate(_) => "message_update"
    @agent.AgentEvent::MessageEnd(_) => "message_end"
    @agent.AgentEvent::ToolExecutionStart(_) => "tool_execution_start"
    @agent.AgentEvent::ToolExecutionUpdate(_) => "tool_execution_update"
    @agent.AgentEvent::ToolExecutionEnd(_) => "tool_execution_end"
  }
}
