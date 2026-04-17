test "register and retrieve models" {
  clear_model_registry()
  register_builtin_models()
  let sonnet = get_registered_model(provider_anthropic, "claude-sonnet-4-20250514")
  assert_true(sonnet is Some(_))
  assert_eq(sonnet.unwrap().name, "Claude Sonnet 4")
  let models = get_registered_models(provider_openai)
  assert_true(models.length() >= 2)
  let providers = get_all_registered_providers()
  assert_true(providers.length() >= 4)
  clear_model_registry()
}
