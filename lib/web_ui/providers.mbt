pub fn is_auto_discovery_provider_type(provider_type : CustomProviderType) -> Bool {
  match provider_type {
    CustomProviderType::AutoDiscovery(_) => true
    _ => false
  }
}

pub fn custom_provider_api_id(provider_type : CustomProviderType) -> @ai.ApiId {
  match provider_type {
    CustomProviderType::AutoDiscovery(_) => @ai.api_openai_completions
    CustomProviderType::OpenaiCompletions => @ai.api_openai_completions
    CustomProviderType::OpenaiResponses => @ai.api_openai_responses
    CustomProviderType::AnthropicMessages => @ai.api_anthropic_messages
  }
}

pub fn custom_provider_models(provider : CustomProvider) -> Array[@ai.Model] {
  match provider.models {
    Some(models) => models.copy()
    None => []
  }
}

pub fn normalize_custom_provider_model(
  provider : CustomProvider,
  model : @ai.Model
) -> @ai.Model {
  {
    id: model.id,
    name: model.name,
    api: custom_provider_api_id(provider.provider_type),
    provider: @ai.ProviderId(provider.name),
    base_url: match model.base_url {
      Some(url) => Some(url)
      None => Some(custom_provider_api_base_url(provider))
    },
    reasoning: model.reasoning,
    input_modalities: model.input_modalities.copy(),
    cost: model.cost,
    context_window: model.context_window,
    max_tokens: model.max_tokens,
  }
}

pub fn custom_provider_loaded_models(
  provider : CustomProvider,
  discovered_models? : Array[@ai.Model]? = None
) -> Array[@ai.Model] {
  let raw_models = match discovered_models {
    Some(models) => models.copy()
    None => custom_provider_models(provider)
  }
  let normalized : Array[@ai.Model] = []
  for model in raw_models {
    normalized.push(normalize_custom_provider_model(provider, model))
  }
  normalized
}

pub fn custom_provider_api_base_url(provider : CustomProvider) -> String {
  match provider.provider_type {
    CustomProviderType::AutoDiscovery(_) =>
      if provider.base_url.has_suffix("/v1") {
        provider.base_url
      } else {
        provider.base_url + "/v1"
      }
    _ => provider.base_url
  }
}

pub fn provider_type_label(provider_type : CustomProviderType) -> String {
  match provider_type {
    CustomProviderType::AutoDiscovery(AutoDiscoveryProviderType::Ollama) => "Ollama"
    CustomProviderType::AutoDiscovery(AutoDiscoveryProviderType::LlamaCpp) => "llama.cpp"
    CustomProviderType::AutoDiscovery(AutoDiscoveryProviderType::Vllm) => "vLLM"
    CustomProviderType::AutoDiscovery(AutoDiscoveryProviderType::Lmstudio) => "LM Studio"
    CustomProviderType::OpenaiCompletions => "OpenAI Completions Compatible"
    CustomProviderType::OpenaiResponses => "OpenAI Responses Compatible"
    CustomProviderType::AnthropicMessages => "Anthropic Messages Compatible"
  }
}
