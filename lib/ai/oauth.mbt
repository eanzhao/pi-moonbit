///| OAuth 认证基础设施。
///
/// 平台无关的类型定义和流程协调。实际 HTTP/浏览器交互由 host 层注入。

///| OAuth 凭证。
pub(all) struct OAuthCredentials {
  access_token : String
  refresh_token : String?
  expires_at : Int64?
  token_type : String
  extra : Json?
} derive(Show, Eq)

///| OAuth 授权信息（供 UI 显示）。
pub(all) struct OAuthAuthInfo {
  url : String
  instructions : String?
} derive(Show, Eq)

///| OAuth 交互提示（等待用户输入）。
pub(all) struct OAuthPrompt {
  kind : String
  message : String
  default_value : String?
} derive(Show, Eq)

///| OAuth 登录过程中的回调钩子。
pub(all) struct OAuthLoginCallbacks {
  on_auth : (OAuthAuthInfo) -> Unit
  on_prompt : (OAuthPrompt) -> String?
  on_progress : (String) -> Unit
  on_manual_code_input : () -> String?
}

///| OAuth 错误类型。
pub(all) suberror OAuthError {
  InvalidGrant(String)
  NetworkError(String)
  UserCancelled
  InvalidState
  ExpiredToken
  ProviderError(String)
} derive(Show)

///| PKCE 代码挑战（RFC 7636）。
pub(all) struct PkceChallenge {
  verifier : String
  challenge : String
  method : String
} derive(Show, Eq)

///| 创建 PKCE 挑战（使用 S256 方法）。
///
/// verifier 应该是 43-128 字符的随机字符串。
/// challenge = base64url(SHA256(verifier))
///
/// 实际的 hash 和 base64url 编码由 host 注入（因为需要 crypto/FFI）。
pub fn pkce_challenge_s256(verifier : String, challenge : String) -> PkceChallenge {
  { verifier, challenge, method: "S256" }
}

///| OAuth Provider 接口（平台无关）。
///
/// 不同 Provider（Anthropic、GitHub、Google 等）实现这个接口。
pub(all) struct OAuthProvider {
  name : String
  /// 构建授权 URL（含 state、PKCE challenge 等）。
  build_auth_url : (String, PkceChallenge) -> String
  /// 用授权码换取 access token。Token endpoint URL 和 body 格式在 impl 里。
  exchange_code : (String, PkceChallenge) -> Result[OAuthCredentials, OAuthError]
  /// 用 refresh token 刷新 access token。
  refresh_token : (String) -> Result[OAuthCredentials, OAuthError]
  /// 从 OAuth 凭证提取 API key/access token。
  get_api_key : (OAuthCredentials) -> String
  /// 是否需要本地回调服务器（为 false 表示手动输入 code）。
  uses_callback_server : Bool
}

///| OAuth 凭证存储接口（实现在 coding_agent 层）。
pub(all) struct OAuthCredentialStore {
  read : (String) -> Result[OAuthCredentials?, String]
  write : (String, OAuthCredentials) -> Result[Unit, String]
  delete : (String) -> Result[Unit, String]
  list : () -> Result[Array[String], String]
}

///| 凭证是否已过期。
pub fn is_credentials_expired(creds : OAuthCredentials, now_epoch_seconds : Int64) -> Bool {
  match creds.expires_at {
    Some(exp) => now_epoch_seconds >= exp
    None => false
  }
}

///| 格式化 OAuth 错误。
pub fn oauth_error_message(error : OAuthError) -> String {
  match error {
    InvalidGrant(msg) => "invalid grant: " + msg
    NetworkError(msg) => "network error: " + msg
    UserCancelled => "user cancelled authentication"
    InvalidState => "invalid OAuth state parameter (possible CSRF)"
    ExpiredToken => "token expired"
    ProviderError(msg) => "provider error: " + msg
  }
}
