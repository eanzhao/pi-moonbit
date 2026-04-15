fn agent_test_model() -> @ai.Model {
  {
    id: "mock",
    name: "mock",
    api: @ai.api_openai_responses,
    provider: @ai.provider_openai,
    base_url: None,
    reasoning: false,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 8192,
    max_tokens: 2048,
  }
}

fn agent_test_assistant_message(
  text : String,
  stop_reason? : @ai.StopReason = @ai.StopReason::Stop,
  error_message? : String? = None
) -> @ai.AssistantMessage {
  {
    content: [@ai.ContentBlock::Text(text)],
    api: @ai.api_openai_responses,
    provider: @ai.provider_openai,
    model: "mock",
    usage: @ai.Usage::zero(),
    stop_reason,
    error_message,
    timestamp: 0.0,
  }
}

fn agent_test_user_message(text : String) -> @ai.Message {
  @ai.Message::User({ content: [@ai.ContentBlock::Text(text)] })
}

fn agent_test_event_name(event : AgentEvent) -> String {
  match event {
    AgentStart => "agent_start"
    AgentEnd(_) => "agent_end"
    TurnStart => "turn_start"
    TurnEnd(_) => "turn_end"
    MessageStart(_) => "message_start"
    MessageUpdate(_) => "message_update"
    MessageEnd(_) => "message_end"
    ToolExecutionStart(_) => "tool_execution_start"
    ToolExecutionUpdate(_) => "tool_execution_update"
    ToolExecutionEnd(_) => "tool_execution_end"
  }
}

test "agent prompt_text updates transcript and emits events" {
  let agent = Agent::new(model=agent_test_model())
  agent.set_stream_fn(AgentStreamFn(fn(_model, _context, _options, handler) {
    let message = agent_test_assistant_message("ok")
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    Ok(())
  }))
  let events : Array[String] = []
  let _ = agent.subscribe(fn(event) { events.push(agent_test_event_name(event)) })
  let result = agent.prompt_text("hello")
  assert_true(result is Ok(_))
  assert_false(agent.state.is_streaming)
  assert_eq(agent.state.messages.length(), 2)
  assert_eq(events[0], "agent_start")
  assert_eq(events[events.length() - 1], "agent_end")
}

test "agent continue_run consumes queued steering message after assistant tail" {
  let agent = Agent::new(
    model=agent_test_model(),
    messages=[
      agent_test_user_message("first"),
      @ai.Message::Assistant(agent_test_assistant_message("done")),
    ],
  )
  agent.set_stream_fn(AgentStreamFn(fn(_model, _context, _options, handler) {
    let message = agent_test_assistant_message("continued")
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    Ok(())
  }))
  agent.steer(agent_test_user_message("next"))
  let result = agent.continue_run()
  assert_true(result is Ok(_))
  assert_eq(agent.state.messages.length(), 4)
  match agent.state.messages[2] {
    @ai.Message::User(message) =>
      match message.content[0] {
        @ai.ContentBlock::Text(text) => assert_eq(text, "next")
        _ => fail("expected user steering text")
      }
    _ => fail("expected queued steering user message")
  }
}

test "agent records stream failure as assistant error message" {
  let agent = Agent::new(model=agent_test_model())
  agent.set_stream_fn(AgentStreamFn(fn(_model, _context, _options, _handler) { Err("boom") }))
  let result = agent.prompt_text("hello")
  assert_true(result is Ok(_))
  assert_eq(agent.state.error_message, Some("boom"))
  assert_eq(agent.state.messages.length(), 2)
  match agent.state.messages[1] {
    @ai.Message::Assistant(message) => {
      assert_eq(message.stop_reason, @ai.StopReason::Error)
      assert_eq(message.error_message, Some("boom"))
    }
    _ => fail("expected assistant error message")
  }
}
