///| `pimbt providers` 子命令 — 管理用户在 NyxID 上连接的 LLM provider。
///
/// 支持：
/// - `pimbt providers list` — GET /api/v1/providers/my-tokens，列出已连接 provider
/// - `pimbt providers connect <slug>` — 交互式提示 API key，POST 到 /connect/api-key
/// - `pimbt providers disconnect <provider_id>` — DELETE /disconnect

pub fn run_providers_command(config : ProvidersConfig, runtime : CliHostRuntime) -> Int {
  // Resolve bearer token (shared across all provider sub-actions)
  let (base_url, bearer) = match resolve_nyxid_bearer(config.base_url, config.bearer_override, config.credentials_path, runtime) {
    Ok(r) => r
    Err(msg) => {
      (runtime.stderr_write)(@tui.ansi_error(msg) + "\n")
      return 2
    }
  }

  match config.action {
    List => run_providers_list(base_url, bearer, runtime)
    Connect(slug) => run_providers_connect(slug, config, base_url, bearer, runtime)
    Disconnect(id) => run_providers_disconnect(id, base_url, bearer, runtime)
  }
}

fn resolve_nyxid_bearer(
  base_url : String,
  bearer_override : String?,
  credentials_path : String,
  runtime : CliHostRuntime
) -> Result[(String, String), String] {
  match bearer_override {
    Some(tok) if tok.length() > 0 => return Ok((base_url, tok))
    _ => ()
  }
  match (runtime.read_text)(credentials_path) {
    Ok(text) => {
      let json = try { @json.parse(text) } catch {
        _ => return Err("credentials file is not valid JSON: " + credentials_path)
      }
      match @ai.parse_nyxid_stored_credentials(json) {
        Ok(stored) => Ok((stored.base_url, stored.credentials.access_token))
        Err(msg) => Err("credentials file invalid: " + msg)
      }
    }
    Err(_) => Err("no NyxID credentials found at " + credentials_path + ".\nRun `pimbt login` first.")
  }
}

fn run_providers_list(base_url : String, bearer : String, runtime : CliHostRuntime) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write

  // /providers/my-tokens — built-in LLM provider bindings (OpenAI / Anthropic / ...).
  let tokens_url = trim_slash_right(base_url) + @ai.nyxid_my_tokens_path
  let (status, body) : (Int, String) = match host_get_bearer(tokens_url, bearer) {
    Ok((s, b)) => (s, b)
    Err(msg) => {
      write_err(@tui.ansi_error("request failed: " + msg) + "\n")
      return 1
    }
  }
  if status == 401 {
    write_err(
      @tui.ansi_error(
        "NyxID rejected the token (401). Run `pimbt login` to re-authenticate.",
      ) + "\n",
    )
    return 3
  }
  if status >= 400 {
    write_err(@tui.ansi_error("HTTP " + status.to_string() + " from NyxID:\n" + body) + "\n")
    return 1
  }
  let json = try @json.parse(body) catch {
    _ => {
      write_err(@tui.ansi_error("response is not valid JSON:\n" + body) + "\n")
      return 1
    }
  } noraise {
    v => v
  }
  let tokens = match @ai.parse_nyxid_user_tokens(json) {
    Ok(t) => t
    Err(msg) => {
      write_err(@tui.ansi_error(msg) + "\n")
      return 1
    }
  }

  // /keys — user-registered proxy services (Ollama / MLX / Mimo / ...).
  // Failure non-fatal (older NyxID may not have this endpoint).
  let keys_url = trim_slash_right(base_url) + @ai.nyxid_keys_path
  let user_services = fetch_user_services_silent(keys_url, bearer)

  write_out(format_user_tokens(tokens))
  write_out(format_user_services(user_services))
  0
}

fn fetch_user_services_silent(
  keys_url : String,
  bearer : String
) -> Array[@ai.NyxidUserService] {
  let (status, body) = match host_get_bearer(keys_url, bearer) {
    Ok(r) => r
    Err(_) => return []
  }
  if status >= 400 { return [] }
  let json = try @json.parse(body) catch {
    _ => return []
  } noraise {
    v => v
  }
  match @ai.parse_nyxid_keys(json) {
    Ok(list) => {
      let out : Array[@ai.NyxidUserService] = []
      for s in list {
        if s.active && s.service_type == "http" {
          out.push(s)
        }
      }
      out
    }
    Err(_) => []
  }
}

fn format_user_services(services : Array[@ai.NyxidUserService]) -> String {
  let sb = StringBuilder::new()
  sb.write_string("\n")
  sb.write_string(@tui.ansi_section_header("User-registered Services") + "\n")
  if services.length() == 0 {
    sb.write_string(
      "  " + @tui.ansi_dim() +
      "(none — register one via `nyxid service add <slug>` on the NyxID CLI)" +
      @tui.ansi_reset() + "\n",
    )
    return sb.to_string()
  }
  for s in services {
    let (icon, colored_status) = match s.status {
      "active" => ("✓", @tui.ansi_green() + s.status + @tui.ansi_reset())
      "expired" => ("⚠", @tui.ansi_yellow() + s.status + @tui.ansi_reset())
      "pending" => ("⋯", @tui.ansi_yellow() + s.status + @tui.ansi_reset())
      _ => ("·", s.status)
    }
    let label_part = if s.label == s.slug {
      ""
    } else {
      " " + @tui.ansi_dim() + "\"" + s.label + "\"" + @tui.ansi_reset()
    }
    let url_part = if s.endpoint_url.length() > 0 {
      "  " + @tui.ansi_dim() + s.endpoint_url + @tui.ansi_reset()
    } else {
      ""
    }
    sb.write_string(
      "  " + icon + " " + @tui.ansi_bold() + s.slug + @tui.ansi_reset() +
      label_part + "  " + @tui.ansi_dim() + "[" + @tui.ansi_reset() +
      colored_status + @tui.ansi_dim() + "]" + @tui.ansi_reset() + url_part + "\n",
    )
  }
  sb.to_string()
}

fn format_user_tokens(tokens : Array[@ai.UserToken]) -> String {
  let sb = StringBuilder::new()
  sb.write_string(@tui.ansi_section_header("Connected Providers") + "\n")
  if tokens.length() == 0 {
    sb.write_string("  " + @tui.ansi_info("(none) — run `pimbt providers connect <slug>` to add one") + "\n\n")
    sb.write_string(@tui.ansi_info("Examples:") + "\n")
    sb.write_string("  pimbt providers connect openai\n")
    sb.write_string("  pimbt providers connect anthropic\n")
    sb.write_string("  pimbt providers connect gemini\n")
    return sb.to_string()
  }
  for token in tokens {
    // NyxID's /providers/my-tokens returns "active" | "expired" | "pending".
    let (icon, colored_status) = match token.status {
      "active" => ("✓", @tui.ansi_green() + token.status + @tui.ansi_reset())
      "expired" => ("⚠", @tui.ansi_yellow() + token.status + @tui.ansi_reset())
      "pending" => ("⋯", @tui.ansi_yellow() + token.status + @tui.ansi_reset())
      _ => ("·", token.status)
    }
    let label_part = match token.label {
      Some(l) if l.length() > 0 => " " + @tui.ansi_dim() + "(" + l + ")" + @tui.ansi_reset()
      _ => ""
    }
    sb.write_string("  " + icon + " " + @tui.ansi_bold() + token.provider_slug + @tui.ansi_reset() +
      label_part + "  " + @tui.ansi_dim() + "[" + @tui.ansi_reset() + colored_status + @tui.ansi_dim() + "]" + @tui.ansi_reset() +
      "  " + @tui.ansi_dim() + "id=" + token.provider_id + @tui.ansi_reset() + "\n")
  }
  sb.to_string()
}

fn run_providers_connect(
  slug : String,
  config : ProvidersConfig,
  base_url : String,
  bearer : String,
  runtime : CliHostRuntime
) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write

  // Get API key — from --api-key flag, or prompt interactively
  let api_key = match config.api_key {
    Some(k) if k.length() > 0 => k
    _ => {
      write_out(@tui.ansi_info("Enter API key for " + slug + " (input not echoed, press Enter when done):") + "\n")
      match (runtime.read_line)(slug + "> ") {
        None => {
          write_err(@tui.ansi_error("no API key provided") + "\n")
          return 2
        }
        Some(line) => {
          let trimmed = line.trim().to_string()
          if trimmed.length() == 0 {
            write_err(@tui.ansi_error("API key cannot be empty") + "\n")
            return 2
          }
          trimmed
        }
      }
    }
  }

  let body = @ai.build_nyxid_connect_api_key_body(api_key, label=config.label)
  let url = trim_slash_right(base_url) + @ai.nyxid_connect_api_key_path(slug)
  let body_text = body.stringify(escape_slash=false)

  match host_post_json_bearer(url, body_text, bearer) {
    Err(msg) => {
      write_err(@tui.ansi_error("request failed: " + msg) + "\n")
      1
    }
    Ok((status, resp)) => {
      if status == 401 {
        write_err(@tui.ansi_error("NyxID rejected the token (401). Run `pimbt login` to re-authenticate.") + "\n")
        return 3
      }
      if status == 404 {
        write_err(@tui.ansi_error("unknown provider slug: " + slug) + "\n")
        return 4
      }
      if status >= 400 {
        write_err(@tui.ansi_error("HTTP " + status.to_string() + " from NyxID:\n" + resp) + "\n")
        return 1
      }
      write_out(@tui.ansi_bold() + @tui.ansi_green() + "✓ Connected " + slug + @tui.ansi_reset() + "\n")
      write_out(@tui.ansi_info("You can now call:") + "\n")
      write_out("  pimbt --api nyxid-gateway --model <model> \"your prompt\"\n")
      0
    }
  }
}

fn run_providers_disconnect(
  provider_id : String,
  base_url : String,
  bearer : String,
  runtime : CliHostRuntime
) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write
  let url = trim_slash_right(base_url) + @ai.nyxid_disconnect_path(provider_id)

  match host_delete_bearer(url, bearer) {
    Err(msg) => {
      write_err(@tui.ansi_error("request failed: " + msg) + "\n")
      1
    }
    Ok((status, resp)) => {
      if status == 401 {
        write_err(@tui.ansi_error("NyxID rejected the token (401). Run `pimbt login` to re-authenticate.") + "\n")
        return 3
      }
      if status == 404 {
        write_err(@tui.ansi_error("provider not found: " + provider_id) + "\n")
        return 4
      }
      if status >= 400 {
        write_err(@tui.ansi_error("HTTP " + status.to_string() + " from NyxID:\n" + resp) + "\n")
        return 1
      }
      write_out(@tui.ansi_bold() + @tui.ansi_green() + "✓ Disconnected " + provider_id + @tui.ansi_reset() + "\n")
      0
    }
  }
}

fn trim_slash_right(s : String) -> String {
  if s.has_suffix("/") { s[:s.length() - 1].to_string() } else { s }
}
