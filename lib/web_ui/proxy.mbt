pub fn default_proxy_settings(url? : String = "http://localhost:3001") -> ProxySettings {
  { enabled: false, url }
}

pub fn load_proxy_settings(store : SettingsStore) -> Result[ProxySettings, String] {
  let enabled_result : Result[Bool?, String] = store.get("proxy.enabled")
  let url_result : Result[String?, String] = store.get("proxy.url")

  let enabled = match enabled_result {
    Ok(Some(value)) => value
    Ok(None) => false
    Err(message) => return Err(message)
  }
  let url = match url_result {
    Ok(Some(value)) if value.trim().length() > 0 => value
    Ok(_) => default_proxy_settings().url
    Err(message) => return Err(message)
  }
  Ok({ enabled, url })
}

pub fn save_proxy_settings(
  store : SettingsStore,
  settings : ProxySettings
) -> Result[Unit, String] {
  match store.set("proxy.enabled", settings.enabled) {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  store.set("proxy.url", settings.url)
}

pub fn clear_proxy_settings(store : SettingsStore) -> Result[Unit, String] {
  match store.delete("proxy.enabled") {
    Ok(_) => ()
    Err(message) => return Err(message)
  }
  store.delete("proxy.url")
}

pub fn current_proxy_url(store : SettingsStore) -> Result[String?, String] {
  match load_proxy_settings(store) {
    Ok(settings) =>
      if settings.enabled && settings.url.trim().length() > 0 {
        Ok(Some(settings.url))
      } else {
        Ok(None)
      }
    Err(message) => Err(message)
  }
}

pub fn should_use_proxy_for_provider(provider : String, api_key : String) -> Bool {
  match provider.to_lower() {
    "zai" => true
    "anthropic" => api_key.has_prefix("sk-ant-oat") || api_key.has_prefix("{")
    "openai-codex" => true
    "openai" => false
    "google" => false
    "groq" => false
    "openrouter" => false
    "cerebras" => false
    "xai" => false
    "ollama" => false
    "lmstudio" => false
    "github-copilot" => false
    _ => false
  }
}

pub fn apply_proxy_if_needed(
  model : @ai.Model,
  api_key : String,
  proxy_url? : String? = None
) -> @ai.Model {
  let resolved_proxy_url = match proxy_url {
    Some(url) if url.trim().length() > 0 => url
    _ => return model
  }
  let base_url = match model.base_url {
    Some(url) => url
    None => return model
  }
  if !should_use_proxy_for_provider(model.provider.0, api_key) {
    return model
  }
  {
    id: model.id,
    name: model.name,
    api: model.api,
    provider: model.provider,
    base_url: Some(
      resolved_proxy_url + "/?url=" + percent_encode(base_url),
    ),
    reasoning: model.reasoning,
    input_modalities: model.input_modalities.copy(),
    cost: model.cost,
    context_window: model.context_window,
    max_tokens: model.max_tokens,
  }
}

pub fn is_cors_error(error_name : String, error_message : String) -> Bool {
  let lowered = error_message.to_lower()
  (error_name == "TypeError" && lowered.contains("failed to fetch")) ||
  error_name == "NetworkError" ||
  lowered.contains("cors") ||
  lowered.contains("cross-origin")
}

fn percent_encode(text : String) -> String {
  let parts : Array[String] = []
  for c in text.iter() {
    let code = c.to_int()
    let allowed =
      (code >= 48 && code <= 57) ||
      (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      c == '-' ||
      c == '_' ||
      c == '.' ||
      c == '~'
    if allowed {
      parts.push(c.to_string())
    } else {
      parts.push("%" + percent_hex(code))
    }
  }
  parts.join("")
}

fn percent_hex(code : Int) -> String {
  if code <= 0xFF {
    hex_byte(code)
  } else if code <= 0xFFFF {
    hex_byte(code / 256) + hex_byte(code % 256)
  } else {
    hex_byte((code >> 16) & 0xFF) + hex_byte((code >> 8) & 0xFF) + hex_byte(code & 0xFF)
  }
}

fn hex_byte(value : Int) -> String {
  hex_digit((value / 16) % 16) + hex_digit(value % 16)
}

fn hex_digit(value : Int) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "A"
    11 => "B"
    12 => "C"
    13 => "D"
    14 => "E"
    _ => "F"
  }
}
