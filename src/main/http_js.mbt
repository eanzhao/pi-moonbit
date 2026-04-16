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

extern "js" fn host_env_var_ffi(name : String) -> String =
  #|(name) => { return process.env[name] || ""; }

fn host_env_var(name : String) -> String? {
  let value = host_env_var_ffi(name)
  if value == "" { None } else { Some(value) }
}
