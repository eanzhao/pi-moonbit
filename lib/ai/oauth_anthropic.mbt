///| Anthropic OAuth provider.
///
/// 基于 Anthropic Claude.ai OAuth 流程（PKCE + callback server）。

///| Anthropic OAuth client ID（公开的 native app id，无需 secret）。
pub let anthropic_oauth_client_id : String = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"

///| Anthropic OAuth 授权端点。
pub let anthropic_oauth_auth_url : String = "https://claude.ai/oauth/authorize"

///| Anthropic OAuth token 端点。
pub let anthropic_oauth_token_url : String = "https://console.anthropic.com/v1/oauth/token"

///| Anthropic OAuth 默认 scope。
pub let anthropic_oauth_scopes : String = "org:create_api_key user:profile user:inference"

///| 构建 Anthropic 授权 URL。
pub fn build_anthropic_auth_url(
  state : String,
  pkce : PkceChallenge,
  redirect_uri? : String = "http://localhost:54545/callback"
) -> String {
  let params = [
    "code=true",
    "client_id=" + anthropic_oauth_client_id,
    "response_type=code",
    "redirect_uri=" + url_encode(redirect_uri),
    "scope=" + url_encode(anthropic_oauth_scopes),
    "code_challenge=" + pkce.challenge,
    "code_challenge_method=" + pkce.challenge_method,
    "state=" + state,
  ]
  anthropic_oauth_auth_url + "?" + params.join("&")
}

///| Anthropic token exchange 请求体。
pub fn build_anthropic_token_request(
  code : String,
  pkce_verifier : String,
  redirect_uri? : String = "http://localhost:54545/callback"
) -> Json {
  Json::object({
    "code": Json::string(code),
    "state": Json::string(""),
    "grant_type": Json::string("authorization_code"),
    "client_id": Json::string(anthropic_oauth_client_id),
    "redirect_uri": Json::string(redirect_uri),
    "code_verifier": Json::string(pkce_verifier),
  })
}

///| Anthropic refresh token 请求体。
pub fn build_anthropic_refresh_request(refresh_token : String) -> Json {
  Json::object({
    "grant_type": Json::string("refresh_token"),
    "refresh_token": Json::string(refresh_token),
    "client_id": Json::string(anthropic_oauth_client_id),
  })
}

///| 从 Anthropic token 响应中解析 OAuthCredentials。
pub fn parse_anthropic_token_response(response : Json, now_epoch_seconds : Int64) -> Result[OAuthCredentials, OAuthError] {
  guard response is Object(obj) else {
    return Err(ProviderError("expected JSON object"))
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

// Private URL encoding (minimal, for query params).
fn url_encode(text : String) -> String {
  let mut result = ""
  for ch in text {
    let code = ch.to_int()
    if (code >= 0x30 && code <= 0x39) ||  // 0-9
       (code >= 0x41 && code <= 0x5A) ||  // A-Z
       (code >= 0x61 && code <= 0x7A) ||  // a-z
       code == 0x2D || code == 0x2E || code == 0x5F || code == 0x7E {
      // -._~ unreserved
      result = result + ch.to_string()
    } else {
      // Percent-encode (ASCII only; multi-byte handled as-is here)
      result = result + "%" + url_encode_hex(code / 16) + url_encode_hex(code % 16)
    }
  }
  result
}

fn url_encode_hex(n : Int) -> String {
  match n {
    0 => "0"; 1 => "1"; 2 => "2"; 3 => "3"; 4 => "4"
    5 => "5"; 6 => "6"; 7 => "7"; 8 => "8"; 9 => "9"
    10 => "A"; 11 => "B"; 12 => "C"; 13 => "D"; 14 => "E"; 15 => "F"
    _ => "0"
  }
}
