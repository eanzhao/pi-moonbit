///| NyxID provider 管理 API 的纯函数（请求构建 + 响应解析）。

///| NyxID LLM 状态端点。
pub let nyxid_llm_status_path : String = "/api/v1/llm/status"

///| NyxID user-tokens 端点（列出已连接的 LLM provider）。
pub let nyxid_my_tokens_path : String = "/api/v1/providers/my-tokens"

///| 构造 connect-api-key 请求 URL。
pub fn nyxid_connect_api_key_path(provider_slug : String) -> String {
  "/api/v1/providers/" + provider_slug + "/connect/api-key"
}

///| 构造 disconnect 请求 URL。
pub fn nyxid_disconnect_path(provider_id : String) -> String {
  "/api/v1/providers/" + provider_id + "/disconnect"
}

///| 单个 LLM provider 的状态（来自 /api/v1/llm/status 响应）。
pub(all) struct LlmProviderStatus {
  provider_slug : String
  provider_name : String
  status : String  // "connected", "available", "error", ...
  proxy_url : String
} derive(Show, Eq)

///| LLM status 响应。
pub(all) struct LlmStatus {
  providers : Array[LlmProviderStatus]
  gateway_url : String
  supported_models : Array[String]
} derive(Show, Eq)

///| 解析 `/api/v1/llm/status` 响应。
pub fn parse_nyxid_llm_status(json : Json) -> Result[LlmStatus, String] {
  guard json is Object(obj) else {
    return Err("expected JSON object in llm status")
  }
  let providers : Array[LlmProviderStatus] = []
  match obj.get("providers") {
    Some(Array(items)) =>
      for item in items {
        match parse_llm_provider_status(item) {
          Ok(p) => providers.push(p)
          Err(_) => ()
        }
      }
    _ => ()
  }
  let gateway_url = match obj.get("gateway_url") {
    Some(String(s)) => s
    _ => ""
  }
  let supported_models : Array[String] = []
  match obj.get("supported_models") {
    Some(Array(items)) =>
      for item in items {
        match item {
          String(s) => supported_models.push(s)
          _ => ()
        }
      }
    _ => ()
  }
  Ok({ providers, gateway_url, supported_models })
}

fn parse_llm_provider_status(json : Json) -> Result[LlmProviderStatus, String] {
  guard json is Object(obj) else {
    return Err("expected provider status object")
  }
  let provider_slug = match obj.get("provider_slug") {
    Some(String(s)) => s
    _ => return Err("missing provider_slug")
  }
  let provider_name = match obj.get("provider_name") {
    Some(String(s)) => s
    _ => provider_slug
  }
  let status = match obj.get("status") {
    Some(String(s)) => s
    _ => "unknown"
  }
  let proxy_url = match obj.get("proxy_url") {
    Some(String(s)) => s
    _ => ""
  }
  Ok({ provider_slug, provider_name, status, proxy_url })
}

///| 用户已连接的外部 provider 凭证（来自 /api/v1/providers/my-tokens）。
pub(all) struct UserToken {
  provider_id : String
  provider_name : String
  provider_slug : String
  provider_type : String  // "api_key" | "oauth" | ...
  status : String         // "connected" | "expired" | "pending"
  label : String?
  gateway_url : String?
  expires_at : String?
  last_used_at : String?
  connected_at : String
} derive(Show, Eq)

///| 解析 `/api/v1/providers/my-tokens` 响应。
pub fn parse_nyxid_user_tokens(json : Json) -> Result[Array[UserToken], String] {
  guard json is Object(obj) else {
    return Err("expected JSON object")
  }
  let items = match obj.get("tokens") {
    Some(Array(items)) => items
    _ => return Err("missing tokens array")
  }
  let tokens : Array[UserToken] = []
  for item in items {
    match parse_user_token(item) {
      Ok(t) => tokens.push(t)
      Err(_) => ()
    }
  }
  Ok(tokens)
}

fn parse_user_token(json : Json) -> Result[UserToken, String] {
  guard json is Object(obj) else {
    return Err("expected object")
  }
  let provider_id = match obj.get("provider_id") {
    Some(String(s)) => s
    _ => return Err("missing provider_id")
  }
  let provider_name = match obj.get("provider_name") {
    Some(String(s)) => s
    _ => provider_id
  }
  let provider_slug = match obj.get("provider_slug") {
    Some(String(s)) => s
    _ => provider_id
  }
  let provider_type = match obj.get("provider_type") {
    Some(String(s)) => s
    _ => "unknown"
  }
  let status = match obj.get("status") {
    Some(String(s)) => s
    _ => "unknown"
  }
  let label = match obj.get("label") { Some(String(s)) => Some(s); _ => None }
  let gateway_url = match obj.get("gateway_url") { Some(String(s)) => Some(s); _ => None }
  let expires_at = match obj.get("expires_at") { Some(String(s)) => Some(s); _ => None }
  let last_used_at = match obj.get("last_used_at") { Some(String(s)) => Some(s); _ => None }
  let connected_at = match obj.get("connected_at") {
    Some(String(s)) => s
    _ => ""
  }
  Ok({
    provider_id,
    provider_name,
    provider_slug,
    provider_type,
    status,
    label,
    gateway_url,
    expires_at,
    last_used_at,
    connected_at,
  })
}

///| 构造 POST /api/v1/providers/{id}/connect/api-key 请求体。
pub fn build_nyxid_connect_api_key_body(
  api_key : String,
  label? : String? = None,
  gateway_url? : String? = None
) -> Json {
  let fields : Map[String, Json] = {
    "api_key": Json::string(api_key),
  }
  match label {
    Some(l) if l.length() > 0 => fields["label"] = Json::string(l)
    _ => ()
  }
  match gateway_url {
    Some(url) if url.length() > 0 => fields["gateway_url"] = Json::string(url)
    _ => ()
  }
  Json::object(fields)
}
