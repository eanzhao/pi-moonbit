///| NyxID provider 管理 API 的纯函数（请求构建 + 响应解析）。

///| NyxID LLM 状态端点。
pub let nyxid_llm_status_path : String = "/api/v1/llm/status"

///| NyxID user-tokens 端点（列出已连接的 LLM provider）。
pub let nyxid_my_tokens_path : String = "/api/v1/providers/my-tokens"

///| NyxID unified keys 端点（用户注册的所有服务 — 内建 + 自定义）。
pub let nyxid_keys_path : String = "/api/v1/keys"

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

///| 用户注册的服务（来自 /api/v1/keys）—— 同时覆盖内建 provider 绑定和完全自定义
/// 的 proxy service（Ollama / MLX / SiliconFlow / Mimo 等）。
pub(all) struct NyxidUserService {
  id : String
  slug : String
  label : String
  endpoint_url : String
  auth_method : String // bearer / header / token_exchange / none / path / api_key
  status : String // active / expired / pending / revoked / error
  active : Bool // is_active
  service_type : String // http / ssh / ...
  catalog_service_slug : String? // e.g. "llm-openai"; None 表示完全自定义
  catalog_service_name : String? // 人类可读的 catalog 名
  last_used_at : String?
} derive(Show, Eq)

///| 解析 `/api/v1/keys` 响应，返回 active HTTP 服务列表。
///
/// NyxID 文档称之为 "the unified keys API"：一次 round-trip 拿到 slug + label
/// + 上游 URL + auth_method + 活跃度，比 `/providers/my-tokens` 覆盖面广得多
/// —— 用户通过 `nyxid service add` 注册的自定义 proxy（如 Ollama、MLX、Mimo、
/// SiliconFlow、chrono-llm）只会出现在这里。
///
/// 注意：结果里包含 `is_active=false` 的 revoked / pending 条目，调用方按需过滤。
pub fn parse_nyxid_keys(json : Json) -> Result[Array[NyxidUserService], String] {
  guard json is Object(obj) else {
    return Err("expected JSON object in keys response")
  }
  let items = match obj.get("keys") {
    Some(Array(items)) => items
    _ => return Err("missing keys array")
  }
  let services : Array[NyxidUserService] = []
  for item in items {
    match parse_nyxid_key_item(item) {
      Ok(svc) => services.push(svc)
      Err(_) => () // skip malformed entries silently
    }
  }
  Ok(services)
}

fn parse_nyxid_key_item(json : Json) -> Result[NyxidUserService, String] {
  guard json is Object(obj) else {
    return Err("expected key object")
  }
  let id = match obj.get("id") {
    Some(String(s)) => s
    _ => return Err("missing id")
  }
  let slug = match obj.get("slug") {
    Some(String(s)) => s
    _ => return Err("missing slug")
  }
  let label = match obj.get("label") {
    Some(String(s)) => s
    _ => slug
  }
  let endpoint_url = match obj.get("endpoint_url") {
    Some(String(s)) => s
    _ => ""
  }
  let auth_method = match obj.get("auth_method") {
    Some(String(s)) => s
    _ => "unknown"
  }
  let status = match obj.get("status") {
    Some(String(s)) => s
    _ => "unknown"
  }
  let active = match obj.get("is_active") {
    Some(True) => true
    Some(False) => false
    _ => status == "active"
  }
  let service_type = match obj.get("service_type") {
    Some(String(s)) => s
    _ => "http"
  }
  let catalog_service_slug = match obj.get("catalog_service_slug") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let catalog_service_name = match obj.get("catalog_service_name") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let last_used_at = match obj.get("last_used_at") {
    Some(String(s)) => Some(s)
    _ => None
  }
  Ok({
    id,
    slug,
    label,
    endpoint_url,
    auth_method,
    status,
    active,
    service_type,
    catalog_service_slug,
    catalog_service_name,
    last_used_at,
  })
}

///| 从 `/api/v1/proxy/s/{slug}` 构造代理到该 user service 的完整 URL。
pub fn nyxid_user_service_proxy_path(slug : String) -> String {
  "/api/v1/proxy/s/" + slug
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
