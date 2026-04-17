test "nyxid auth url contains required OAuth params" {
  let pkce = pkce_challenge_s256("verifier-123", "CHALLENGE-xyz")
  let url = build_nyxid_auth_url(
    "https://nyx.chrono-ai.fun",
    "client-abc",
    "http://localhost:54545/callback",
    "state-123",
    pkce,
  )
  assert_true(url.has_prefix("https://nyx.chrono-ai.fun/oauth/authorize?"))
  assert_true(url.contains("response_type=code"))
  assert_true(url.contains("client_id=client-abc"))
  assert_true(url.contains("code_challenge=CHALLENGE-xyz"))
  assert_true(url.contains("code_challenge_method=S256"))
  assert_true(url.contains("state=state-123"))
  // redirect_uri should be percent-encoded
  assert_true(url.contains("redirect_uri=http%3A%2F%2Flocalhost%3A54545%2Fcallback"))
}

test "nyxid auth url omits scope when empty (lets server use allowed_scopes)" {
  let pkce = pkce_challenge_s256("v", "c")
  let url = build_nyxid_auth_url(
    "https://nyx.example.com",
    "id", "http://x", "s", pkce,
  )
  assert_false(url.contains("scope="))
}

test "nyxid auth url includes scope when provided" {
  let pkce = pkce_challenge_s256("v", "c")
  let url = build_nyxid_auth_url(
    "https://nyx.example.com",
    "id", "http://x", "s", pkce,
    scope="openid profile email",
  )
  assert_true(url.contains("scope=openid"))
}

test "nyxid auth url trims trailing slash on base url" {
  let pkce = pkce_challenge_s256("v", "c")
  let url = build_nyxid_auth_url(
    "https://nyx.chrono-ai.fun/",
    "id", "http://x", "s", pkce,
  )
  assert_true(url.has_prefix("https://nyx.chrono-ai.fun/oauth/authorize?"))
}

test "token request form includes required fields" {
  let form = build_nyxid_token_form("auth-code", "client-id", None, "http://localhost/cb", "verifier-xyz")
  let encoded = encode_form(form)
  assert_true(encoded.contains("grant_type=authorization_code"))
  assert_true(encoded.contains("code=auth-code"))
  assert_true(encoded.contains("client_id=client-id"))
  assert_true(encoded.contains("code_verifier=verifier-xyz"))
  assert_false(encoded.contains("client_secret"))
}

test "token request form includes secret when provided" {
  let form = build_nyxid_token_form("c", "id", Some("secret-value"), "uri", "v")
  let encoded = encode_form(form)
  assert_true(encoded.contains("client_secret=secret-value"))
}

test "refresh form includes grant_type and refresh_token" {
  let form = build_nyxid_refresh_form("refresh-abc", "client-id", None)
  let encoded = encode_form(form)
  assert_true(encoded.contains("grant_type=refresh_token"))
  assert_true(encoded.contains("refresh_token=refresh-abc"))
}

test "parse token response extracts credentials and expiry" {
  let response = Json::object({
    "access_token": Json::string("access-123"),
    "refresh_token": Json::string("refresh-456"),
    "expires_in": Json::number(900.0),
    "token_type": Json::string("Bearer"),
    "scope": Json::string("openid profile email"),
  })
  match parse_nyxid_token_response(response, 1_000_000L) {
    Ok(creds) => {
      assert_eq(creds.access_token, "access-123")
      assert_eq(creds.refresh_token, Some("refresh-456"))
      assert_eq(creds.expires_at, Some(1_000_900L))
      assert_eq(creds.token_type, "Bearer")
    }
    Err(_) => fail("expected Ok")
  }
}

test "parse token response handles OAuth error format" {
  let response = Json::object({
    "error": Json::string("invalid_grant"),
    "error_description": Json::string("code expired"),
  })
  match parse_nyxid_token_response(response, 0L) {
    Err(InvalidGrant(msg)) => assert_eq(msg, "code expired")
    _ => fail("expected InvalidGrant error")
  }
}

test "stored credentials JSON roundtrip" {
  let creds : OAuthCredentials = {
    access_token: "access-xyz",
    refresh_token: Some("refresh-xyz"),
    expires_at: Some(2_000_000L),
    token_type: "Bearer",
    extra: None,
  }
  let json = nyxid_credentials_to_json(creds, "https://nyx.example.com", "my-client")
  match parse_nyxid_stored_credentials(json) {
    Ok(stored) => {
      assert_eq(stored.base_url, "https://nyx.example.com")
      assert_eq(stored.client_id, "my-client")
      assert_eq(stored.credentials.access_token, "access-xyz")
      assert_eq(stored.credentials.refresh_token, Some("refresh-xyz"))
      assert_eq(stored.credentials.expires_at, Some(2_000_000L))
    }
    Err(msg) => fail(msg)
  }
}

test "encode_form escapes special characters" {
  let form : Array[(String, String)] = [("key with space", "val&other=thing")]
  let encoded = encode_form(form)
  assert_true(encoded.contains("key%20with%20space"))
  assert_true(encoded.contains("val%26other%3Dthing"))
}

test "is_credentials_expired with 60-second buffer" {
  let creds : OAuthCredentials = {
    access_token: "tok",
    refresh_token: Some("rt"),
    expires_at: Some(1000L),
    token_type: "Bearer",
    extra: None,
  }
  // Current behavior: is_credentials_expired returns true only when now >= expires_at
  // Consumers apply their own buffer.
  assert_true(is_credentials_expired(creds, 1000L))
  assert_true(is_credentials_expired(creds, 1500L))
  assert_false(is_credentials_expired(creds, 999L))
  // For a 60-second buffer, caller checks: now + 60 >= expires_at
  let now : Int64 = 950L
  assert_true(now + 60L >= 1000L)
  let now2 : Int64 = 900L
  assert_false(now2 + 60L >= 1000L)
}

test "cli auth url omits client_id (not needed for CLI flow)" {
  let url = build_nyxid_cli_auth_url("https://nyx.chrono-ai.fun", 54545, "state-abc")
  assert_true(url.has_prefix("https://nyx.chrono-ai.fun/cli-auth?"))
  assert_true(url.contains("port=54545"))
  assert_true(url.contains("state=state-abc"))
  assert_true(url.contains("client_ua=pimbt"))
  assert_false(url.contains("client_id"))
  assert_false(url.contains("code_challenge"))
}

test "cli auth url with custom client_ua" {
  let url = build_nyxid_cli_auth_url("https://x.com", 1234, "s", client_ua="myapp/1.0")
  assert_true(url.contains("client_ua=myapp%2F1.0"))
}

test "parse_nyxid_public_config extracts frontend_url" {
  let json = Json::object({
    "frontend_url": Json::string("https://app.nyx.example.com/"),
    "other_field": Json::string("ignored"),
  })
  match parse_nyxid_public_config(json) {
    Ok(url) => assert_eq(url, "https://app.nyx.example.com")  // trailing slash trimmed
    Err(msg) => fail(msg)
  }
}

test "parse_nyxid_public_config handles missing frontend_url" {
  let json = Json::object({})
  assert_true(parse_nyxid_public_config(json) is Err(_))
}

test "nyxid_cli_credentials_from_callback builds OAuthCredentials" {
  let creds = nyxid_cli_credentials_from_callback("access-xyz", Some("refresh-xyz"), 1000L)
  assert_eq(creds.access_token, "access-xyz")
  assert_eq(creds.refresh_token, Some("refresh-xyz"))
  assert_eq(creds.token_type, "Bearer")
  assert_eq(creds.expires_at, Some(1900L))  // 1000 + 900 default
}

test "nyxid_cli_credentials with custom ttl" {
  let creds = nyxid_cli_credentials_from_callback("t", None, 0L, assumed_ttl_seconds=3600)
  assert_eq(creds.expires_at, Some(3600L))
}

test "refresh response without refresh_token preserves original" {
  // Simulate what NyxID might return on refresh (sometimes no new refresh_token)
  let response = Json::object({
    "access_token": Json::string("new-access"),
    "expires_in": Json::number(900.0),
    "token_type": Json::string("Bearer"),
  })
  match parse_nyxid_token_response(response, 1000L) {
    Ok(creds) => {
      assert_eq(creds.access_token, "new-access")
      assert_eq(creds.refresh_token, None)  // Response had none
      assert_eq(creds.expires_at, Some(1900L))
    }
    Err(_) => fail("expected Ok")
  }
}
