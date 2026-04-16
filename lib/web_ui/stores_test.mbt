test "settings store round-trips typed values" {
  let storage = app_storage_with_in_memory_backend()

  ignore(storage.settings.set("proxy.enabled", true))
  ignore(storage.settings.set("proxy.url", "https://proxy.local"))
  let enabled : Bool? = storage.settings.get("proxy.enabled").unwrap()
  let proxy_url : String? = storage.settings.get("proxy.url").unwrap()

  assert_eq(enabled, Some(true))
  assert_eq(proxy_url, Some("https://proxy.local"))

  let keys = storage.settings.list().unwrap()
  assert_true(keys.contains("proxy.enabled"))
  assert_true(keys.contains("proxy.url"))
}

test "provider and custom provider stores use shared backend" {
  let storage = app_storage_with_in_memory_backend()

  ignore(storage.provider_keys.set("anthropic", "secret"))
  assert_true(storage.provider_keys.has("anthropic").unwrap())
  assert_eq(storage.provider_keys.get("anthropic").unwrap(), Some("secret"))

  let provider : CustomProvider = {
    id: "provider-1",
    name: "local-openai",
    provider_type: CustomProviderType::OpenaiResponses,
    base_url: "http://localhost:11434/v1",
    api_key: Some("token"),
    models: Some([web_ui_test_model()]),
  }
  ignore(storage.custom_providers.set(provider))
  let providers = storage.custom_providers.get_all().unwrap()
  assert_eq(providers.length(), 1)
  assert_eq(providers[0].name, "local-openai")
}

test "sessions store and app storage global instance work together" {
  clear_app_storage()
  let storage = app_storage_with_in_memory_backend()
  set_app_storage(storage)

  let global_storage = get_app_storage().unwrap()
  let data = web_ui_session_data(
    "session-global",
    "",
    [web_ui_user_message("hello"), web_ui_assistant_message("world", input=3, output=4)],
    "2026-04-16T00:00:00.000Z",
    "2026-04-16T00:03:00.000Z",
  )
  ignore(global_storage.sessions.save(data))

  let metadata = global_storage.sessions.get_metadata("session-global").unwrap().unwrap()
  assert_eq(metadata.title, "hello")
  assert_eq(global_storage.sessions.get_latest_session_id().unwrap(), Some("session-global"))

  let quota = global_storage.get_quota_info().unwrap()
  assert_true(quota.usage > 0)
}
