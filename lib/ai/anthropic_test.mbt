fn anthropic_test_model() -> Model {
  {
    id: "claude-sonnet-4-20250514",
    name: "Claude Sonnet 4",
    api: api_anthropic_messages,
    provider: provider_anthropic,
    base_url: None,
    reasoning: true,
    input_modalities: [Text, Image],
    cost: { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 },
    context_window: 200_000,
    max_tokens: 8192,
  }
}

fn anthropic_test_options(
  temperature? : Double? = None,
  max_tokens? : Int? = None,
  top_p? : Double? = None,
  thinking_mode? : ThinkingMode? = None,
  thinking_budget_tokens? : Int? = None,
) -> StreamOptions {
  {
    temperature,
    max_tokens,
    top_p,
    api_key: None,
    cache_retention: None,
    retry_count: None,
    retry_delay_ms: None,
    thinking_mode,
    thinking_budget_tokens,
    reasoning: None,
  }
}

fn anthropic_test_assistant_message(
  content : Array[ContentBlock],
  stop_reason? : StopReason = Stop
) -> Message {
  Assistant({
    content,
    api: api_anthropic_messages,
    provider: provider_anthropic,
    model: "claude-sonnet-4-20250514",
    usage: Usage::zero(),
    stop_reason,
    error_message: None,
    timestamp: 0.0,
  })
}

test "build request body with system prompt extracted" {
  let context : Context = {
    system_prompt: Some("You are concise."),
    messages: [User({ content: [Text("Hello")] })],
    tools: [],
  }
  let body = build_anthropic_request_body(
    anthropic_test_model(),
    context,
    anthropic_test_options(
      temperature=Some(0.2),
      max_tokens=Some(256),
      thinking_mode=Some(Enabled),
      thinking_budget_tokens=Some(128),
    ),
  )

  guard body is Object({
    "model": String(model_id),
    "system": String(system_prompt),
    "messages": Array(messages),
    "stream": True,
    "max_tokens": Number(max_tokens, ..),
    "temperature": Number(temperature, ..),
    "thinking": Object({
      "type": String(thinking_type),
      "budget_tokens": Number(thinking_budget, ..),
      ..
    }),
    ..
  }) else {
    fail("expected Anthropic request body object")
  }

  assert_eq(model_id, "claude-sonnet-4-20250514")
  assert_eq(system_prompt, "You are concise.")
  assert_eq(messages.length(), 1)
  assert_eq(max_tokens.to_int(), 256)
  assert_eq(temperature, 0.2)
  assert_eq(thinking_type, "enabled")
  assert_eq(thinking_budget.to_int(), 128)

  guard messages[0] is Object({
    "role": String(role),
    "content": Array(parts),
    ..
  }) else {
    fail("expected Anthropic user message")
  }
  assert_eq(role, "user")
  assert_eq(parts.length(), 1)
  guard parts[0] is Object({
    "type": String(part_type),
    "text": String(text),
    ..
  }) else {
    fail("expected text content part")
  }
  assert_eq(part_type, "text")
  assert_eq(text, "Hello")
}

test "build request body with tool definitions and tool messages" {
  let tool_call : ToolCall = {
    id: "toolu_1",
    name: "lookup_weather",
    arguments: Json::object({ "city": Json::string("Paris") }),
  }
  let context : Context = {
    system_prompt: None,
    messages: [
      anthropic_test_assistant_message([
        Text("Checking weather."),
        ContentBlock::ToolCall(tool_call),
      ], stop_reason=ToolUse),
      ToolResult({
        content: [Text("sunny")],
        tool_call_id: "toolu_1",
        tool_name: "lookup_weather",
        error: false,
      }),
    ],
    tools: [
      {
        name: "lookup_weather",
        description: "Look up weather by city",
        parameters: Json::object({
          "type": Json::string("object"),
          "properties": Json::object({
            "city": Json::object({ "type": Json::string("string") }),
          }),
        }),
      },
    ],
  }

  let body = build_anthropic_request_body(anthropic_test_model(), context, anthropic_test_options())

  guard body is Object({
    "messages": Array(messages),
    "tools": Array(tools),
    ..
  }) else {
    fail("expected request body with messages and tools")
  }

  assert_eq(messages.length(), 2)
  assert_eq(tools.length(), 1)

  guard tools[0] is Object({
    "name": String(tool_name),
    "description": String(tool_description),
    "input_schema": Object(_),
    ..
  }) else {
    fail("expected Anthropic tool definition")
  }
  assert_eq(tool_name, "lookup_weather")
  assert_eq(tool_description, "Look up weather by city")

  guard messages[0] is Object({
    "role": String(assistant_role),
    "content": Array(assistant_parts),
    ..
  }) else {
    fail("expected assistant message")
  }
  assert_eq(assistant_role, "assistant")
  assert_eq(assistant_parts.length(), 2)

  guard assistant_parts[1] is Object({
    "type": String(part_type),
    "id": String(tool_id),
    "name": String(tool_name),
    "input": Object({ "city": String(city), .. }),
    ..
  }) else {
    fail("expected tool_use content block")
  }
  assert_eq(part_type, "tool_use")
  assert_eq(tool_id, "toolu_1")
  assert_eq(tool_name, "lookup_weather")
  assert_eq(city, "Paris")

  guard messages[1] is Object({
    "role": String(tool_role),
    "content": Array(tool_parts),
    ..
  }) else {
    fail("expected tool result message")
  }
  assert_eq(tool_role, "user")
  assert_eq(tool_parts.length(), 1)
  guard tool_parts[0] is Object({
    "type": String(result_type),
    "tool_use_id": String(tool_use_id),
    "content": String(result_content),
    ..
  }) else {
    fail("expected tool_result content block")
  }
  assert_eq(result_type, "tool_result")
  assert_eq(tool_use_id, "toolu_1")
  assert_eq(result_content, "sunny")
}

test "parse content_block_start text event" {
  let state = AnthropicStreamState::new(anthropic_test_model())
  let start_events = parse_anthropic_sse_event(
    "message_start",
    Json::object({
      "message": Json::object({
        "usage": Json::object({
          "input_tokens": Json::number(12.0),
        }),
      }),
    }).stringify(escape_slash=false),
    state,
  )
  assert_eq(start_events.length(), 0)
  assert_eq(state.input_tokens, 12)

  let events = parse_anthropic_sse_event(
    "content_block_start",
    Json::object({
      "index": Json::number(0.0),
      "content_block": Json::object({
        "type": Json::string("text"),
        "text": Json::string(""),
      }),
    }).stringify(escape_slash=false),
    state,
  )

  assert_eq(events.length(), 2)
  assert_true(events[0] is Start(_))
  match events[1] {
    TextStart(index) => assert_eq(index, 0)
    _ => fail("expected TextStart")
  }
}

test "parse content_block_delta text_delta event" {
  let state = AnthropicStreamState::new(anthropic_test_model())
  ignore(parse_anthropic_sse_event(
    "content_block_start",
    Json::object({
      "index": Json::number(0.0),
      "content_block": Json::object({
        "type": Json::string("text"),
        "text": Json::string(""),
      }),
    }).stringify(escape_slash=false),
    state,
  ))

  let events = parse_anthropic_sse_event(
    "content_block_delta",
    Json::object({
      "index": Json::number(0.0),
      "delta": Json::object({
        "type": Json::string("text_delta"),
        "text": Json::string("Hello"),
      }),
    }).stringify(escape_slash=false),
    state,
  )

  assert_eq(events.length(), 1)
  match events[0] {
    TextDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, "Hello")
    }
    _ => fail("expected TextDelta")
  }

  match state.content[0] {
    Text(text) => assert_eq(text, "Hello")
    _ => fail("expected accumulated text")
  }
}

test "parse content_block_start tool_use event" {
  let state = AnthropicStreamState::new(anthropic_test_model())
  let events = parse_anthropic_sse_event(
    "content_block_start",
    Json::object({
      "index": Json::number(0.0),
      "content_block": Json::object({
        "type": Json::string("tool_use"),
        "id": Json::string("toolu_1"),
        "name": Json::string("lookup_weather"),
        "input": Json::object({}),
      }),
    }).stringify(escape_slash=false),
    state,
  )

  assert_eq(events.length(), 2)
  assert_true(events[0] is Start(_))
  match events[1] {
    ToolCallStart(index, tool_call) => {
      assert_eq(index, 0)
      assert_eq(tool_call.id, "toolu_1")
      assert_eq(tool_call.name, "lookup_weather")
    }
    _ => fail("expected ToolCallStart")
  }
  assert_eq(state.current_tool_id, "toolu_1")
  assert_eq(state.current_tool_name, "lookup_weather")
}

test "parse content_block_delta input_json_delta event" {
  let state = AnthropicStreamState::new(anthropic_test_model())
  ignore(parse_anthropic_sse_event(
    "content_block_start",
    Json::object({
      "index": Json::number(0.0),
      "content_block": Json::object({
        "type": Json::string("tool_use"),
        "id": Json::string("toolu_1"),
        "name": Json::string("lookup_weather"),
        "input": Json::object({}),
      }),
    }).stringify(escape_slash=false),
    state,
  ))

  let events = parse_anthropic_sse_event(
    "content_block_delta",
    Json::object({
      "index": Json::number(0.0),
      "delta": Json::object({
        "type": Json::string("input_json_delta"),
        "partial_json": Json::string("{\"city\":\"Paris\"}"),
      }),
    }).stringify(escape_slash=false),
    state,
  )

  assert_eq(events.length(), 1)
  match events[0] {
    ToolCallDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, "{\"city\":\"Paris\"}")
    }
    _ => fail("expected ToolCallDelta")
  }
  assert_eq(state.tool_input_json, "{\"city\":\"Paris\"}")
}

test "parse thinking block events" {
  let state = AnthropicStreamState::new(anthropic_test_model())
  let start_events = parse_anthropic_sse_event(
    "content_block_start",
    Json::object({
      "index": Json::number(0.0),
      "content_block": Json::object({
        "type": Json::string("thinking"),
        "thinking": Json::string(""),
      }),
    }).stringify(escape_slash=false),
    state,
  )

  assert_eq(start_events.length(), 2)
  assert_true(start_events[0] is Start(_))
  match start_events[1] {
    ThinkingStart(index) => assert_eq(index, 0)
    _ => fail("expected ThinkingStart")
  }

  let delta_events = parse_anthropic_sse_event(
    "content_block_delta",
    Json::object({
      "index": Json::number(0.0),
      "delta": Json::object({
        "type": Json::string("thinking_delta"),
        "thinking": Json::string("reasoning"),
      }),
    }).stringify(escape_slash=false),
    state,
  )

  assert_eq(delta_events.length(), 1)
  match delta_events[0] {
    ThinkingDelta(index, delta) => {
      assert_eq(index, 0)
      assert_eq(delta, "reasoning")
    }
    _ => fail("expected ThinkingDelta")
  }
}

test "parse message_delta with stop_reason" {
  let state = AnthropicStreamState::new(anthropic_test_model())
  ignore(parse_anthropic_sse_event(
    "message_start",
    Json::object({
      "message": Json::object({
        "usage": Json::object({
          "input_tokens": Json::number(10.0),
        }),
      }),
    }).stringify(escape_slash=false),
    state,
  ))
  ignore(parse_anthropic_sse_event(
    "content_block_start",
    Json::object({
      "index": Json::number(0.0),
      "content_block": Json::object({
        "type": Json::string("text"),
        "text": Json::string(""),
      }),
    }).stringify(escape_slash=false),
    state,
  ))
  ignore(parse_anthropic_sse_event(
    "content_block_delta",
    Json::object({
      "index": Json::number(0.0),
      "delta": Json::object({
        "type": Json::string("text_delta"),
        "text": Json::string("Hello"),
      }),
    }).stringify(escape_slash=false),
    state,
  ))
  ignore(parse_anthropic_sse_event(
    "content_block_stop",
    Json::object({
      "index": Json::number(0.0),
    }).stringify(escape_slash=false),
    state,
  ))

  let events = parse_anthropic_sse_event(
    "message_delta",
    Json::object({
      "delta": Json::object({
        "stop_reason": Json::string("end_turn"),
      }),
      "usage": Json::object({
        "output_tokens": Json::number(5.0),
      }),
    }).stringify(escape_slash=false),
    state,
  )

  assert_eq(events.length(), 1)
  match events[0] {
    Done(reason, message) => {
      assert_eq(reason, Stop)
      assert_eq(message.stop_reason, Stop)
      assert_eq(message.usage.input, 10)
      assert_eq(message.usage.output, 5)
      assert_eq(message.usage.total_tokens, 15)
      match message.content[0] {
        Text(text) => assert_eq(text, "Hello")
        _ => fail("expected final text")
      }
    }
    _ => fail("expected Done")
  }
}

test "parse message_stop event" {
  let state = AnthropicStreamState::new(anthropic_test_model())
  let events = parse_anthropic_sse_event(
    "message_stop",
    Json::object({}).stringify(escape_slash=false),
    state,
  )
  assert_eq(events.length(), 0)
}

test "anthropic stop reason mapping" {
  assert_eq(anthropic_stop_reason_to_stop_reason("end_turn"), Stop)
  assert_eq(anthropic_stop_reason_to_stop_reason("max_tokens"), Length)
  assert_eq(anthropic_stop_reason_to_stop_reason("tool_use"), ToolUse)
  assert_eq(anthropic_stop_reason_to_stop_reason("rate_limit_error"), Error)
}
