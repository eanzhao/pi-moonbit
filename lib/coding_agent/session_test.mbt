fn session_test_model() -> @ai.Model {
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

fn session_test_assistant_message(
  content : Array[@ai.ContentBlock],
  stop_reason? : @ai.StopReason = @ai.StopReason::Stop
) -> @ai.AssistantMessage {
  {
    content,
    api: @ai.api_openai_responses,
    provider: @ai.provider_openai,
    model: "mock",
    usage: @ai.Usage::zero(),
    stop_reason,
    error_message: None,
    timestamp: 0.0,
  }
}

fn session_message_text(message : @ai.Message) -> String {
  match message {
    @ai.Message::User(user_message) =>
      match user_message.content[0] {
        @ai.ContentBlock::Text(text) => text
        _ => abort("expected user text")
      }
    @ai.Message::Assistant(assistant_message) =>
      match assistant_message.content[0] {
        @ai.ContentBlock::Text(text) => text
        _ => abort("expected assistant text")
      }
    @ai.Message::ToolResult(tool_result_message) =>
      match tool_result_message.content[0] {
        @ai.ContentBlock::Text(text) => text
        _ => abort("expected tool result text")
      }
  }
}

test "agent session persists transcript and injects custom context into LLM" {
  let session_manager = SessionManager::new()
  let _ = session_manager.append_custom_message(
    "note",
    [@ai.ContentBlock::Text("remember tests")],
  )
  let session_result = AgentSession::new(
    session_test_model(),
    session_manager=session_manager,
  )
  assert_true(session_result is Ok(_))
  let session = session_result.unwrap()

  let seen_context : Ref[Array[@ai.Message]] = Ref::new([])
  session.agent.set_stream_fn(@agent.AgentStreamFn(fn(_model, context, _options, handler) {
    seen_context.val = context.messages.copy()
    let message = session_test_assistant_message([@ai.ContentBlock::Text("ok")])
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    Ok(())
  }))

  let prompt_result = session.prompt_text("hello")
  assert_true(prompt_result is Ok(_))
  assert_eq(session.session_manager.build_transcript_messages().length(), 2)
  assert_eq(seen_context.val.length(), 2)
  assert_eq(session_message_text(seen_context.val[0]), "remember tests")
  assert_eq(session_message_text(seen_context.val[1]), "hello")
}

test "agent session wires extension before_tool_call hook" {
  let echo_tool : @agent.AgentTool = {
    name: "echo",
    label: "Echo",
    description: "Echo back input",
    parameters: Json::object({}),
    prepare_arguments: None,
    validate_arguments: None,
    execute: fn(_tool_call_id, args, _on_update) {
      guard args is Object({ "value": String(value), .. }) else {
        return Err("missing value")
      }
      Ok({
        content: [@ai.ContentBlock::Text("echoed: " + value)],
        details: Json::object({}),
      })
    },
  }

  let mut blocker = CodingExtension::empty("block-echo")
  blocker = { ..blocker, before_tool_call: Some(fn(tool_context, _context) {
    if tool_context.tool_call.name == "echo" {
      Some(@agent.BeforeToolCallResult::block(reason="blocked by extension"))
    } else {
      None
    }
  }) }
  let extension_runtime = ExtensionRuntime::new(extensions=[blocker])
  let session = AgentSession::new(
    session_test_model(),
    tools=[echo_tool],
    extensions=extension_runtime,
  ).unwrap()

  let call_index : Ref[Int] = Ref::new(0)
  session.agent.set_stream_fn(@agent.AgentStreamFn(fn(_model, _context, _options, handler) {
    if call_index.val == 0 {
      let tool_call = @ai.ToolCall::{
        id: "tool-1",
        name: "echo",
        arguments: { "value": Json::string("hello") },
      }
      let message = session_test_assistant_message(
        [@ai.ContentBlock::ToolCall(tool_call)],
        stop_reason=@ai.StopReason::ToolUse,
      )
      handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::ToolUse, message))
    } else {
      let message = session_test_assistant_message([@ai.ContentBlock::Text("done")])
      handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    }
    call_index.val = call_index.val + 1
    Ok(())
  }))

  let result = session.prompt_text("echo")
  assert_true(result is Ok(_))
  let transcript = session.session_manager.build_transcript_messages()
  assert_eq(transcript.length(), 4)
  match transcript[2] {
    @ai.Message::ToolResult(tool_result_message) => {
      assert_true(tool_result_message.error)
      match tool_result_message.content[0] {
        @ai.ContentBlock::Text(text) => assert_eq(text, "blocked by extension")
        _ => fail("expected tool error text")
      }
    }
    _ => fail("expected tool result message")
  }
}

test "extension on_message hook receives all messages" {
  let seen : Array[String] = []
  let mut ext = CodingExtension::empty("observer")
  ext = { ..ext, on_message: Some(fn(message, _context) {
    match message {
      @ai.Message::User(u) =>
        match u.content[0] {
          @ai.ContentBlock::Text(text) => seen.push("user:" + text)
          _ => ()
        }
      @ai.Message::Assistant(a) =>
        match a.content[0] {
          @ai.ContentBlock::Text(text) => seen.push("assistant:" + text)
          _ => ()
        }
      _ => ()
    }
  }) }
  let session = AgentSession::new(
    session_test_model(),
    extensions=ExtensionRuntime::new(extensions=[ext]),
  ).unwrap()
  session.agent.set_stream_fn(@agent.AgentStreamFn(fn(_model, _context, _options, handler) {
    let message = session_test_assistant_message([@ai.ContentBlock::Text("reply")])
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    Ok(())
  }))
  ignore(session.prompt_text("hello"))
  assert_true(seen.contains("assistant:reply"))
}

test "extension command registration and execution" {
  let executed : Ref[String] = Ref::new("")
  let mut ext = CodingExtension::empty("cmd-ext")
  ext = { ..ext, commands: [{
    name: "greet",
    description: "Say hello",
    handler: fn(args, _ctx, _actions) {
      executed.val = "greeted:" + args
      Ok(())
    },
  }] }
  let session = AgentSession::new(
    session_test_model(),
    extensions=ExtensionRuntime::new(extensions=[ext]),
  ).unwrap()
  let commands = session.get_extension_commands()
  assert_eq(commands.length(), 1)
  assert_eq(commands[0].name, "greet")
  let result = session.run_extension_command("greet", "world")
  assert_true(result is Ok(_))
  assert_eq(executed.val, "greeted:world")
  let err = session.run_extension_command("unknown", "")
  assert_true(err is Err(_))
}

test "extension actions can inject messages and change model" {
  let injected : Ref[Bool] = Ref::new(false)
  let mut ext = CodingExtension::empty("action-ext")
  ext = { ..ext, on_start: Some(fn(_ctx, actions) {
    ignore((actions.send_message)("note", [@ai.ContentBlock::Text("injected")]))
    let model = (actions.get_model)()
    if model.id != "mock" {
      return Err("unexpected model id: " + model.id)
    }
    injected.val = true
    Ok(())
  }) }
  let session = AgentSession::new(
    session_test_model(),
    extensions=ExtensionRuntime::new(extensions=[ext]),
  ).unwrap()
  assert_true(injected.val)
  let context = session.build_session_context()
  assert_true(context.messages.length() > 0)
}

test "extension transform_context modifies LLM messages" {
  let mut ext = CodingExtension::empty("ctx-transform")
  ext = { ..ext, transform_context: Some(fn(messages, _ctx) {
    let result = messages.copy()
    result.push(@ai.Message::User({ content: [@ai.ContentBlock::Text("extra context")] }))
    result
  }) }
  let session = AgentSession::new(
    session_test_model(),
    extensions=ExtensionRuntime::new(extensions=[ext]),
  ).unwrap()
  let seen_context : Ref[Array[@ai.Message]] = Ref::new([])
  session.agent.set_stream_fn(@agent.AgentStreamFn(fn(_model, context, _options, handler) {
    seen_context.val = context.messages.copy()
    let message = session_test_assistant_message([@ai.ContentBlock::Text("ok")])
    handler.0(@ai.AssistantMessageEvent::Done(@ai.StopReason::Stop, message))
    Ok(())
  }))
  ignore(session.prompt_text("hello"))
  let last_msg = seen_context.val[seen_context.val.length() - 1]
  assert_eq(session_message_text(last_msg), "extra context")
}
