test "build_system_prompt includes tools and guidelines" {
  let prompt = build_system_prompt({
    base_prompt: "You are a coding assistant.",
    tools: [{
      name: "read",
      label: "Read",
      description: "Read files",
      parameters: Json::object({}),
      prepare_arguments: None,
      validate_arguments: None,
      execute: fn(_id, _args, _u) { Err("stub") },
    }],
    cwd: "/project",
    project_context: Some("MoonBit project"),
    extension_snippets: [],
    guidelines: ["Be concise", "Use tools"],
  })
  assert_true(prompt.contains("coding assistant"))
  assert_true(prompt.contains("read: Read files"))
  assert_true(prompt.contains("/project"))
  assert_true(prompt.contains("MoonBit project"))
  assert_true(prompt.contains("Be concise"))
}

test "settings manager round trips values" {
  let settings = SettingsManager::new()
  settings.set_model_id("gpt-4o")
  settings.set_thinking_level("high")
  settings.set_active_tools(["read", "write"])
  assert_eq(settings.get_model_id(), Some("gpt-4o"))
  assert_eq(settings.get_thinking_level(), Some("high"))
  assert_eq(settings.get_active_tools(), ["read", "write"])
  let json = settings.to_json()
  let restored = SettingsManager::load_from_json(json)
  assert_eq(restored.get_model_id(), Some("gpt-4o"))
}

test "slash command registry parses and executes" {
  let registry = SlashCommandRegistry::new()
  let executed : Ref[String] = Ref::new("")
  registry.register({
    name: "test",
    description: "Test command",
    handler: fn(args, _ctx) {
      executed.val = args
      Ok(())
    },
  })
  match parse_slash_input(":test hello world") {
    Some((name, args)) => {
      assert_eq(name, "test")
      assert_eq(args, "hello world")
    }
    None => fail("expected parsed slash command")
  }
  assert_true(parse_slash_input("not a command") is None)
  let ctx : SlashCommandContext = {
    session_manager: SessionManager::new(),
    agent: @agent.Agent::new(),
    cwd: ".",
    write: fn(_text) { },
  }
  let result = registry.execute("test", "hello world", ctx)
  assert_true(result is Ok(_))
  assert_eq(executed.val, "hello world")
}

test "skill registry invokes templates" {
  let registry = SkillRegistry::new()
  registry.register({
    name: "review",
    description: "Code review",
    prompt_template: "Review this code: {args}",
    source: "builtin",
  })
  assert_eq(registry.invoke("review", "fn main {}"), Some("Review this code: fn main {}"))
  assert_eq(registry.invoke("unknown", ""), None)
}

test "export_session_html produces valid html structure" {
  let messages : Array[@ai.Message] = [
    @ai.Message::User({ content: [@ai.ContentBlock::Text("hello <world>")] }),
    @ai.Message::Assistant({
      content: [@ai.ContentBlock::Text("**hi** there")],
      api: @ai.api_openai_responses,
      provider: @ai.provider_openai,
      model: "test",
      usage: @ai.Usage::zero(),
      stop_reason: @ai.StopReason::Stop,
      error_message: None,
      timestamp: 0.0,
    }),
  ]
  let html = export_session_html(messages, "Test Session", "gpt-4o", "2026-04-16")
  assert_true(html.contains("<!DOCTYPE html>"))
  assert_true(html.contains("&lt;world&gt;"))
  assert_true(html.contains("<strong>hi</strong>"))
  assert_true(html.contains("Test Session"))
}

test "ansi_to_html converts color codes" {
  let input = "\u{1b}[1mbold\u{1b}[0m and \u{1b}[31mred\u{1b}[0m"
  let html = ansi_to_html(input)
  assert_true(html.contains("font-weight:bold"))
  assert_true(html.contains("color:#e74c3c"))
  assert_true(html.contains("bold"))
  assert_true(html.contains("red"))
}
