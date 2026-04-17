let registered_models : Array[Model] = []

pub fn register_model(model : Model) -> Unit {
  for i = 0; i < registered_models.length(); i = i + 1 {
    if registered_models[i].id == model.id && registered_models[i].provider == model.provider {
      registered_models[i] = model
      return
    }
  }
  registered_models.push(model)
}

pub fn get_registered_model(provider : ProviderId, model_id : String) -> Model? {
  for model in registered_models {
    if model.provider == provider && model.id == model_id {
      return Some(model)
    }
  }
  None
}

pub fn get_registered_models(provider : ProviderId) -> Array[Model] {
  let result : Array[Model] = []
  for model in registered_models {
    if model.provider == provider { result.push(model) }
  }
  result
}

pub fn get_all_registered_providers() -> Array[ProviderId] {
  let seen : Array[ProviderId] = []
  for model in registered_models {
    let mut found = false
    for p in seen { if p == model.provider { found = true; break } }
    if !found { seen.push(model.provider) }
  }
  seen
}

pub fn clear_model_registry() -> Unit { registered_models.clear() }

pub fn register_builtin_models() -> Unit {
  // Anthropic
  register_model({ id: "claude-sonnet-4-20250514", name: "Claude Sonnet 4", api: api_anthropic_messages, provider: provider_anthropic, base_url: None, reasoning: true, input_modalities: [Text, Image], cost: { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 }, context_window: 200000, max_tokens: 16384 })
  register_model({ id: "claude-opus-4-20250514", name: "Claude Opus 4", api: api_anthropic_messages, provider: provider_anthropic, base_url: None, reasoning: true, input_modalities: [Text, Image], cost: { input: 15.0, output: 75.0, cache_read: 1.5, cache_write: 18.75 }, context_window: 200000, max_tokens: 32768 })
  register_model({ id: "claude-haiku-3-5-20241022", name: "Claude 3.5 Haiku", api: api_anthropic_messages, provider: provider_anthropic, base_url: None, reasoning: false, input_modalities: [Text, Image], cost: { input: 0.8, output: 4.0, cache_read: 0.08, cache_write: 1.0 }, context_window: 200000, max_tokens: 8192 })
  // OpenAI
  register_model({ id: "gpt-4o", name: "GPT-4o", api: api_openai_responses, provider: provider_openai, base_url: None, reasoning: false, input_modalities: [Text, Image], cost: { input: 2.5, output: 10.0, cache_read: 1.25, cache_write: 0.0 }, context_window: 128000, max_tokens: 16384 })
  register_model({ id: "gpt-4o-mini", name: "GPT-4o Mini", api: api_openai_responses, provider: provider_openai, base_url: None, reasoning: false, input_modalities: [Text, Image], cost: { input: 0.15, output: 0.6, cache_read: 0.075, cache_write: 0.0 }, context_window: 128000, max_tokens: 16384 })
  register_model({ id: "o3-mini", name: "o3-mini", api: api_openai_responses, provider: provider_openai, base_url: None, reasoning: true, input_modalities: [Text], cost: { input: 1.1, output: 4.4, cache_read: 0.55, cache_write: 0.0 }, context_window: 200000, max_tokens: 100000 })
  // Google
  register_model({ id: "gemini-2.0-flash", name: "Gemini 2.0 Flash", api: api_google_genai, provider: provider_google, base_url: None, reasoning: false, input_modalities: [Text, Image], cost: { input: 0.1, output: 0.4, cache_read: 0.025, cache_write: 0.0 }, context_window: 1048576, max_tokens: 8192 })
  register_model({ id: "gemini-2.5-pro", name: "Gemini 2.5 Pro", api: api_google_genai, provider: provider_google, base_url: None, reasoning: true, input_modalities: [Text, Image], cost: { input: 1.25, output: 10.0, cache_read: 0.315, cache_write: 0.0 }, context_window: 1048576, max_tokens: 65536 })
  // Mistral
  register_model({ id: "mistral-large-latest", name: "Mistral Large", api: api_mistral, provider: provider_mistral, base_url: None, reasoning: false, input_modalities: [Text], cost: { input: 2.0, output: 6.0, cache_read: 0.0, cache_write: 0.0 }, context_window: 128000, max_tokens: 8192 })
}
