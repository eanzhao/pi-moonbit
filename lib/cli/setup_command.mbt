///| `pimbt setup` — 一站式向导：登录 → 连接 provider → 选默认 model。
///
/// 设计目标：让一个新用户从 0 到第一次成功调用 LLM 只需要回答几个问题，
/// 不用记 `--api` / `--model` / 各种 provider slug。

pub(all) struct SetupConfig {
  base_url : String
  credentials_path : String
  user_config_path : String
}

pub fn SetupConfig::defaults(cwd : String) -> SetupConfig {
  {
    base_url: @ai.nyxid_default_base_url,
    credentials_path: credentials_default_path(cwd),
    user_config_path: pimbt_user_config_path(cwd),
  }
}

pub fn run_setup_command(config : SetupConfig, runtime : CliHostRuntime) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write
  write_out(@tui.ansi_section_header("pimbt setup") + "\n\n")

  // Step 1: ensure logged in
  if !nyxid_credentials_exist(runtime, config.credentials_path) {
    write_out(@tui.ansi_info("You're not logged in to NyxID yet.") + "\n")
    write_out("Run " + @tui.ansi_bold() + "pimbt login" + @tui.ansi_reset() +
      " first, then re-run " + @tui.ansi_bold() + "pimbt setup" + @tui.ansi_reset() + ".\n")
    return 2
  }
  write_out(@tui.ansi_green() + "✓" + @tui.ansi_reset() + " Logged in to NyxID (" + config.base_url + ")\n\n")

  // Step 2: fetch /llm/status and inspect connected providers
  let (base_url, bearer) = match resolve_nyxid_bearer(config.base_url, None, config.credentials_path, runtime) {
    Ok(r) => r
    Err(msg) => {
      write_err(@tui.ansi_error(msg) + "\n")
      return 2
    }
  }
  let status = match fetch_llm_status(base_url, bearer) {
    Ok(s) => s
    Err(msg) => {
      write_err(@tui.ansi_error("Could not reach NyxID: " + msg) + "\n")
      return 3
    }
  }

  let connected = collect_ready_providers(status.providers)

  // Step 3: if no providers, prompt to connect one
  let after_connect_status = if connected.length() == 0 {
    write_out(@tui.ansi_section_header("No LLM providers connected") + "\n")
    write_out("Choose a provider to add (or press Enter to skip):\n\n")
    let candidate_slugs = ["openai", "anthropic", "gemini", "mistral", "groq", "xai", "deepseek", "cohere"]
    for i = 0; i < candidate_slugs.length(); i = i + 1 {
      write_out("  " + (i + 1).to_string() + ". " + candidate_slugs[i] + "\n")
    }
    write_out("\n")
    match prompt_choice(runtime, "Choice [1-" + candidate_slugs.length().to_string() + "]: ", candidate_slugs.length()) {
      None => {
        write_out(@tui.ansi_info("Skipped. Add providers later via `pimbt providers connect <slug>`.") + "\n")
        status
      }
      Some(idx) => {
        let slug = candidate_slugs[idx - 1]
        write_out("Enter the API key for " + @tui.ansi_bold() + slug + @tui.ansi_reset() + " (e.g. sk-...): ")
        let key = match (runtime.read_line)("") {
          Some(k) => k.trim().to_string()
          None => ""
        }
        if key.length() == 0 {
          write_err(@tui.ansi_error("API key cannot be empty.") + "\n")
          return 4
        }
        match connect_provider(base_url, bearer, slug, key) {
          Err(msg) => {
            write_err(@tui.ansi_error("Failed to connect: " + msg) + "\n")
            return 5
          }
          Ok(_) => {
            write_out(@tui.ansi_green() + "✓" + @tui.ansi_reset() + " Connected " + slug + "\n\n")
            // Re-fetch status to get updated supported_models
            match fetch_llm_status(base_url, bearer) {
              Ok(s) => s
              Err(_) => status  // Fall back to old snapshot
            }
          }
        }
      }
    }
  } else {
    write_out(@tui.ansi_section_header("Connected providers") + "\n")
    for p in connected {
      write_out("  " + @tui.ansi_green() + "✓" + @tui.ansi_reset() + " " + p.provider_slug + "\n")
    }
    write_out("\n")
    status
  }

  // Step 4: pick a default model — reuse the two-level source→model picker
  // so the user sees real model ids rather than routing wildcards. Includes
  // both built-in providers and user-registered services from /api/v1/keys.
  ignore(after_connect_status)
  let sources_now = collect_model_sources(base_url, bearer)
  let chosen : String? = if sources_now.length() == 0 {
    write_out(@tui.ansi_info("No models available yet — add a provider or service and re-run `pimbt setup`.") + "\n")
    None
  } else {
    let picked_source = if sources_now.length() == 1 {
      Some(sources_now[0])
    } else {
      pick_model_source(runtime, sources_now)
    }
    match picked_source {
      None => None
      Some(s) => pick_model_from_source(runtime, base_url, bearer, s)
    }
  }

  // Step 5: persist preferences
  let user_config : PimbtUserConfig = {
    default_api: Some("nyxid-gateway"),
    default_model: chosen,
    default_provider: None,
    default_thinking: None,
  }
  match save_user_config(runtime, config.user_config_path, user_config) {
    Err(msg) => {
      write_err(@tui.ansi_error("Failed to save config: " + msg) + "\n")
      return 6
    }
    Ok(_) => ()
  }

  write_out("\n" + @tui.ansi_green() + "✓" + @tui.ansi_reset() + " Saved preferences to " + config.user_config_path + "\n\n")
  match chosen {
    Some(model) => {
      write_out(@tui.ansi_info("You're all set. Try:") + "\n")
      write_out("  " + @tui.ansi_bold() + "pimbt \"hello\"" + @tui.ansi_reset() +
        @tui.ansi_dim() + "    # uses " + model + " automatically" + @tui.ansi_reset() + "\n")
    }
    None => {
      write_out(@tui.ansi_info("You're all set. Try:") + "\n")
      write_out("  " + @tui.ansi_bold() + "pimbt --model <id> \"hello\"" + @tui.ansi_reset() + "\n")
    }
  }
  0
}

///| 提示用户在 [1, max] 范围内选一个数字。Enter 跳过返回 None。
fn prompt_choice(runtime : CliHostRuntime, prompt : String, max : Int) -> Int? {
  match (runtime.read_line)(prompt) {
    None => None
    Some(line) => {
      let trimmed = line.trim().to_string()
      if trimmed.length() == 0 { return None }
      match (try? @string.parse_int(trimmed)) {
        Ok(n) if n >= 1 && n <= max => Some(n)
        _ => None
      }
    }
  }
}

fn fetch_llm_status(base_url : String, bearer : String) -> Result[@ai.LlmStatus, String] {
  let url = trim_slash_right(base_url) + @ai.nyxid_llm_status_path
  let (status, body) = match host_get_bearer(url, bearer) {
    Ok(r) => r
    Err(msg) => return Err(msg)
  }
  if status == 401 {
    return Err("NyxID rejected the token (401). Run `pimbt login` again.")
  }
  if status >= 400 {
    return Err("HTTP " + status.to_string() + " from NyxID: " + body)
  }
  let json = try { @json.parse(body) } catch {
    _ => return Err("invalid JSON in /llm/status response")
  }
  @ai.parse_nyxid_llm_status(json)
}

fn collect_ready_providers(providers : Array[@ai.LlmProviderStatus]) -> Array[@ai.LlmProviderStatus] {
  let result : Array[@ai.LlmProviderStatus] = []
  for p in providers {
    if p.status == "ready" {
      result.push(p)
    }
  }
  result
}

fn connect_provider(base_url : String, bearer : String, slug : String, api_key : String) -> Result[Unit, String] {
  let url = trim_slash_right(base_url) + @ai.nyxid_connect_api_key_path(slug)
  let body = @ai.build_nyxid_connect_api_key_body(api_key)
  let (status, resp) = match host_post_json_bearer(url, body.stringify(escape_slash=false), bearer) {
    Ok(r) => r
    Err(msg) => return Err(msg)
  }
  if status >= 400 {
    return Err("HTTP " + status.to_string() + ": " + resp)
  }
  Ok(())
}

///| 交互式选模型 — 当用户跑 `pimbt --api nyxid-gateway` 但没传 `--model` 时调用。
///
/// 两层流程：
/// 1. 列出所有可用 **ModelSource**（内建 provider + 用户自注册的 service，
///    见 NyxID `/api/v1/keys`），用户选一个。
/// 2. 从该来源拉真实 model id，用户再选一个。
///
/// 只有一个来源时跳过第 1 步；列表太长时用方向键导航。
/// 返回选中的 model id；如果用户取消或没有可用来源，返回 None。
pub fn pick_model_interactive(
  runtime : CliHostRuntime,
  base_url : String,
  credentials_path : String
) -> String? {
  let (base, bearer) = match resolve_nyxid_bearer(
    base_url, None, credentials_path, runtime,
  ) {
    Ok(r) => r
    Err(_) => return None
  }
  let sources = collect_model_sources(base, bearer)
  if sources.length() == 0 {
    (runtime.stdout_write)(
      @tui.ansi_info(
        "No LLM sources available. Run `pimbt providers connect <slug>` " +
        "or register a service on NyxID first.",
      ) + "\n",
    )
    return None
  }
  let source = match sources.length() {
    1 => sources[0]
    _ =>
      match pick_model_source(runtime, sources) {
        Some(s) => s
        None => return None
      }
  }
  pick_model_from_source(runtime, base, bearer, source)
}

///| 汇总所有可用模型来源：ready 状态的内建 provider + 看起来像 LLM 的 user service。
///
/// 返回值已按"先内建、后 user service"排好序，方便 picker 展示。
fn collect_model_sources(
  base_url : String,
  bearer : String
) -> Array[ModelSource] {
  let out : Array[ModelSource] = []

  // Built-in providers (ready only).
  match fetch_llm_status(base_url, bearer) {
    Ok(status) =>
      for p in status.providers {
        if p.status == "ready" {
          out.push(BuiltinProvider(p))
        }
      }
    Err(_) => () // /llm/status failure → fall through, user services may still work
  }

  // User-registered services (filter to OpenAI-compatible LLM-like ones).
  let keys_url = trim_slash_right(base_url) + @ai.nyxid_keys_path
  match host_get_bearer(keys_url, bearer) {
    Ok((status, body)) if status < 400 => {
      let json = try @json.parse(body) catch {
        _ => return out
      } noraise {
        v => v
      }
      match @ai.parse_nyxid_keys(json) {
        Ok(list) =>
          for s in list {
            if is_user_service_llm_compatible(s) {
              out.push(UserService(s))
            }
          }
        Err(_) => ()
      }
    }
    _ => ()
  }
  out
}

///| 让用户在 ModelSource 列表里挑一个。取消返回 None。
fn pick_model_source(
  runtime : CliHostRuntime,
  sources : Array[ModelSource]
) -> ModelSource? {
  let labels : Array[String] = []
  for s in sources {
    let kind_tag = match s {
      BuiltinProvider(_) => @tui.ansi_dim() + "[built-in]" + @tui.ansi_reset()
      UserService(_) => @tui.ansi_dim() + "[service]" + @tui.ansi_reset()
    }
    labels.push(model_source_label(s) + "  " + kind_tag)
  }
  let title = @tui.ansi_section_header("Pick a provider or service")
  let idx = host_select_from_list(title, labels, 0)
  if idx < 0 || idx >= sources.length() {
    (runtime.stderr_write)(@tui.ansi_info("Cancelled.") + "\n")
    None
  } else {
    Some(sources[idx])
  }
}

///| 从指定 ModelSource 拉真实 model 列表并让用户挑一个。失败时允许手动输入。
fn pick_model_from_source(
  runtime : CliHostRuntime,
  base_url : String,
  bearer : String,
  source : ModelSource
) -> String? {
  let source_name = match source {
    BuiltinProvider(p) => p.provider_slug
    UserService(s) => s.slug
  }
  let models = fetch_models_for_source(base_url, bearer, source)
  if models.length() == 0 {
    (runtime.stdout_write)(
      @tui.ansi_info(
        "No models discovered for " + source_name +
        ". Enter a model id manually (or press Enter to skip):",
      ) + "\n",
    )
    match (runtime.read_line)("model> ") {
      Some(line) => {
        let trimmed = line.trim().to_string()
        if trimmed.length() == 0 { None } else { Some(trimmed) }
      }
      None => None
    }
  } else {
    let title = @tui.ansi_section_header("Pick a model (" + source_name + ")")
    let idx = host_select_from_list(title, models, 0)
    if idx < 0 || idx >= models.length() {
      (runtime.stderr_write)(@tui.ansi_info("Cancelled.") + "\n")
      None
    } else {
      Some(models[idx])
    }
  }
}
