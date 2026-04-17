test "ApiId equality and identity" {
  assert_eq(api_anthropic_messages, ApiId("anthropic-messages"))
  assert_not_eq(api_anthropic_messages, api_openai_completions)
}

test "ProviderId equality" {
  assert_eq(provider_anthropic, ProviderId("anthropic"))
  assert_not_eq(provider_anthropic, provider_openai)
}

test "calculate_cost" {
  let model : Model = {
    id: "claude-sonnet-4-20250514",
    name: "Claude Sonnet 4",
    api: api_anthropic_messages,
    provider: provider_anthropic,
    base_url: None,
    reasoning: true,
    input_modalities: [Text, Image],
    cost: { input: 3.0, output: 15.0, cache_read: 0.3, cache_write: 3.75 },
    context_window: 200_000,
    max_tokens: 16_384,
  }
  let usage : Usage = {
    input: 1_000_000,
    output: 1_000_000,
    cache_read: 0,
    cache_write: 0,
    total_tokens: 2_000_000,
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0, total: 0.0 },
  }
  let cost = calculate_cost(model, usage)
  assert_eq(cost, 18.0)
}

test "models_are_equal" {
  let base : Model = {
    id: "gpt-5.4",
    name: "GPT-4o",
    api: api_openai_responses,
    provider: provider_openai,
    base_url: None,
    reasoning: false,
    input_modalities: [Text, Image],
    cost: { input: 2.5, output: 10.0, cache_read: 1.25, cache_write: 0.0 },
    context_window: 128_000,
    max_tokens: 16_384,
  }
  let same : Model = {
    id: "gpt-5.4",
    name: "GPT-4o (different name)",
    api: api_openai_completions,
    provider: provider_openai,
    base_url: Some("https://custom.endpoint.com"),
    reasoning: false,
    input_modalities: [Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 64_000,
    max_tokens: 8_192,
  }
  let different : Model = {
    id: "gpt-5.4-mini",
    name: "GPT-4o Mini",
    api: api_openai_responses,
    provider: provider_openai,
    base_url: None,
    reasoning: false,
    input_modalities: [Text, Image],
    cost: { input: 0.15, output: 0.6, cache_read: 0.075, cache_write: 0.0 },
    context_window: 128_000,
    max_tokens: 16_384,
  }
  assert_true(models_are_equal(base, same))
  assert_false(models_are_equal(base, different))
}
