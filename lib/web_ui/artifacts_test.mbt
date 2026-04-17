test "detect_artifact_type recognizes common types" {
  match detect_artifact_type("index.html", "text/html") { Html => (); _ => fail("expected Html") }
  match detect_artifact_type("chart.svg", "image/svg+xml") { Svg => (); _ => fail("expected Svg") }
  match detect_artifact_type("notes.md", "text/markdown") { Markdown => (); _ => fail("expected Markdown") }
  match detect_artifact_type("data.csv", "text/csv") { Csv => (); _ => fail("expected Csv") }
  match detect_artifact_type("data.json", "application/json") { Json => (); _ => fail("expected Json") }
  match detect_artifact_type("code.rs", "text/plain") { Code(lang) => assert_eq(lang, "rust"); _ => fail("expected Code") }
  match detect_artifact_type("logo.png", "image/png") { Image(m) => assert_eq(m, "image/png"); _ => fail("expected Image") }
}

test "artifact_pill generates icons" {
  let artifact : Artifact = {
    id: "a1", title: "Test", artifact_type: Markdown, content: "hello",
    language: None, mime_type: "text/markdown", size: 5,
    created_at: "2026-04-16", updated_at: None,
  }
  let pill = artifact_pill(artifact)
  assert_eq(pill.title, "Test")
  assert_true(pill.icon.length() > 0)
  assert_eq(pill.color_class, "markdown")
}

test "artifact registry add, get, remove" {
  let registry = ArtifactRegistry::new()
  let artifact : Artifact = {
    id: "x", title: "X", artifact_type: Text, content: "c",
    language: None, mime_type: "text/plain", size: 1,
    created_at: "2026-04-16", updated_at: None,
  }
  registry.add(artifact)
  assert_eq(registry.list().length(), 1)
  match registry.get("x") {
    Some(a) => assert_eq(a.title, "X")
    None => fail("expected artifact")
  }
  registry.remove("x")
  assert_eq(registry.list().length(), 0)
}

test "safe_sandbox_config allows scripts only for HTML/SVG" {
  let html_cfg = safe_sandbox_config(Html)
  assert_true(html_cfg.allow_scripts)
  let text_cfg = safe_sandbox_config(Text)
  assert_false(text_cfg.allow_scripts)
}

test "tool_renderer_registry lookup" {
  let registry = ToolRendererRegistry::new()
  register_builtin_tool_renderers(registry)
  assert_true(registry.get("bash") is Some(_))
  assert_true(registry.get("read") is Some(_))
  assert_true(registry.get("unknown") is None)
}

test "bash_tool_renderer extracts command" {
  let renderer = bash_tool_renderer()
  let call = (renderer.render_call)("bash", Json::object({ "command": Json::string("ls -la") }))
  assert_eq(call.summary, "ls -la")
  assert_eq(call.label, "bash")
}

test "read_tool_renderer extracts path" {
  let renderer = read_tool_renderer()
  let call = (renderer.render_call)("read", Json::object({ "path": Json::string("/tmp/file.txt") }))
  assert_eq(call.summary, "/tmp/file.txt")
}

test "ApiKeyDialog constructor" {
  let dialog = ApiKeyDialog::new("openai", "OpenAI")
  assert_eq(dialog.provider_id, "openai")
  assert_eq(dialog.provider_name, "OpenAI")
  assert_eq(dialog.current_value, None)
}

test "SessionListDialog filters by query" {
  let sessions : Array[SessionMetadata] = [
    { id: "s1", title: "Alpha project", created_at: "", last_modified: "", message_count: 1, usage: @ai.Usage::zero(), thinking_level: @agent.AgentThinkingLevel::Off, preview: "start of alpha" },
    { id: "s2", title: "Beta coding", created_at: "", last_modified: "", message_count: 1, usage: @ai.Usage::zero(), thinking_level: @agent.AgentThinkingLevel::Off, preview: "hello beta" },
  ]
  let dialog = SessionListDialog::new(sessions)
  let dialog2 = { ..dialog, search_query: "beta" }
  let filtered = dialog2.filtered()
  assert_eq(filtered.length(), 1)
  assert_eq(filtered[0].title, "Beta coding")
}

test "SettingsDialog has default sections" {
  let dialog = SettingsDialog::new()
  assert_true(dialog.sections.length() >= 4)
  // Check at least providers and models exist
  let mut has_providers = false
  let mut has_models = false
  for s in dialog.sections {
    if s.id == "providers" { has_providers = true }
    if s.id == "models" { has_models = true }
  }
  assert_true(has_providers)
  assert_true(has_models)
}
