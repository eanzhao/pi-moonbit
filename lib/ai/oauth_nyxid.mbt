///| NyxID OAuth provider.
///
/// NyxID 实现标准 OAuth 2.0 + PKCE (S256)。
/// CLI 应用推荐使用 public client（无 client_secret，仅靠 PKCE 保证安全）。

///| NyxID 默认 base URL（托管实例）。
pub let nyxid_default_base_url : String = "https://nyx.chrono-ai.fun"

///| NyxID OAuth 授权端点路径。
pub let nyxid_oauth_auth_path : String = "/oauth/authorize"

///| NyxID OAuth token 端点路径。
pub let nyxid_oauth_token_path : String = "/oauth/token"

///| NyxID 用户信息端点路径。
pub let nyxid_oauth_userinfo_path : String = "/oauth/userinfo"

///| 默认 OAuth scope。
pub let nyxid_default_scope : String = "openid profile email"

///| 构建 NyxID 授权 URL。
///
/// 用户访问此 URL 后登录 / 授权，然后被重定向到 redirect_uri（携带 code + state）。
pub fn build_nyxid_auth_url(
  base_url : String,
  client_id : String,
  redirect_uri : String,
  state : String,
  pkce : PkceChallenge,
  scope? : String = nyxid_default_scope
) -> String {
  let base = trim_trailing_slash(base_url)
  let params = [
    "response_type=code",
    "client_id=" + nyxid_url_encode(client_id),
    "redirect_uri=" + nyxid_url_encode(redirect_uri),
    "scope=" + nyxid_url_encode(scope),
    "state=" + nyxid_url_encode(state),
    "code_challenge=" + nyxid_url_encode(pkce.challenge),
    "code_challenge_method=" + pkce.method,
  ]
  base + nyxid_oauth_auth_path + "?" + params.join("&")
}

///| 构建 token 请求体（application/x-www-form-urlencoded 格式的 form fields）。
///
/// 返回的 Map 由调用方编码为 x-www-form-urlencoded body。
pub fn build_nyxid_token_form(
  code : String,
  client_id : String,
  client_secret : String?,
  redirect_uri : String,
  pkce_verifier : String
) -> Array[(String, String)] {
  let form : Array[(String, String)] = [
    ("grant_type", "authorization_code"),
    ("code", code),
    ("client_id", client_id),
    ("redirect_uri", redirect_uri),
    ("code_verifier", pkce_verifier),
  ]
  match client_secret {
    Some(secret) if secret.length() > 0 =>
      form.push(("client_secret", secret))
    _ => ()
  }
  form
}

///| 构建 refresh token 请求表单。
pub fn build_nyxid_refresh_form(
  refresh_token : String,
  client_id : String,
  client_secret : String?
) -> Array[(String, String)] {
  let form : Array[(String, String)] = [
    ("grant_type", "refresh_token"),
    ("refresh_token", refresh_token),
    ("client_id", client_id),
  ]
  match client_secret {
    Some(secret) if secret.length() > 0 =>
      form.push(("client_secret", secret))
    _ => ()
  }
  form
}

///| 将 form fields 编码为 application/x-www-form-urlencoded 字符串。
pub fn encode_form(fields : Array[(String, String)]) -> String {
  let parts : Array[String] = []
  for field in fields {
    let (key, value) = field
    parts.push(nyxid_url_encode(key) + "=" + nyxid_url_encode(value))
  }
  parts.join("&")
}

///| 解析 NyxID token 响应。
///
/// 成功响应格式:
/// ```json
/// {
///   "access_token": "eyJ...",
///   "refresh_token": "eyJ...",
///   "id_token": "eyJ...",
///   "token_type": "Bearer",
///   "expires_in": 900,
///   "scope": "openid profile email"
/// }
/// ```
pub fn parse_nyxid_token_response(
  response : Json,
  now_epoch_seconds : Int64
) -> Result[OAuthCredentials, OAuthError] {
  guard response is Object(obj) else {
    return Err(ProviderError("expected JSON object in token response"))
  }
  // Check for OAuth 2.0 error response
  match obj.get("error") {
    Some(String(err_code)) => {
      let description = match obj.get("error_description") {
        Some(String(d)) => d
        _ => err_code
      }
      return Err(match err_code {
        "invalid_grant" => InvalidGrant(description)
        _ => ProviderError(err_code + ": " + description)
      })
    }
    _ => ()
  }
  let access_token = match obj.get("access_token") {
    Some(String(t)) => t
    _ => return Err(ProviderError("missing access_token"))
  }
  let refresh_token = match obj.get("refresh_token") {
    Some(String(t)) => Some(t)
    _ => None
  }
  let expires_at = match obj.get("expires_in") {
    Some(Number(seconds, ..)) => Some(now_epoch_seconds + seconds.to_int64())
    _ => None
  }
  let token_type = match obj.get("token_type") {
    Some(String(t)) => t
    _ => "Bearer"
  }
  Ok({
    access_token,
    refresh_token,
    expires_at,
    token_type,
    extra: Some(response),
  })
}

///| 将 OAuthCredentials 序列化为 JSON（用于持久化）。
pub fn nyxid_credentials_to_json(creds : OAuthCredentials, base_url : String, client_id : String) -> Json {
  let fields : Map[String, Json] = {
    "provider": Json::string("nyxid"),
    "base_url": Json::string(base_url),
    "client_id": Json::string(client_id),
    "access_token": Json::string(creds.access_token),
    "token_type": Json::string(creds.token_type),
  }
  match creds.refresh_token {
    Some(rt) => fields["refresh_token"] = Json::string(rt)
    None => ()
  }
  match creds.expires_at {
    Some(exp) => fields["expires_at"] = Json::number(exp.to_double())
    None => ()
  }
  Json::object(fields)
}

///| 从 JSON 反序列化 NyxID 凭证（base_url + client_id + credentials）。
pub(all) struct NyxidStoredCredentials {
  base_url : String
  client_id : String
  credentials : OAuthCredentials
}

pub fn parse_nyxid_stored_credentials(json : Json) -> Result[NyxidStoredCredentials, String] {
  guard json is Object(obj) else {
    return Err("expected JSON object")
  }
  let base_url = match obj.get("base_url") {
    Some(String(s)) => s
    _ => return Err("missing base_url")
  }
  let client_id = match obj.get("client_id") {
    Some(String(s)) => s
    _ => return Err("missing client_id")
  }
  let access_token = match obj.get("access_token") {
    Some(String(s)) => s
    _ => return Err("missing access_token")
  }
  let refresh_token = match obj.get("refresh_token") {
    Some(String(s)) => Some(s)
    _ => None
  }
  let expires_at = match obj.get("expires_at") {
    Some(Number(n, ..)) => Some(n.to_int64())
    _ => None
  }
  let token_type = match obj.get("token_type") {
    Some(String(s)) => s
    _ => "Bearer"
  }
  Ok({
    base_url,
    client_id,
    credentials: {
      access_token,
      refresh_token,
      expires_at,
      token_type,
      extra: None,
    },
  })
}

// --- Private helpers ---

fn trim_trailing_slash(s : String) -> String {
  if s.has_suffix("/") { s[:s.length() - 1].to_string() } else { s }
}

fn nyxid_url_encode(text : String) -> String {
  let mut result = ""
  for ch in text {
    let code = ch.to_int()
    if (code >= 0x30 && code <= 0x39) ||  // 0-9
       (code >= 0x41 && code <= 0x5A) ||  // A-Z
       (code >= 0x61 && code <= 0x7A) ||  // a-z
       code == 0x2D || code == 0x2E || code == 0x5F || code == 0x7E {
      result = result + ch.to_string()
    } else if code < 0x80 {
      result = result + "%" + nyxid_hex_pair(code)
    } else if code < 0x800 {
      let byte1 = 0xC0 | (code >> 6)
      let byte2 = 0x80 | (code & 0x3F)
      result = result + "%" + nyxid_hex_pair(byte1) + "%" + nyxid_hex_pair(byte2)
    } else if code < 0x10000 {
      let byte1 = 0xE0 | (code >> 12)
      let byte2 = 0x80 | ((code >> 6) & 0x3F)
      let byte3 = 0x80 | (code & 0x3F)
      result = result + "%" + nyxid_hex_pair(byte1) + "%" + nyxid_hex_pair(byte2) + "%" + nyxid_hex_pair(byte3)
    } else {
      let byte1 = 0xF0 | (code >> 18)
      let byte2 = 0x80 | ((code >> 12) & 0x3F)
      let byte3 = 0x80 | ((code >> 6) & 0x3F)
      let byte4 = 0x80 | (code & 0x3F)
      result = result + "%" + nyxid_hex_pair(byte1) + "%" + nyxid_hex_pair(byte2) + "%" + nyxid_hex_pair(byte3) + "%" + nyxid_hex_pair(byte4)
    }
  }
  result
}

fn nyxid_hex_pair(byte : Int) -> String {
  nyxid_hex_digit(byte / 16) + nyxid_hex_digit(byte % 16)
}

fn nyxid_hex_digit(n : Int) -> String {
  match n {
    0 => "0"; 1 => "1"; 2 => "2"; 3 => "3"; 4 => "4"
    5 => "5"; 6 => "6"; 7 => "7"; 8 => "8"; 9 => "9"
    10 => "A"; 11 => "B"; 12 => "C"; 13 => "D"; 14 => "E"; 15 => "F"
    _ => "0"
  }
}
