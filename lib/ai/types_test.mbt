test "StopReason equality" {
  assert_eq(StopReason::Stop, StopReason::Stop)
  assert_not_eq(StopReason::Stop, StopReason::Length)
  assert_not_eq(StopReason::ToolUse, StopReason::Error)
}

test "Usage::zero returns zeroed usage" {
  let u = Usage::zero()
  assert_eq(u.input, 0)
  assert_eq(u.output, 0)
  assert_eq(u.cache_read, 0)
  assert_eq(u.total_tokens, 0)
  assert_eq(u.cost.total, 0.0)
}

test "Message construction" {
  let msg : Message = User({ content: [Text("hello")] })
  match msg {
    User(u) => {
      assert_eq(u.content.length(), 1)
      match u.content[0] {
        Text(t) => assert_eq(t, "hello")
        _ => fail("expected Text")
      }
    }
    _ => fail("expected User")
  }
}

test "ToolResultMessage construction" {
  let msg : Message = ToolResult({
    content: [Text("result")],
    tool_call_id: "call_123",
    tool_name: "read_file",
    error: false,
  })
  match msg {
    ToolResult(tr) => {
      assert_eq(tr.tool_call_id, "call_123")
      assert_eq(tr.tool_name, "read_file")
      assert_eq(tr.error, false)
    }
    _ => fail("expected ToolResult")
  }
}

test "ImageMimeType variants" {
  let types : Array[ImageMimeType] = [Jpeg, Png, Gif, Webp]
  assert_eq(types.length(), 4)
  assert_eq(types[0], Jpeg)
  assert_not_eq(types[0], Png)
}
