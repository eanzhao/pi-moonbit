///| JS target 的 crypto FFI（用 Node.js crypto 模块）。

///| 生成指定字节数的随机 base64url 字符串。
extern "js" fn host_random_base64url_ffi(length : Int) -> String =
  #|(length) => {
  #|  const crypto = require("crypto");
  #|  return crypto.randomBytes(length).toString("base64url");
  #|}

///| 对字符串做 SHA-256 并返回 base64url 编码。
extern "js" fn host_sha256_base64url_ffi(input : String) -> String =
  #|(input) => {
  #|  const crypto = require("crypto");
  #|  return crypto.createHash("sha256").update(input).digest("base64url");
  #|}

///| 生成随机字符串（alphanumeric，用作 OAuth state）。
fn host_random_state() -> String {
  host_random_base64url_ffi(16)
}

///| 生成 PKCE S256 challenge。
///
/// 流程：
/// 1. verifier = base64url(随机 32 字节)
/// 2. challenge = base64url(SHA-256(verifier))
fn host_generate_pkce() -> @ai.PkceChallenge {
  let verifier = host_random_base64url_ffi(32)
  let challenge = host_sha256_base64url_ffi(verifier)
  @ai.pkce_challenge_s256(verifier, challenge)
}
