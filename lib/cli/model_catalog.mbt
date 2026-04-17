///| 按 provider 实时拉取真实模型列表，失败时回退到内置清单。
///
/// NyxID 的 `/api/v1/llm/status` 返回 `supported_models` 字段是一组路由
/// 通配符（`gpt-*`, `claude-*`, ...），不是真正的 model id。网关本身没有
/// `/models` 端点。每个 provider 的 `proxy_url` 是对上游 OpenAI 兼容接口
/// 的透传，所以 `{proxy_url}/models` 在上游支持时会返回真实 id。
///
/// 已知 quirks：
/// - `openai-codex`：需要 `?client_version=<semver>` 查询参数；响应形状是
///   `{ models: [{ slug, ... }] }`
/// - 其它：标准 OpenAI `{ data: [{ id, ... }] }`
/// - `anthropic`：上游要求 `anthropic-version` 头；当前代理不转发，所以
///   通常失败，此时回退到 `fallback_models("anthropic")`

///| 取一个 provider 的真实 model id 列表。失败时回退到内置清单。
pub fn fetch_provider_models(
  proxy_url : String,
  bearer : String,
  provider_slug : String
) -> Array[String] {
  let url = if provider_slug == "openai-codex" {
    trim_slash_right(proxy_url) + "/models?client_version=" + pimbt_client_version
  } else {
    trim_slash_right(proxy_url) + "/models"
  }
  let live = match host_get_bearer(url, bearer) {
    Ok((status, body)) if status < 400 => parse_models_response(body)
    _ => []
  }
  if live.length() > 0 {
    live
  } else {
    fallback_models(provider_slug)
  }
}

///| 解析 OpenAI 风格 `{data:[{id}]}` 或 Codex 风格 `{models:[{slug}]}`。
fn parse_models_response(body : String) -> Array[String] {
  let json = try @json.parse(body) catch {
    _ => return []
  } noraise {
    value => value
  }
  let obj = match json {
    Object(o) => o
    _ => return []
  }
  let ids : Array[String] = []
  // OpenAI-style: { data: [{ id }] }
  match obj.get("data") {
    Some(Array(items)) =>
      for item in items {
        match item {
          Object(o) =>
            match o.get("id") {
              Some(String(s)) => ids.push(s)
              _ => ()
            }
          _ => ()
        }
      }
    _ => ()
  }
  // Codex-style: { models: [{ slug }] } — fall back when data[] was missing or empty.
  if ids.length() == 0 {
    match obj.get("models") {
      Some(Array(items)) =>
        for item in items {
          match item {
            Object(o) => {
              let picked = match o.get("slug") {
                Some(String(s)) => Some(s)
                _ =>
                  match o.get("id") {
                    Some(String(s)) => Some(s)
                    _ => None
                  }
              }
              match picked {
                Some(s) => ids.push(s)
                None => ()
              }
            }
            _ => ()
          }
        }
      _ => ()
    }
  }
  // De-dupe while preserving order.
  let seen : Map[String, Bool] = Map::new()
  let out : Array[String] = []
  for id in ids {
    if !seen.contains(id) {
      seen[id] = true
      out.push(id)
    }
  }
  out
}

///| 当上游 `/models` 不可用时的兜底清单（选常见 + 推荐的条目，不求穷尽）。
fn fallback_models(slug : String) -> Array[String] {
  match slug {
    "openai" =>
      ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "o1", "o1-mini", "o3-mini", "o4-mini"]
    "openai-codex" => ["gpt-5.2"]
    "anthropic" =>
      [
        "claude-sonnet-4-5",
        "claude-opus-4-5",
        "claude-haiku-4-5",
        "claude-3-5-sonnet-latest",
        "claude-3-5-haiku-latest",
      ]
    "google-ai" => ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
    "mistral" =>
      [
        "mistral-large-latest",
        "mistral-small-latest",
        "codestral-latest",
        "pixtral-large-latest",
      ]
    "cohere" => ["command-r-plus", "command-r", "command-r7b"]
    "deepseek" => ["deepseek-chat", "deepseek-reasoner"]
    _ => []
  }
}

///| 传给 openai-codex 的 client_version（必须是 semver）。
let pimbt_client_version : String = "0.1.3"
