test "parse_rpc_command parses valid JSONL command" {
  let result = parse_rpc_command(
    "{\"id\":\"req-1\",\"command\":\"Prompt\",\"data\":{\"text\":\"hello\"}}",
  )
  match result {
    Ok(command) => {
      assert_eq(command.id, Some("req-1"))
      assert_eq(command.command, "prompt")
      match command.data {
        Some(Object(obj)) =>
          match obj.get("text") {
            Some(String(text)) => assert_eq(text, "hello")
            _ => fail("expected text field")
          }
        _ => fail("expected command data")
      }
    }
    Err(message) => fail(message)
  }
}

test "parse_rpc_command rejects invalid command" {
  let result = parse_rpc_command("{\"command\":\"unknown\"}")
  match result {
    Ok(_) => fail("expected parse error")
    Err(message) => assert_true(message.contains("unknown rpc command"))
  }
}

test "rpc_response_json serializes response" {
  let text = rpc_response_json({
    id: Some("req-1"),
    command: "prompt",
    success: true,
    data: Some(Json::object({ "ok": Json::boolean(true) })),
    error: None,
  })
  let json = try @json.parse(text) catch {
    _ => fail("expected valid json")
  } noraise {
    value => value
  }
  guard json is Object(obj) else {
    fail("expected object")
  }
  match obj.get("id") {
    Some(String(value)) => assert_eq(value, "req-1")
    _ => fail("expected id")
  }
  match obj.get("command") {
    Some(String(value)) => assert_eq(value, "prompt")
    _ => fail("expected command")
  }
  match obj.get("success") {
    Some(True) => ()
    _ => fail("expected success")
  }
  match obj.get("data") {
    Some(Object(data)) =>
      match data.get("ok") {
        Some(True) => ()
        _ => fail("expected ok=true")
      }
    _ => fail("expected data")
  }
  match obj.get("error") {
    Some(Null) => ()
    _ => fail("expected null error")
  }
}

test "rpc_event_json serializes event" {
  let text = rpc_event_json({
    event_type: "agent_start",
    data: Some(Json::object({ "source": Json::string("rpc") })),
  })
  let json = try @json.parse(text) catch {
    _ => fail("expected valid json")
  } noraise {
    value => value
  }
  guard json is Object(obj) else {
    fail("expected object")
  }
  match obj.get("event_type") {
    Some(String(value)) => assert_eq(value, "agent_start")
    _ => fail("expected event_type")
  }
  match obj.get("data") {
    Some(Object(data)) =>
      match data.get("source") {
        Some(String(value)) => assert_eq(value, "rpc")
        _ => fail("expected source")
      }
    _ => fail("expected data")
  }
}
