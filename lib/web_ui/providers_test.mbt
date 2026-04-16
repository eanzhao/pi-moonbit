test "custom provider helpers normalize auto discovery models" {
  let provider : CustomProvider = {
    id: "provider-1",
    name: "My Ollama",
    provider_type: CustomProviderType::AutoDiscovery(AutoDiscoveryProviderType::Ollama),
    base_url: "http://localhost:11434",
    api_key: None,
    models: None,
  }
  let discovered : @ai.Model = {
    id: "llama3.2",
    name: "Llama 3.2",
    api: @ai.api_openai_completions,
    provider: @ai.ProviderId(""),
    base_url: None,
    reasoning: true,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 8192,
    max_tokens: 4096,
  }

  let models = custom_provider_loaded_models(provider, discovered_models=Some([discovered]))
  assert_eq(models.length(), 1)
  assert_eq(models[0].provider, @ai.ProviderId("My Ollama"))
  assert_eq(models[0].api, @ai.api_openai_completions)
  assert_eq(models[0].base_url, Some("http://localhost:11434/v1"))
}

test "custom provider helpers preserve manual models" {
  let manual_model = web_ui_test_model()
  let provider : CustomProvider = {
    id: "provider-2",
    name: "Custom Anthropic",
    provider_type: CustomProviderType::AnthropicMessages,
    base_url: "https://api.anthropic.local",
    api_key: Some("token"),
    models: Some([manual_model]),
  }

  let models = custom_provider_loaded_models(provider)
  assert_eq(models.length(), 1)
  assert_eq(models[0].provider, @ai.ProviderId("Custom Anthropic"))
  assert_eq(models[0].api, @ai.api_anthropic_messages)
  assert_eq(models[0].base_url, Some("https://api.anthropic.local"))
  assert_eq(provider_type_label(provider.provider_type), "Anthropic Messages Compatible")
}
