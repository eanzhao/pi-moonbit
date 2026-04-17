test "dark and light themes have correct names" {
  assert_eq(dark_theme().name, "dark")
  assert_eq(light_theme().name, "light")
}

test "get_theme defaults to dark for unknown names" {
  assert_eq(get_theme("unknown").name, "dark")
  assert_eq(get_theme("light").name, "light")
  assert_eq(get_theme("dark").name, "dark")
}

test "theme_colored wraps text with color and reset" {
  let theme = dark_theme()
  let result = theme_colored(theme, "hello", theme.accent_user)
  assert_true(result.contains("hello"))
  assert_true(result.has_prefix(theme.accent_user))
  assert_true(result.has_suffix(theme.reset))
}

test "render_tool_call includes tool name" {
  let theme = dark_theme()
  let rendered = render_tool_call(theme, "bash", "ls -la")
  assert_true(rendered.contains("bash"))
  assert_true(rendered.contains("ls -la"))
}

test "render_tool_result uses success/error icons" {
  let theme = dark_theme()
  let ok = render_tool_result(theme, "read", true, "content")
  let err = render_tool_result(theme, "write", false, "error")
  assert_true(ok.contains("✓"))
  assert_true(ok.contains("read"))
  assert_true(err.contains("✗"))
  assert_true(err.contains("write"))
}

test "render_session_panel shows all fields" {
  let theme = dark_theme()
  let rendered = render_session_panel(theme, "/tmp/s.jsonl", "gpt-4o", "high", 42)
  assert_true(rendered.contains("/tmp/s.jsonl"))
  assert_true(rendered.contains("gpt-4o"))
  assert_true(rendered.contains("high"))
  assert_true(rendered.contains("42"))
}

test "render_model_list marks current model" {
  let theme = dark_theme()
  let models : Array[ModelEntry] = [
    { id: "gpt-4o", provider: "openai", description: None },
    { id: "claude-sonnet", provider: "anthropic", description: None },
  ]
  let rendered = render_model_list(theme, "gpt-4o", models)
  assert_true(rendered.contains("gpt-4o"))
  assert_true(rendered.contains("claude-sonnet"))
  assert_true(rendered.contains("→"))
}

test "render_thinking_selector lists all levels" {
  let theme = dark_theme()
  let rendered = render_thinking_selector(theme, "medium")
  assert_true(rendered.contains("off"))
  assert_true(rendered.contains("minimal"))
  assert_true(rendered.contains("medium"))
  assert_true(rendered.contains("xhigh"))
}

test "render_welcome_banner mentions pi-moonbit" {
  let theme = dark_theme()
  let banner = render_welcome_banner(theme, "gpt-4o", "off")
  assert_true(banner.contains("pi-moonbit"))
  assert_true(banner.contains("gpt-4o"))
}
