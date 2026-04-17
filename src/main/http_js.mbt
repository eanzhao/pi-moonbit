///| 通过 JS fetch API 进行 OpenAI 兼容的流式 SSE 请求。
/// 接收请求体 JSON，返回完整 SSE 文本（同步阻塞直到流结束）。
extern "js" fn host_fetch_sse_ffi(url : String, body : String, api_key : String, extra_headers : String) -> Array[String] =
  #|(url, body, apiKey, extraHeaders) => {
  #|  try {
  #|    const headers = { "Content-Type": "application/json" };
  #|    if (apiKey) headers["Authorization"] = "Bearer " + apiKey;
  #|    if (extraHeaders) {
  #|      try { Object.assign(headers, JSON.parse(extraHeaders)); } catch {}
  #|    }
  #|    const http = require("http");
  #|    const https = require("https");
  #|    const { URL } = require("url");
  #|    const parsed = new URL(url);
  #|    const lib = parsed.protocol === "https:" ? https : http;
  #|    const lines = [];
  #|    const result = (() => {
  #|      return new Promise((resolve, reject) => {
  #|        const req = lib.request(parsed, {
  #|          method: "POST",
  #|          headers: headers,
  #|          timeout: 300000,
  #|        }, (res) => {
  #|          if (res.statusCode >= 400) {
  #|            let body = "";
  #|            res.on("data", c => body += c);
  #|            res.on("end", () => reject(new Error("HTTP " + res.statusCode + ": " + body.slice(0, 500))));
  #|            return;
  #|          }
  #|          let buf = "";
  #|          res.on("data", (chunk) => {
  #|            buf += chunk;
  #|            let idx;
  #|            while ((idx = buf.indexOf("\n")) !== -1) {
  #|              lines.push(buf.slice(0, idx));
  #|              buf = buf.slice(idx + 1);
  #|            }
  #|          });
  #|          res.on("end", () => {
  #|            if (buf.length > 0) lines.push(buf);
  #|            resolve();
  #|          });
  #|          res.on("error", reject);
  #|        });
  #|        req.on("error", reject);
  #|        req.write(body);
  #|        req.end();
  #|      });
  #|    })();
  #|    // spawnSync trick: block the event loop until promise resolves
  #|    const { execSync } = require("child_process");
  #|    const tmp = require("os").tmpdir() + "/pi-mb-sse-" + Date.now() + ".js";
  #|    require("fs").writeFileSync(tmp, `
  #|      const http = require("http");
  #|      const https = require("https");
  #|      const { URL } = require("url");
  #|      const parsed = new URL(${JSON.stringify(url)});
  #|      const lib = parsed.protocol === "https:" ? https : http;
  #|      const req = lib.request(parsed, {
  #|        method: "POST",
  #|        headers: ${JSON.stringify(headers)},
  #|        timeout: 300000,
  #|      }, (res) => {
  #|        if (res.statusCode >= 400) {
  #|          let body = "";
  #|          res.on("data", c => body += c);
  #|          res.on("end", () => {
  #|            process.stdout.write(JSON.stringify(["err", "HTTP " + res.statusCode + ": " + body.slice(0, 500)]));
  #|          });
  #|          return;
  #|        }
  #|        const lines = [];
  #|        let buf = "";
  #|        res.on("data", (chunk) => {
  #|          buf += chunk;
  #|          let idx;
  #|          while ((idx = buf.indexOf("\\n")) !== -1) {
  #|            lines.push(buf.slice(0, idx));
  #|            buf = buf.slice(idx + 1);
  #|          }
  #|        });
  #|        res.on("end", () => {
  #|          if (buf.length > 0) lines.push(buf);
  #|          process.stdout.write(JSON.stringify(["ok", ...lines]));
  #|        });
  #|        res.on("error", (e) => {
  #|          process.stdout.write(JSON.stringify(["err", e.message]));
  #|        });
  #|      });
  #|      req.on("error", (e) => {
  #|        process.stdout.write(JSON.stringify(["err", e.message]));
  #|      });
  #|      req.write(${JSON.stringify(body)});
  #|      req.end();
  #|    `);
  #|    const out = execSync("node " + JSON.stringify(tmp), {
  #|      maxBuffer: 100 * 1024 * 1024,
  #|      timeout: 300000,
  #|    });
  #|    try { require("fs").unlinkSync(tmp); } catch {}
  #|    const parsed2 = JSON.parse(out.toString());
  #|    return parsed2;
  #|  } catch (e) {
  #|    return ["err", e.message || String(e)];
  #|  }
  #|}

///| 发起 Anthropic Messages API 流式请求并通过 EventHandler 推送事件。
fn host_anthropic_stream(
  model : @ai.Model,
  context : @ai.Context,
  options : @ai.StreamOptions,
  handler : @ai.EventHandler
) -> Unit!@ai.StreamError {
  let base_url = match model.base_url {
    Some(url) => url
    None => "https://api.anthropic.com"
  }
  let url = if base_url.has_suffix("/") {
    base_url + "v1/messages"
  } else {
    base_url + "/v1/messages"
  }
  let api_key = match options.api_key {
    Some(key) => key
    None => host_env_var("ANTHROPIC_API_KEY").unwrap_or("")
  }
  let body = @ai.build_anthropic_request_body(model, context, options)
  let extra_headers = Json::object({
    "x-api-key": Json::string(api_key),
    "anthropic-version": Json::string("2023-06-01"),
  })
  let result = host_fetch_sse_ffi(
    url,
    body.stringify(escape_slash=false),
    "",
    extra_headers.stringify(escape_slash=false),
  )
  if result.length() == 0 {
    raise @ai.StreamError("empty response from Anthropic")
  }
  if result[0] == "err" {
    let message = if result.length() > 1 { result[1] } else { "unknown error" }
    raise @ai.StreamError(message)
  }
  let state = @ai.AnthropicStreamState::new(model)
  let mut current_event_type = ""
  for i = 1; i < result.length(); i = i + 1 {
    let line = result[i].trim().to_string()
    if line.has_prefix("event:") {
      current_event_type = line[6:].trim().to_string()
    } else if line.has_prefix("data:") {
      let data = line[5:].trim().to_string()
      let events = @ai.parse_anthropic_sse_event(current_event_type, data, state)
      for event in events {
        handler.0(event)
      }
    }
  }
}

///| 发起 Gemini GenerateContent SSE 流式请求并通过 EventHandler 推送事件。
fn host_gemini_stream(
  model : @ai.Model,
  context : @ai.Context,
  options : @ai.StreamOptions,
  handler : @ai.EventHandler
) -> Unit!@ai.StreamError {
  let api_key = match options.api_key {
    Some(key) => key
    None =>
      match host_env_var("GOOGLE_API_KEY") {
        Some(key) => key
        None => host_env_var("GEMINI_API_KEY").unwrap_or("")
      }
  }
  let url = @ai.build_gemini_url(model, api_key)
  let body = @ai.build_gemini_request_body(model, context, options)
  let result = host_fetch_sse_ffi(
    url,
    body.stringify(escape_slash=false),
    "",
    "",
  )
  if result.length() == 0 {
    raise @ai.StreamError("empty response from Gemini")
  }
  if result[0] == "err" {
    let message = if result.length() > 1 { result[1] } else { "unknown error" }
    raise @ai.StreamError(message)
  }
  let state = @ai.GeminiStreamState::new(model)
  for i = 1; i < result.length(); i = i + 1 {
    let events = @ai.parse_gemini_sse_line(result[i], state)
    for event in events {
      handler.0(event)
    }
  }
  if !state.terminal_emitted {
    let events = @ai.parse_gemini_sse_line("data: [DONE]", state)
    for event in events {
      handler.0(event)
    }
  }
}

///| 发起 NyxID gateway (OpenAI 兼容) 的 SSE 流式请求。
///
/// NyxID 是一个凭证代理：用户在 NyxID 面板存储 LLM API keys，
/// pi-moonbit 只需要 NyxID 的 access token（OAuth）或 API key。
/// NyxID 服务端根据 model id 自动路由到对应 Provider 并注入凭证。
fn host_nyxid_stream(
  model : @ai.Model,
  context : @ai.Context,
  options : @ai.StreamOptions,
  handler : @ai.EventHandler
) -> Unit!@ai.StreamError {
  // 凭证查找优先级：
  //   1. options.api_key (Bearer)
  //   2. NYXID_TOKEN env var
  //   3. NYXID_API_KEY env var (X-API-Key header)
  //   4. ~/.pimbt/nyxid-credentials.json (Bearer)
  let (resolved_base_url, token, api_key) = resolve_nyxid_auth(model, options)
  let base_url = resolved_base_url
  let url = if base_url.has_suffix("/") {
    base_url + "api/v1/llm/gateway/v1/chat/completions"
  } else {
    base_url + "/api/v1/llm/gateway/v1/chat/completions"
  }
  let extra_headers = if api_key.length() > 0 && token.length() == 0 {
    Json::object({ "X-API-Key": Json::string(api_key) }).stringify(escape_slash=false)
  } else {
    ""
  }
  let body = @ai.build_openai_request_body(model, context, options)
  let result = host_fetch_sse_ffi(
    url,
    body.stringify(escape_slash=false),
    token,
    extra_headers,
  )
  if result.length() == 0 {
    raise @ai.StreamError("empty response from NyxID")
  }
  if result[0] == "err" {
    let message = if result.length() > 1 { result[1] } else { "unknown error" }
    raise @ai.StreamError(message)
  }
  let state = @ai.OpenAiStreamState::new(model)
  for i = 1; i < result.length(); i = i + 1 {
    let events = @ai.parse_openai_sse_line(result[i], state)
    for event in events {
      handler.0(event)
    }
  }
  if !state.terminal_emitted {
    let events = @ai.parse_openai_sse_line("data: [DONE]", state)
    for event in events {
      handler.0(event)
    }
  }
}

///| 发起 OpenAI 兼容的 SSE 流式请求并通过 EventHandler 推送事件。
fn host_openai_stream(
  model : @ai.Model,
  context : @ai.Context,
  options : @ai.StreamOptions,
  handler : @ai.EventHandler
) -> Unit!@ai.StreamError {
  let base_url = match model.base_url {
    Some(url) => url
    None => "https://api.openai.com/v1"
  }
  let url = if base_url.has_suffix("/") {
    base_url + "chat/completions"
  } else {
    base_url + "/chat/completions"
  }
  let api_key = match options.api_key {
    Some(key) => key
    None => host_env_var("OPENAI_API_KEY").unwrap_or("")
  }
  let body = @ai.build_openai_request_body(model, context, options)
  let result = host_fetch_sse_ffi(
    url,
    body.stringify(escape_slash=false),
    api_key,
    "",
  )
  if result.length() == 0 {
    raise @ai.StreamError("empty response from LLM")
  }
  if result[0] == "err" {
    let message = if result.length() > 1 { result[1] } else { "unknown error" }
    raise @ai.StreamError(message)
  }
  let state = @ai.OpenAiStreamState::new(model)
  for i = 1; i < result.length(); i = i + 1 {
    let events = @ai.parse_openai_sse_line(result[i], state)
    for event in events {
      handler.0(event)
    }
  }
  if !state.terminal_emitted {
    let events = @ai.parse_openai_sse_line("data: [DONE]", state)
    for event in events {
      handler.0(event)
    }
  }
}

///| 发起 Mistral OpenAI 兼容的 SSE 流式请求并通过 EventHandler 推送事件。
fn host_mistral_stream(
  model : @ai.Model,
  context : @ai.Context,
  options : @ai.StreamOptions,
  handler : @ai.EventHandler
) -> Unit!@ai.StreamError {
  let base_url = match model.base_url {
    Some(url) => url
    None => "https://api.mistral.ai/v1"
  }
  let url = if base_url.has_suffix("/") {
    base_url + "chat/completions"
  } else {
    base_url + "/chat/completions"
  }
  let api_key = match options.api_key {
    Some(key) => key
    None => host_env_var("MISTRAL_API_KEY").unwrap_or("")
  }
  let body = @ai.build_openai_request_body(model, context, options)
  let result = host_fetch_sse_ffi(
    url,
    body.stringify(escape_slash=false),
    api_key,
    "",
  )
  if result.length() == 0 {
    raise @ai.StreamError("empty response from LLM")
  }
  if result[0] == "err" {
    let message = if result.length() > 1 { result[1] } else { "unknown error" }
    raise @ai.StreamError(message)
  }
  let state = @ai.OpenAiStreamState::new(model)
  for i = 1; i < result.length(); i = i + 1 {
    let events = @ai.parse_openai_sse_line(result[i], state)
    for event in events {
      handler.0(event)
    }
  }
  if !state.terminal_emitted {
    let events = @ai.parse_openai_sse_line("data: [DONE]", state)
    for event in events {
      handler.0(event)
    }
  }
}

///| 解析 NyxID 认证信息：返回 (base_url, bearer_token, api_key)。
///
/// 从存储的凭证文件加载时，自动检测 access_token 是否即将过期
/// （60 秒缓冲），如果是则用 refresh_token 刷新并写回新凭证。
fn resolve_nyxid_auth(model : @ai.Model, options : @ai.StreamOptions) -> (String, String, String) {
  // 优先级 1: options.api_key as Bearer
  match options.api_key {
    Some(key) if key.length() > 0 => {
      let base = match model.base_url {
        Some(url) => url
        None => host_env_var("NYXID_BASE_URL").unwrap_or("https://nyx.chrono-ai.fun")
      }
      return (base, key, "")
    }
    _ => ()
  }
  // 优先级 2: NYXID_TOKEN env
  let env_token = host_env_var("NYXID_TOKEN").unwrap_or("")
  if env_token.length() > 0 {
    let base = match model.base_url {
      Some(url) => url
      None => host_env_var("NYXID_BASE_URL").unwrap_or("https://nyx.chrono-ai.fun")
    }
    return (base, env_token, "")
  }
  // 优先级 3: NYXID_API_KEY env
  let env_api_key = host_env_var("NYXID_API_KEY").unwrap_or("")
  if env_api_key.length() > 0 {
    let base = match model.base_url {
      Some(url) => url
      None => host_env_var("NYXID_BASE_URL").unwrap_or("https://nyx.chrono-ai.fun")
    }
    return (base, "", env_api_key)
  }
  // 优先级 4: stored credentials file (with auto-refresh)
  let creds_path = nyxid_credentials_path()
  let fallback_base = match model.base_url {
    Some(url) => url
    None => "https://nyx.chrono-ai.fun"
  }
  match host_read_text(creds_path) {
    Ok(text) => {
      let json = try { @json.parse(text) } catch { _ => return (fallback_base, "", "") }
      match @ai.parse_nyxid_stored_credentials(json) {
        Ok(stored) => {
          // Check expiry with 60-second buffer
          let now = nyxid_now_epoch_seconds()
          let refreshed = match stored.credentials.expires_at {
            Some(exp) if now + 60L >= exp => {
              // Token expired or about to — try refresh
              try_refresh_nyxid_token(stored, creds_path)
            }
            _ => stored  // Not expired, use as-is
          }
          (refreshed.base_url, refreshed.credentials.access_token, "")
        }
        Err(_) => (fallback_base, "", "")
      }
    }
    Err(_) => (fallback_base, "", "")
  }
}

///| 尝试刷新 NyxID access token。失败时返回原凭证。
fn try_refresh_nyxid_token(
  stored : @ai.NyxidStoredCredentials,
  creds_path : String
) -> @ai.NyxidStoredCredentials {
  let refresh_token = match stored.credentials.refresh_token {
    Some(rt) if rt.length() > 0 => rt
    _ => return stored  // No refresh token, can't refresh
  }
  let form = @ai.build_nyxid_refresh_form(refresh_token, stored.client_id, None)
  let form_body = @ai.encode_form(form)
  let token_url = nyxid_trim_slash(stored.base_url) + @ai.nyxid_oauth_token_path
  match host_post_form(token_url, form_body) {
    Ok((_status, body)) => {
      let json = try { @json.parse(body) } catch { _ => return stored }
      let now = nyxid_now_epoch_seconds()
      match @ai.parse_nyxid_token_response(json, now) {
        Ok(new_creds) => {
          // Preserve old refresh_token if server didn't return new one
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
          // Best-effort persist; even if write fails, use in-memory
          let json_out = @ai.nyxid_credentials_to_json(final_creds, stored.base_url, stored.client_id)
          let _ = host_write_text(creds_path, json_out.stringify(escape_slash=false))
          final_stored
        }
        Err(_) => stored
      }
    }
    Err(_) => stored
  }
}

fn nyxid_credentials_path() -> String {
  let home = host_env_var("HOME").unwrap_or(".")
  if home.has_suffix("/") {
    home + ".pimbt/nyxid-credentials.json"
  } else {
    home + "/.pimbt/nyxid-credentials.json"
  }
}

fn nyxid_trim_slash(s : String) -> String {
  if s.has_suffix("/") { s[:s.length() - 1].to_string() } else { s }
}

///| 当前 epoch 秒数（从 host_now_iso 解析）。
fn nyxid_now_epoch_seconds() -> Int64 {
  nyxid_parse_iso_to_epoch(host_now_iso())
}

fn nyxid_parse_iso_to_epoch(iso : String) -> Int64 {
  if iso.length() < 19 { return 0L }
  let year = nyxid_parse_int_or(iso[0:4].to_string(), 1970)
  let month = nyxid_parse_int_or(iso[5:7].to_string(), 1)
  let day = nyxid_parse_int_or(iso[8:10].to_string(), 1)
  let hour = nyxid_parse_int_or(iso[11:13].to_string(), 0)
  let minute = nyxid_parse_int_or(iso[14:16].to_string(), 0)
  let second = nyxid_parse_int_or(iso[17:19].to_string(), 0)
  nyxid_days_from_civil(year, month, day) * 86400L +
    hour.to_int64() * 3600L +
    minute.to_int64() * 60L +
    second.to_int64()
}

fn nyxid_parse_int_or(s : String, default : Int) -> Int {
  match (try? @string.parse_int(s)) {
    Ok(n) => n
    Err(_) => default
  }
}

fn nyxid_days_from_civil(y : Int, m : Int, d : Int) -> Int64 {
  let year = if m <= 2 { y - 1 } else { y }
  let era = if year >= 0 { year / 400 } else { (year - 399) / 400 }
  let yoe = year - era * 400
  let doy = (153 * (if m > 2 { m - 3 } else { m + 9 }) + 2) / 5 + d - 1
  let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
  era.to_int64() * 146097L + doe.to_int64() - 719468L
}

extern "js" fn host_env_var_ffi(name : String) -> String =
  #|(name) => { return process.env[name] || ""; }

fn host_env_var(name : String) -> String? {
  let value = host_env_var_ffi(name)
  if value == "" { None } else { Some(value) }
}
