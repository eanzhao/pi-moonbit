test "proxy settings round trip through settings store" {
  let storage = app_storage_with_in_memory_backend()
  let settings : ProxySettings = { enabled: true, url: "https://proxy.local" }

  ignore(save_proxy_settings(storage.settings, settings))
  let loaded = load_proxy_settings(storage.settings).unwrap()
  assert_eq(loaded.enabled, true)
  assert_eq(loaded.url, "https://proxy.local")
  assert_eq(current_proxy_url(storage.settings).unwrap(), Some("https://proxy.local"))

  ignore(clear_proxy_settings(storage.settings))
  let cleared = load_proxy_settings(storage.settings).unwrap()
  assert_eq(cleared.enabled, false)
  assert_eq(cleared.url, "http://localhost:3001")
}

test "proxy rules match provider behavior" {
  assert_true(should_use_proxy_for_provider("zai", "whatever"))
  assert_true(should_use_proxy_for_provider("anthropic", "sk-ant-oat-demo"))
  assert_true(!should_use_proxy_for_provider("anthropic", "sk-ant-api-demo"))
  assert_true(!should_use_proxy_for_provider("openai", "sk-demo"))
  assert_true(is_cors_error("TypeError", "Failed to fetch"))
  assert_true(is_cors_error("NetworkError", "network"))
}

test "apply proxy rewrites model base url only when required" {
  let model : @ai.Model = {
    id: "claude",
    name: "Claude",
    api: @ai.api_anthropic_messages,
    provider: @ai.ProviderId("anthropic"),
    base_url: Some("https://api.anthropic.com"),
    reasoning: true,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 },
    context_window: 200000,
    max_tokens: 8192,
  }

  let proxied = apply_proxy_if_needed(
    model,
    "sk-ant-oat-demo",
    proxy_url=Some("https://proxy.local"),
  )
  assert_true(proxied.base_url.unwrap().contains("https%3A%2F%2Fapi.anthropic.com"))

  let unchanged = apply_proxy_if_needed(model, "sk-ant-api-demo", proxy_url=Some("https://proxy.local"))
  assert_eq(unchanged.base_url, model.base_url)
}
