fn test_model() -> @ai.Model {
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

fn test_assistant_message(
  content : Array[@ai.ContentBlock],
  stop_reason? : @ai.StopReason = @ai.StopReason::Stop,
  error_message? : String? = None
) -> @ai.AssistantMessage {
  {
    content,
    api: @ai.api_openai_responses,
    provider: @ai.provider_openai,
    model: "mock",
    usage: @ai.Usage::zero(),
    stop_reason,
    error_message,
    timestamp: 0.0,
  }
}

fn test_user_message(text : String) -> @ai.Message {
  @ai.Message::User({ content: [@ai.ContentBlock::Text(text)] })
}

fn test_event_name(event : AgentEvent) -> String {
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

test "run_agent_loop returns prompt and assistant message" {
  let events : Array[AgentEvent] = []
  let config = AgentLoopConfig::new(
    test_model(),
    options=@ai.StreamOptions::default(),
  )
  config.stream_fn = Some(AgentStreamFn(fn(_model, _context, _options, handler) {
    let partial = test_assistant_message([])
    let done_message = test_assistant_message([@ai.ContentBlock::Text("hi")])
    handler.0(@ai.AssistantMessageEvent::Start(partial))
    handler.0(@ai.AssistantMessageEvent::TextStart(0))
    handler.0(@ai.AssistantMessageEvent::TextDelta(0, "hi"))
    handler.0(@ai.AssistantMessageEvent::TextEnd(0, "hi"))
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, done_message))
    Ok(())
  }))
  let result = run_agent_loop(
    [test_user_message("hello")],
    { system_prompt: "", messages: [], tools: [] },
    config,
    fn(event) { events.push(event) },
  )
  assert_true(result is Ok(_))
  let messages = result.unwrap()
  assert_eq(messages.length(), 2)
  match messages[1] {
    @ai.Message::Assistant(message) =>
      match message.content[0] {
        @ai.ContentBlock::Text(text) => assert_eq(text, "hi")
        _ => fail("expected text content")
      }
    _ => fail("expected assistant message")
  }
  assert_eq(test_event_name(events[0]), "agent_start")
  assert_eq(test_event_name(events[events.length() - 1]), "agent_end")
}

test "run_agent_loop executes tool call and feeds tool result into next turn" {
  let executed : Ref[String?] = Ref::new(None)
  let tool : AgentTool = {
    name: "echo",
    label: "Echo",
    description: "Echo text",
    parameters: Json::object({}),
    prepare_arguments: None,
    validate_arguments: None,
    execute: fn(_tool_call_id, args, _on_update) {
      guard args is Object({ "value": String(value), .. }) else {
        return Err("missing value")
      }
      executed.val = Some(value)
      Ok({
        content: [@ai.ContentBlock::Text("echoed: " + value)],
        details: Json::object({ "value": Json::string(value) }),
      })
    },
  }
  let call_index : Ref[Int] = Ref::new(0)
  let config = AgentLoopConfig::new(test_model())
  config.stream_fn = Some(AgentStreamFn(fn(_model, _context, _options, handler) {
    if call_index.val == 0 {
      let tool_call = @ai.ToolCall::{ id: "tool-1", name: "echo", arguments: {
        "value": Json::string("hello"),
      } }
      let message = test_assistant_message(
        [@ai.ContentBlock::ToolCall(tool_call)],
        stop_reason=@ai.StopReason::ToolUse,
      )
      handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::ToolUse, message))
    } else {
      let message = test_assistant_message([@ai.ContentBlock::Text("done")])
      handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    }
    call_index.val = call_index.val + 1
    Ok(())
  }))
  let result = run_agent_loop(
    [test_user_message("echo")],
    { system_prompt: "", messages: [], tools: [tool] },
    config,
    fn(_event) { },
  )
  assert_true(result is Ok(_))
  assert_eq(executed.val, Some("hello"))
  let messages = result.unwrap()
  assert_eq(messages.length(), 4)
  match messages[2] {
    @ai.Message::ToolResult(message) => {
      assert_true(message.error == false)
      match message.content[0] {
        @ai.ContentBlock::Text(text) => assert_eq(text, "echoed: hello")
        _ => fail("expected tool result text")
      }
    }
    _ => fail("expected tool result message")
  }
}

test "before_tool_call can block tool execution" {
  let executed : Ref[Bool] = Ref::new(false)
  let tool : AgentTool = {
    name: "echo",
    label: "Echo",
    description: "Echo text",
    parameters: Json::object({}),
    prepare_arguments: None,
    validate_arguments: None,
    execute: fn(_tool_call_id, _args, _on_update) {
      executed.val = true
      Ok({
        content: [@ai.ContentBlock::Text("should not run")],
        details: empty_json_object(),
      })
    },
  }
  let call_index : Ref[Int] = Ref::new(0)
  let config = AgentLoopConfig::new(test_model())
  config.before_tool_call = Some(fn(_context) { Some(BeforeToolCallResult::block(reason="blocked")) })
  config.stream_fn = Some(AgentStreamFn(fn(_model, _context, _options, handler) {
    if call_index.val == 0 {
      let tool_call = @ai.ToolCall::{ id: "tool-1", name: "echo", arguments: {} }
      let message = test_assistant_message(
        [@ai.ContentBlock::ToolCall(tool_call)],
        stop_reason=@ai.StopReason::ToolUse,
      )
      handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::ToolUse, message))
    } else {
      let message = test_assistant_message([@ai.ContentBlock::Text("done")])
      handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    }
    call_index.val = call_index.val + 1
    Ok(())
  }))
  let result = run_agent_loop(
    [test_user_message("echo")],
    { system_prompt: "", messages: [], tools: [tool] },
    config,
    fn(_event) { },
  )
  assert_true(result is Ok(_))
  assert_false(executed.val)
  let messages = result.unwrap()
  match messages[2] {
    @ai.Message::ToolResult(message) => {
      assert_true(message.error)
      match message.content[0] {
        @ai.ContentBlock::Text(text) => assert_eq(text, "blocked")
        _ => fail("expected blocked tool text")
      }
    }
    _ => fail("expected tool result message")
  }
}
