fn selectable_model(provider : String, model : @ai.Model) -> SelectableModel {
  { provider, model }
}

test "subsequence score prefers ordered matches" {
  assert_true(subsequence_score("cld", "claude sonnet") > 0.0)
  assert_eq(subsequence_score("zzz", "claude sonnet"), 0.0)
}

test "filter selectable models applies current model capability and search filters" {
  let claude : @ai.Model = {
    id: "claude-sonnet",
    name: "Claude Sonnet",
    api: @ai.api_anthropic_messages,
    provider: @ai.ProviderId("anthropic"),
    base_url: Some("https://api.anthropic.com"),
    reasoning: true,
    input_modalities: [@ai.InputModality::Text, @ai.InputModality::Image],
    cost: { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 },
    context_window: 200000,
    max_tokens: 8192,
  }
  let gpt : @ai.Model = {
    id: "gpt-5.4-mini",
    name: "GPT-4o mini",
    api: @ai.api_openai_responses,
    provider: @ai.ProviderId("openai"),
    base_url: Some("https://api.openai.com"),
    reasoning: false,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.15, output: 0.6, cache_read: 0.0, cache_write: 0.0 },
    context_window: 128000,
    max_tokens: 16000,
  }
  let models = [
    selectable_model("openai", gpt),
    selectable_model("anthropic", claude),
  ]

  let default_sorted = filter_selectable_models(models, current_model=Some(claude))
  assert_eq(default_sorted[0].model.id, "claude-sonnet")

  let search_sorted = filter_selectable_models(models, search_query="g4m")
  assert_eq(search_sorted.length(), 1)
  assert_eq(search_sorted[0].provider, "openai")

  let vision_only = filter_selectable_models(models, filter_vision=true)
  assert_eq(vision_only.length(), 1)
  assert_eq(vision_only[0].provider, "anthropic")
}
