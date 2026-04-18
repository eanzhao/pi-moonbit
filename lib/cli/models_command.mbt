///| `pimbt models` 命令的实现。
///
/// 调 NyxID 的 `GET /api/v1/llm/status` 端点，列出：
///   - providers: 用户已连接的 provider 及其状态 (ready/expired/not_connected)
///   - supported_models: 网关支持的 model id（用于传给 `--model`）
///
/// 认证用 Bearer（从 ~/.pimbt/nyxid-credentials.json 的 access_token 读取，
/// 或 `--bearer` 手动指定）。

pub fn run_models_command(config : ModelsConfig, runtime : CliHostRuntime) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write

  // Resolve Bearer token
  let (base_url, bearer) = match config.bearer_override {
    Some(tok) if tok.length() > 0 => (config.base_url, tok)
    _ => {
      match (runtime.read_text)(config.credentials_path) {
        Ok(text) => {
          let json = try { @json.parse(text) } catch {
            _ => {
              write_err(@tui.ansi_error("credentials file is not valid JSON: " + config.credentials_path) + "\n")
              return 2
            }
          }
          match @ai.parse_nyxid_stored_credentials(json) {
            Ok(stored) => (stored.base_url, stored.credentials.access_token)
            Err(msg) => {
              write_err(@tui.ansi_error("credentials file invalid: " + msg) + "\n")
              return 2
            }
          }
        }
        Err(_) => {
          write_err(@tui.ansi_error(
            "no NyxID credentials found at " + config.credentials_path +
            ".\nRun `pimbt login --client-id <your-client-id>` first.",
          ) + "\n")
          return 2
        }
      }
    }
  }

  let status_url = trim_slash_right(base_url) + @ai.nyxid_llm_status_path
  let status_json = match host_get_bearer(status_url, bearer) {
    Err(msg) => {
      write_err(@tui.ansi_error("request failed: " + msg) + "\n")
      return 1
    }
    Ok((status, body)) => {
      if status == 401 {
        write_err(@tui.ansi_error(
          "NyxID rejected the token (401). Run `pimbt login` to re-authenticate.",
        ) + "\n")
        return 3
      }
      if status >= 400 {
        write_err(@tui.ansi_error(
          "HTTP " + status.to_string() + " from NyxID:\n" + body,
        ) + "\n")
        return 1
      }
      try @json.parse(body) catch {
        _ => {
          write_err(@tui.ansi_error("response is not valid JSON:\n" + body) + "\n")
          return 1
        }
      } noraise {
        v => v
      }
    }
  }
  let parsed_status = match @ai.parse_nyxid_llm_status(status_json) {
    Ok(s) => s
    Err(msg) => {
      write_err(@tui.ansi_error(msg) + "\n")
      return 1
    }
  }

  // /api/v1/keys — user-registered services (Ollama / MLX / Mimo / ...).
  // Failure here is non-fatal: older NyxID deployments may lack this route,
  // and the built-in provider listing is still useful on its own.
  let keys_url = trim_slash_right(base_url) + @ai.nyxid_keys_path
  let user_services = fetch_user_services(keys_url, bearer)

  write_out(format_providers_and_services(parsed_status, user_services, bearer, base_url))
  0
}

fn collect_active_user_services(
  all : Array[@ai.NyxidUserService]
) -> Array[@ai.NyxidUserService] {
  let out : Array[@ai.NyxidUserService] = []
  for s in all {
    if s.active && s.service_type == "http" {
      out.push(s)
    }
  }
  out
}

///| GET /api/v1/keys and parse into active user services. Failure is swallowed:
/// older NyxID deployments may lack this route, and the built-in provider
/// listing is still useful on its own.
fn fetch_user_services(
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
    Ok(list) => collect_active_user_services(list)
    Err(_) => []
  }
}

///| 综合渲染：内建 provider + 用户 service + 每项的真实模型清单 + 路由通配符。
fn format_providers_and_services(
  status : @ai.LlmStatus,
  services : Array[@ai.NyxidUserService],
  bearer : String,
  base_url : String
) -> String {
  let sb = StringBuilder::new()

  // Built-in providers.
  sb.write_string(@tui.ansi_section_header("Connected Providers (built-in)") + "\n")
  if status.providers.length() == 0 {
    sb.write_string("  " + @tui.ansi_info("(none)") + "\n")
  } else {
    for p in status.providers {
      sb.write_string("  " + format_provider_entry(p) + "\n")
    }
  }
  sb.write_string("\n")

  // User-registered services (may be empty).
  sb.write_string(@tui.ansi_section_header("Connected Services (user-registered)") + "\n")
  if services.length() == 0 {
    sb.write_string(
      "  " + @tui.ansi_dim() +
      "(none — add one via `nyxid service add <slug>` on the NyxID CLI)" +
      @tui.ansi_reset() + "\n",
    )
  } else {
    for s in services {
      sb.write_string("  " + format_user_service_entry(s) + "\n")
    }
  }
  sb.write_string("\n")

  // Fan out real model IDs per source (best-effort; skips unreachable ones).
  sb.write_string(@tui.ansi_section_header("Models") + "\n")
  sb.write_string(
    "  " + @tui.ansi_dim() + "(fetched live from each provider/service)" +
    @tui.ansi_reset() + "\n",
  )
  let mut any_models = false
  for p in status.providers {
    if p.status != "ready" { continue }
    let models = fetch_provider_models(p.proxy_url, bearer, p.provider_slug)
    if models.length() == 0 { continue }
    any_models = true
    sb.write_string("  " + @tui.ansi_bold() + p.provider_slug + @tui.ansi_reset() + ":\n")
    for m in models {
      sb.write_string("    " + m + "\n")
    }
  }
  for s in services {
    if !is_user_service_llm_compatible(s) { continue }
    let models = fetch_user_service_models(base_url, bearer, s)
    if models.length() == 0 { continue }
    any_models = true
    sb.write_string("  " + @tui.ansi_bold() + s.slug + @tui.ansi_reset() + ":\n")
    for m in models {
      sb.write_string("    " + m + "\n")
    }
  }
  if !any_models {
    sb.write_string("  " + @tui.ansi_info("(none discovered live)") + "\n")
  }
  sb.write_string("\n")

  // Gateway routing patterns — kept for debugging / reference only.
  sb.write_string(@tui.ansi_section_header("Routing Patterns") + "\n")
  sb.write_string(
    "  " + @tui.ansi_dim() + "(prefix → provider map used by the gateway)" +
    @tui.ansi_reset() + "\n",
  )
  if status.supported_models.length() == 0 {
    sb.write_string("  " + @tui.ansi_info("(none)") + "\n")
  } else {
    for m in status.supported_models {
      sb.write_string("  " + m + "\n")
    }
  }

  sb.write_string("\n")
  sb.write_string(@tui.ansi_info(
    "Run `pimbt` to pick a model interactively.",
  ) + "\n")
  sb.to_string()
}

fn format_provider_entry(p : @ai.LlmProviderStatus) -> String {
  let (icon, colored_status) = match p.status {
    "ready" => ("✓", @tui.ansi_green() + p.status + @tui.ansi_reset())
    "expired" => ("⚠", @tui.ansi_yellow() + p.status + @tui.ansi_reset())
    "not_connected" => ("—", @tui.ansi_dim() + p.status + @tui.ansi_reset())
    _ => ("·", p.status)
  }
  let label = if p.provider_name == p.provider_slug {
    p.provider_slug
  } else {
    p.provider_name + " (" + p.provider_slug + ")"
  }
  icon + " " + label + " " + @tui.ansi_dim() + "[" + @tui.ansi_reset() +
  colored_status + @tui.ansi_dim() + "]" + @tui.ansi_reset()
}

fn format_user_service_entry(s : @ai.NyxidUserService) -> String {
  let (icon, colored_status) = match s.status {
    "active" => ("✓", @tui.ansi_green() + s.status + @tui.ansi_reset())
    "expired" => ("⚠", @tui.ansi_yellow() + s.status + @tui.ansi_reset())
    "pending" => ("⋯", @tui.ansi_yellow() + s.status + @tui.ansi_reset())
    _ => ("·", s.status)
  }
  let label = if s.label == s.slug {
    @tui.ansi_bold() + s.slug + @tui.ansi_reset()
  } else {
    @tui.ansi_bold() + s.slug + @tui.ansi_reset() + " " +
    @tui.ansi_dim() + "\"" + s.label + "\"" + @tui.ansi_reset()
  }
  let auth_hint = @tui.ansi_dim() + "auth=" + s.auth_method + @tui.ansi_reset()
  icon + " " + label + "  " + auth_hint + "  " +
  @tui.ansi_dim() + "[" + @tui.ansi_reset() + colored_status +
  @tui.ansi_dim() + "]" + @tui.ansi_reset()
}

///| 把 /api/v1/llm/status 的 JSON 格式化成人类可读输出。
///
/// 预期 shape（LlmStatusResponse）：
/// ```json
/// {
///   "providers": [{ "name": "openai", "status": "ready", ... }, ...],
///   "gateway_url": "...",
///   "supported_models": ["gpt-5.4", "claude-sonnet-4-5", ...]
/// }
/// ```
pub fn format_llm_status(json : Json) -> String {
  let sb = StringBuilder::new()

  // Providers
  sb.write_string(@tui.ansi_section_header("Connected Providers") + "\n")
  match json {
    Object({ "providers": Array(providers), .. }) => {
      if providers.length() == 0 {
        sb.write_string("  " + @tui.ansi_info("(none — add providers in the NyxID web panel)") + "\n")
      } else {
        for p in providers {
          sb.write_string("  " + format_provider(p) + "\n")
        }
      }
    }
    _ => sb.write_string("  " + @tui.ansi_info("(providers field missing in response)") + "\n")
  }
  sb.write_string("\n")

  // Routing patterns (NOT real model IDs — the gateway uses these to decide
  // which provider to forward to; you pass a concrete id like gpt-4o, not gpt-*).
  sb.write_string(@tui.ansi_section_header("Routing Patterns") + "\n")
  sb.write_string("  " + @tui.ansi_dim() +
    "(prefix → provider map used by the gateway)" + @tui.ansi_reset() + "\n")
  match json {
    Object({ "supported_models": Array(models), .. }) => {
      if models.length() == 0 {
        sb.write_string("  " + @tui.ansi_info("(none)") + "\n")
      } else {
        for m in models {
          match m {
            String(id) => sb.write_string("  " + id + "\n")
            _ => ()
          }
        }
      }
    }
    _ => sb.write_string("  " + @tui.ansi_info("(supported_models field missing)") + "\n")
  }

  // Usage hint
  sb.write_string("\n")
  sb.write_string(@tui.ansi_info(
    "For an interactive picker with real model IDs, run: pimbt",
  ) + "\n")
  sb.write_string(@tui.ansi_info(
    "Or pass one directly: pimbt --api nyxid-gateway --model <id> \"...\"",
  ) + "\n")

  sb.to_string()
}

fn format_provider(p : Json) -> String {
  match p {
    Object(fields) => {
      // NyxID's LlmProviderStatus uses provider_slug + provider_name, not "name".
      let slug = match fields.get("provider_slug") {
        Some(String(s)) => s
        _ => "(unknown)"
      }
      let display_name = match fields.get("provider_name") {
        Some(String(s)) => s
        _ => slug
      }
      let status = match fields.get("status") {
        Some(String(s)) => s
        _ => "?"
      }
      let (icon, colored_status) = match status {
        "ready" => ("✓", @tui.ansi_green() + status + @tui.ansi_reset())
        "expired" => ("⚠", @tui.ansi_yellow() + status + @tui.ansi_reset())
        "not_connected" => ("—", @tui.ansi_dim() + status + @tui.ansi_reset())
        _ => ("·", status)
      }
      let label = if display_name == slug { slug } else { display_name + " (" + slug + ")" }
      icon + " " + label + " " + @tui.ansi_dim() + "[" + @tui.ansi_reset() + colored_status + @tui.ansi_dim() + "]" + @tui.ansi_reset()
    }
    _ => "(malformed provider entry)"
  }
}
