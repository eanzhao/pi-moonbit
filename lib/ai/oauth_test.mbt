test "pkce_challenge_s256 constructs challenge" {
  let pkce = pkce_challenge_s256("test-verifier-43-chars-at-least-long-enough", "ABC123")
  assert_eq(pkce.method, "S256")
  assert_eq(pkce.verifier, "test-verifier-43-chars-at-least-long-enough")
  assert_eq(pkce.challenge, "ABC123")
}

test "is_credentials_expired checks expiry" {
  let expired : OAuthCredentials = {
    access_token: "tok",
    refresh_token: None,
    expires_at: Some(100L),
    token_type: "Bearer",
    extra: None,
  }
  assert_true(is_credentials_expired(expired, 200L))
  assert_false(is_credentials_expired(expired, 50L))
  let no_expiry : OAuthCredentials = { ..expired, expires_at: None }
  assert_false(is_credentials_expired(no_expiry, 999999L))
}

test "oauth_error_message formats errors" {
  assert_eq(oauth_error_message(UserCancelled), "user cancelled authentication")
  assert_eq(oauth_error_message(NetworkError("timeout")), "network error: timeout")
  assert_true(oauth_error_message(InvalidGrant("bad")).contains("invalid grant"))
}

test "anthropic auth url contains required params" {
  let pkce = pkce_challenge_s256("verifier", "CHALLENGE")
  let url = build_anthropic_auth_url("state123", pkce)
  assert_true(url.contains("client_id=" + anthropic_oauth_client_id))
  assert_true(url.contains("code_challenge=CHALLENGE"))
  assert_true(url.contains("code_challenge_method=S256"))
  assert_true(url.contains("state=state123"))
  assert_true(url.contains("response_type=code"))
}

test "anthropic token request builds correct payload" {
  let request = build_anthropic_token_request("auth-code", "verifier-xyz")
  match request {
    Object(obj) => {
      match obj.get("grant_type") {
        Some(String(g)) => assert_eq(g, "authorization_code")
        _ => fail("missing grant_type")
      }
      match obj.get("code_verifier") {
        Some(String(v)) => assert_eq(v, "verifier-xyz")
        _ => fail("missing code_verifier")
      }
    }
    _ => fail("expected object")
  }
}

test "parse anthropic token response extracts credentials" {
  let response = Json::object({
    "access_token": Json::string("access-abc"),
    "refresh_token": Json::string("refresh-xyz"),
    "expires_in": Json::number(3600.0),
    "token_type": Json::string("Bearer"),
  })
  match parse_anthropic_token_response(response, 1000L) {
    Ok(creds) => {
      assert_eq(creds.access_token, "access-abc")
      assert_eq(creds.refresh_token, Some("refresh-xyz"))
      assert_eq(creds.expires_at, Some(4600L))
      assert_eq(creds.token_type, "Bearer")
    }
    Err(_) => fail("expected Ok")
  }
}

test "parse anthropic token response handles missing fields" {
  let bad = Json::object({})
  assert_true(parse_anthropic_token_response(bad, 0L) is Err(_))
}
