///| `pimbt login` 命令的实现。
///
/// 流程：
/// 1. 解析 provider / client_id / base_url / redirect_uri
/// 2. 生成 PKCE verifier/challenge 和 state
/// 3. 启动本地 callback server (默认 localhost:54545)
/// 4. 打开浏览器到授权 URL
/// 5. 接收 code + state
/// 6. POST /oauth/token 换 access_token
/// 7. 保存到 ~/.pimbt/nyxid-credentials.json

pub(all) struct LoginConfig {
  provider : String
  base_url : String
  client_id : String
  client_secret : String?
  redirect_port : Int
  scope : String
  credentials_path : String
  timeout_seconds : Int
}

pub fn LoginConfig::defaults(cwd : String) -> LoginConfig {
  {
    provider: "nyxid",
    base_url: @ai.nyxid_default_base_url,
    client_id: "",
    client_secret: None,
    redirect_port: 54545,
    scope: "",  // empty = use client's allowed_scopes on server side
    credentials_path: credentials_default_path(cwd),
    timeout_seconds: 300,
  }
}

///| 默认凭证存储路径（优先 HOME，回退 cwd）。
pub fn credentials_default_path(cwd : String) -> String {
  let home = host_env_var("HOME").unwrap_or(cwd)
  if home.has_suffix("/") {
    home + ".pimbt/nyxid-credentials.json"
  } else {
    home + "/.pimbt/nyxid-credentials.json"
  }
}

///| 运行 NyxID 登录流程（简化 CLI 流程，不需要 client_id）。
///
/// 1. GET /api/v1/public/config 发现 frontend URL
/// 2. 打开浏览器到 {frontend}/cli-auth?port=X&state=Y
/// 3. 等 frontend 通过浏览器端 fetch 回推 tokens 到 localhost:X/callback
/// 4. 保存 tokens 到 ~/.pimbt/nyxid-credentials.json
pub fn run_nyxid_login(
  config : LoginConfig,
  runtime : CliHostRuntime
) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write

  // Step 1: discover frontend URL
  let config_url = trim_trail_slash(config.base_url) + @ai.nyxid_public_config_path
  let (status, body) = match host_get(config_url) {
    Ok(result) => result
    Err(msg) => {
      write_err(@tui.ansi_error("Failed to reach NyxID at " + config.base_url + ": " + msg) + "\n")
      return 3
    }
  }
  if status >= 400 {
    write_err(@tui.ansi_error("NyxID returned HTTP " + status.to_string() + ": " + body) + "\n")
    return 3
  }
  let config_json = try { @json.parse(body) } catch {
    _ => {
      write_err(@tui.ansi_error("Failed to parse public config: " + body) + "\n")
      return 3
    }
  }
  let frontend_url = match @ai.parse_nyxid_public_config(config_json) {
    Ok(url) => url
    Err(msg) => {
      write_err(@tui.ansi_error(msg) + "\n")
      return 3
    }
  }

  // Step 2: open browser to /cli-auth
  let state = host_random_state()
  let auth_url = @ai.build_nyxid_cli_auth_url(
    frontend_url,
    config.redirect_port,
    state,
    client_ua="pimbt",
  )

  write_out(
    @tui.ansi_bold() + "Opening browser for NyxID login..." + @tui.ansi_reset() + "\n" +
    @tui.ansi_info("If the browser does not open, visit:") + "\n" +
    "  " + auth_url + "\n\n" +
    @tui.ansi_info("Waiting for callback on http://127.0.0.1:" + config.redirect_port.to_string() + "/callback (timeout " + config.timeout_seconds.to_string() + "s)...") + "\n",
  )
  host_open_browser(auth_url)

  // Step 3: wait for tokens
  let (access_token, refresh_token_opt, returned_state) = match host_wait_cli_callback(
    config.redirect_port,
    state,
    config.timeout_seconds * 1000,
  ) {
    Ok(result) => result
    Err(msg) => {
      write_err(@tui.ansi_error("Login failed: " + msg) + "\n")
      return 4
    }
  }
  if returned_state != state {
    write_err(@tui.ansi_error("State mismatch (possible CSRF); aborting.") + "\n")
    return 5
  }

  // Step 4: build credentials + persist
  let now = now_epoch_seconds(runtime)
  let creds = @ai.nyxid_cli_credentials_from_callback(
    access_token,
    refresh_token_opt,
    now,
  )

  let creds_json = @ai.nyxid_credentials_to_json(creds, config.base_url, "")
  let creds_text = creds_json.stringify(escape_slash=false)
  match (runtime.write_text)(config.credentials_path, creds_text) {
    Ok(_) => ()
    Err(msg) => {
      write_err(@tui.ansi_error("Failed to save credentials to " + config.credentials_path + ": " + msg) + "\n")
      return 6
    }
  }

  write_out(
    @tui.ansi_bold() + @tui.ansi_green() + "✓ Login successful!" + @tui.ansi_reset() + "\n" +
    @tui.ansi_info("Credentials saved to " + config.credentials_path) + "\n\n",
  )

  // Self-check: probe /api/v1/llm/status to show connected providers or guide the user.
  show_post_login_status(config.base_url, access_token, runtime)

  0
}

///| 登录后自检：查询 NyxID 的 LLM status，告诉用户下一步要做什么。
///
/// 三种情况：
/// - 已连接 provider → 显示列表 + 怎么调模型
/// - 没连接任何 provider → 提示用 `pimbt providers connect`
/// - 请求失败 → 静默忽略（login 本身已经成功）
fn show_post_login_status(base_url : String, bearer : String, runtime : CliHostRuntime) -> Unit {
  let status_url = trim_trail_slash(base_url) + @ai.nyxid_llm_status_path
  match host_get_bearer(status_url, bearer) {
    Ok((status, body)) if status < 400 => {
      let json = try { @json.parse(body) } catch { _ => return }
      let parsed = match @ai.parse_nyxid_llm_status(json) {
        Ok(s) => s
        Err(_) => return
      }
      let connected : Array[@ai.LlmProviderStatus] = []
      for p in parsed.providers {
        if p.status == "connected" || p.status == "ready" {
          connected.push(p)
        }
      }
      let write_out = runtime.stdout_write
      if connected.length() > 0 {
        write_out(@tui.ansi_section_header("Connected Providers") + "\n")
        for p in connected {
          write_out("  " + @tui.ansi_green() + "✓" + @tui.ansi_reset() + " " + p.provider_slug + "\n")
        }
        write_out("\n" + @tui.ansi_info("You're all set. Try:") + "\n")
        if parsed.supported_models.length() > 0 {
          write_out("  pimbt --api nyxid-gateway --model " + parsed.supported_models[0] + " \"hello\"\n")
        } else {
          write_out("  pimbt --api nyxid-gateway --model <model-id> \"hello\"\n")
        }
      } else {
        write_out(@tui.ansi_section_header("No LLM providers connected yet") + "\n")
        write_out(@tui.ansi_info("Add one with:") + "\n")
        write_out("  pimbt providers connect openai     " + @tui.ansi_dim() + "# or anthropic, gemini, mistral..." + @tui.ansi_reset() + "\n\n")
        write_out(@tui.ansi_info("Or configure in the web panel: " + base_url + "/providers") + "\n")
      }
    }
    _ => ()  // Silently skip on error; login itself succeeded
  }
}

///| 兼容保留：标准 OAuth 2.0 + PKCE 登录流程（需要 client_id）。
///
/// 在 pimbt 中一般不用这个，保留给需要自定义 OAuth 客户端的场景。
pub fn run_nyxid_oauth_login(
  config : LoginConfig,
  runtime : CliHostRuntime
) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write

  if config.client_id == "" {
    write_err(@tui.ansi_error("client_id is required for OAuth flow. Pass --client-id <id> or set NYXID_CLIENT_ID env var.") + "\n")
    return 2
  }

  let redirect_uri = "http://localhost:" + config.redirect_port.to_string() + "/callback"
  let pkce = host_generate_pkce()
  let state = host_random_state()

  let auth_url = @ai.build_nyxid_auth_url(
    config.base_url,
    config.client_id,
    redirect_uri,
    state,
    pkce,
    scope=config.scope,
  )

  write_out(
    @tui.ansi_bold() + "Opening browser for NyxID login..." + @tui.ansi_reset() + "\n" +
    @tui.ansi_info("If the browser does not open, visit this URL manually:") + "\n" +
    "  " + auth_url + "\n\n" +
    @tui.ansi_info("Waiting for callback on " + redirect_uri + " (timeout " + config.timeout_seconds.to_string() + "s)...") + "\n",
  )

  host_open_browser(auth_url)

  let (code, returned_state) = match host_wait_oauth_callback(
    config.redirect_port,
    state,
    config.timeout_seconds * 1000,
  ) {
    Ok(result) => result
    Err(msg) => {
      write_err(@tui.ansi_error("OAuth callback failed: " + msg) + "\n")
      return 3
    }
  }

  if returned_state != state {
    write_err(@tui.ansi_error("State mismatch (possible CSRF); aborting.") + "\n")
    return 4
  }

  // Exchange code for token
  write_out(@tui.ansi_info("Exchanging code for access token...") + "\n")

  let token_url = trim_trail_slash(config.base_url) + @ai.nyxid_oauth_token_path
  let form = @ai.build_nyxid_token_form(
    code,
    config.client_id,
    config.client_secret,
    redirect_uri,
    pkce.verifier,
  )
  let form_body = @ai.encode_form(form)

  let (status, body) = match host_post_form(token_url, form_body) {
    Ok(result) => result
    Err(msg) => {
      write_err(@tui.ansi_error("Token request failed: " + msg) + "\n")
      return 5
    }
  }

  let json = try {
    @json.parse(body)
  } catch {
    _ => {
      write_err(@tui.ansi_error("Failed to parse token response (status " + status.to_string() + "): " + body) + "\n")
      return 6
    }
  }

  // Parse response with current timestamp
  let now = now_epoch_seconds(runtime)
  let creds = match @ai.parse_nyxid_token_response(json, now) {
    Ok(c) => c
    Err(e) => {
      write_err(@tui.ansi_error("Token exchange failed: " + @ai.oauth_error_message(e)) + "\n")
      return 7
    }
  }

  // Save credentials
  let creds_json = @ai.nyxid_credentials_to_json(creds, config.base_url, config.client_id)
  let creds_text = creds_json.stringify(escape_slash=false)
  match (runtime.write_text)(config.credentials_path, creds_text) {
    Ok(_) => ()
    Err(msg) => {
      write_err(@tui.ansi_error("Failed to save credentials to " + config.credentials_path + ": " + msg) + "\n")
      return 8
    }
  }

  write_out(
    @tui.ansi_bold() + @tui.ansi_green() + "✓ Login successful!" + @tui.ansi_reset() + "\n" +
    @tui.ansi_info("Credentials saved to " + config.credentials_path) + "\n" +
    @tui.ansi_info("You can now use: pimbt --api nyxid-gateway --model <model> \"hello\"") + "\n",
  )

  0
}

///| 从保存的文件读取 NyxID 凭证。
pub fn load_nyxid_credentials(
  runtime : CliHostRuntime,
  path : String
) -> Result[@ai.NyxidStoredCredentials, String] {
  match (runtime.read_text)(path) {
    Err(msg) => Err(msg)
    Ok(text) => {
      let json = try {
        @json.parse(text)
      } catch {
        _ => return Err("invalid JSON in credentials file")
      }
      @ai.parse_nyxid_stored_credentials(json)
    }
  }
}

///| 刷新已过期的 access token。成功时写回新凭证。
pub fn refresh_nyxid_credentials(
  runtime : CliHostRuntime,
  stored : @ai.NyxidStoredCredentials,
  credentials_path : String
) -> Result[@ai.NyxidStoredCredentials, String] {
  let refresh_token = match stored.credentials.refresh_token {
    Some(rt) => rt
    None => return Err("no refresh_token stored; run `pimbt login` again")
  }
  let form = @ai.build_nyxid_refresh_form(refresh_token, stored.client_id, None)
  let form_body = @ai.encode_form(form)
  let token_url = trim_trail_slash(stored.base_url) + @ai.nyxid_oauth_token_path

  let (_, body) = match host_post_form(token_url, form_body) {
    Ok(r) => r
    Err(msg) => return Err("refresh failed: " + msg)
  }
  let json = try {
    @json.parse(body)
  } catch {
    _ => return Err("invalid token response from refresh")
  }
  let now = now_epoch_seconds(runtime)
  let new_creds = match @ai.parse_nyxid_token_response(json, now) {
    Ok(c) => c
    Err(e) => return Err("refresh rejected: " + @ai.oauth_error_message(e))
  }

  // Preserve refresh_token if server didn't return a new one
  let preserved_refresh = match new_creds.refresh_token {
    Some(_) => new_creds.refresh_token
    None => stored.credentials.refresh_token
  }
  let final_creds : @ai.OAuthCredentials = { ..new_creds, refresh_token: preserved_refresh }
  let final_stored : @ai.NyxidStoredCredentials = {
    base_url: stored.base_url,
    client_id: stored.client_id,
    credentials: final_creds,
  }

  // Persist
  let creds_json = @ai.nyxid_credentials_to_json(final_creds, stored.base_url, stored.client_id)
  match (runtime.write_text)(credentials_path, creds_json.stringify(escape_slash=false)) {
    Ok(_) => Ok(final_stored)
    Err(msg) => Err("saved refreshed token but failed to persist: " + msg)
  }
}

fn trim_trail_slash(s : String) -> String {
  if s.has_suffix("/") { s[:s.length() - 1].to_string() } else { s }
}

fn now_epoch_seconds(runtime : CliHostRuntime) -> Int64 {
  // ISO 8601 timestamp → rough epoch seconds (YYYY-MM-DDTHH:MM:SS.sssZ)
  let iso = (runtime.now_iso)()
  parse_iso_to_epoch(iso)
}

///| 解析 ISO 8601 时间戳为 epoch seconds（近似，忽略闰秒等细节）。
fn parse_iso_to_epoch(iso : String) -> Int64 {
  // Expect format: YYYY-MM-DDTHH:MM:SS(.sss)?Z
  if iso.length() < 19 { return 0L }
  let year = parse_int_or(iso[0:4].to_string(), 1970)
  let month = parse_int_or(iso[5:7].to_string(), 1)
  let day = parse_int_or(iso[8:10].to_string(), 1)
  let hour = parse_int_or(iso[11:13].to_string(), 0)
  let minute = parse_int_or(iso[14:16].to_string(), 0)
  let second = parse_int_or(iso[17:19].to_string(), 0)
  days_from_civil(year, month, day) * 86400L +
    hour.to_int64() * 3600L +
    minute.to_int64() * 60L +
    second.to_int64()
}

fn parse_int_or(s : String, default : Int) -> Int {
  try @string.parse_int(s) catch {
    _ => default
  } noraise {
    n => n
  }
}

///| Howard Hinnant's civil_from_days algorithm (days since 1970-01-01).
fn days_from_civil(y : Int, m : Int, d : Int) -> Int64 {
  let year = if m <= 2 { y - 1 } else { y }
  let era = if year >= 0 { year / 400 } else { (year - 399) / 400 }
  let yoe = year - era * 400
  let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  (era.to_int64() * 146097L + doe.to_int64() - 719468L)
}
