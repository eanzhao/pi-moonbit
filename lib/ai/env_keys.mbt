let env_var_resolver : Ref[(String) -> String?] = Ref::new(fn(_name) { None })

pub fn set_env_resolver(resolver : (String) -> String?) -> Unit {
  env_var_resolver.val = resolver
}

pub fn get_env_var(name : String) -> String? {
  (env_var_resolver.val)(name)
}

pub fn resolve_api_key(provider : ProviderId) -> String? {
  // Try env vars in order for each provider
  let vars = api_key_env_vars(provider)
  for name in vars {
    match get_env_var(name) {
      Some(value) if value.length() > 0 => return Some(value)
      _ => ()
    }
  }
  None
}

fn api_key_env_vars(provider : ProviderId) -> Array[String] {
  match provider.0 {
    "anthropic" => ["ANTHROPIC_API_KEY", "ANTHROPIC_OAUTH_TOKEN"]
    "openai" => ["OPENAI_API_KEY"]
    "google" | "google-vertex" => ["GOOGLE_API_KEY", "GEMINI_API_KEY"]
    "mistral" => ["MISTRAL_API_KEY"]
    "groq" => ["GROQ_API_KEY"]
    "xai" => ["XAI_API_KEY"]
    "amazon-bedrock" => ["AWS_ACCESS_KEY_ID"]
    "azure-openai" => ["AZURE_OPENAI_API_KEY"]
    "ollama" | "lm-studio" | "vllm" => ["OLLAMA_API_KEY"]  // usually not needed
    "github-copilot" => ["GITHUB_TOKEN"]
    _ => []
  }
}
