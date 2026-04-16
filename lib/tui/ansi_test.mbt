test "ansi_colored wraps text with color and reset" {
  let result = ansi_colored("hello", ansi_red())
  assert_true(result.has_prefix("\x1b[31m"))
  assert_true(result.contains("hello"))
  assert_true(result.has_suffix("\x1b[0m"))
}

test "ansi_bold_colored applies bold and color" {
  let result = ansi_bold_colored("test", ansi_blue())
  assert_true(result.has_prefix("\x1b[1m\x1b[34m"))
  assert_true(result.contains("test"))
  assert_true(result.has_suffix("\x1b[0m"))
}

test "ansi format helpers produce expected labels" {
  let prompt = ansi_user_prompt()
  assert_true(prompt.contains("you>"))

  let label = ansi_assistant_label()
  assert_true(label.contains("assistant>"))

  let tool_s = ansi_tool_start("bash")
  assert_true(tool_s.contains("bash"))

  let tool_ok = ansi_tool_success("read")
  assert_true(tool_ok.contains("read"))

  let tool_err = ansi_tool_error("write")
  assert_true(tool_err.contains("write"))
  assert_true(tool_err.contains("failed"))
}
