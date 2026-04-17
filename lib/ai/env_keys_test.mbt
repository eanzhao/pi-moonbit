test "resolve_api_key uses injected resolver" {
  set_env_resolver(fn(name) {
    if name == "ANTHROPIC_API_KEY" { Some("sk-ant-test") } else { None }
  })
  assert_eq(resolve_api_key(provider_anthropic), Some("sk-ant-test"))
  assert_eq(resolve_api_key(provider_openai), None)
  set_env_resolver(fn(_) { None })
}

test "resolve_api_key tries multiple env vars in order" {
  set_env_resolver(fn(name) {
    if name == "GEMINI_API_KEY" { Some("gemini-key") } else { None }
  })
  assert_eq(resolve_api_key(provider_google), Some("gemini-key"))
  set_env_resolver(fn(_) { None })
}
