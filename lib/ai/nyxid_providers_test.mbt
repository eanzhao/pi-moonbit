test "parse_nyxid_llm_status extracts providers and models" {
  let json = Json::object({
    "providers": Json::array([
      Json::object({
        "provider_slug": Json::string("openai"),
        "provider_name": Json::string("OpenAI"),
        "status": Json::string("connected"),
        "proxy_url": Json::string("https://nyx.example.com/api/v1/llm/openai"),
      }),
      Json::object({
        "provider_slug": Json::string("anthropic"),
        "provider_name": Json::string("Anthropic"),
        "status": Json::string("available"),
        "proxy_url": Json::string(""),
      }),
    ]),
    "gateway_url": Json::string("https://nyx.example.com/api/v1/llm/gateway"),
    "supported_models": Json::array([
      Json::string("gpt-5.4"),
      Json::string("claude-sonnet-4-5"),
    ]),
  })
  match parse_nyxid_llm_status(json) {
    Ok(status) => {
      assert_eq(status.providers.length(), 2)
      assert_eq(status.providers[0].provider_slug, "openai")
      assert_eq(status.providers[0].status, "connected")
      assert_eq(status.providers[1].provider_slug, "anthropic")
      assert_eq(status.gateway_url, "https://nyx.example.com/api/v1/llm/gateway")
      assert_eq(status.supported_models.length(), 2)
      assert_eq(status.supported_models[0], "gpt-5.4")
    }
    Err(msg) => fail(msg)
  }
}

test "parse_nyxid_user_tokens extracts connected providers" {
  let json = Json::object({
    "tokens": Json::array([
      Json::object({
        "provider_id": Json::string("abc-123"),
        "provider_name": Json::string("OpenAI"),
        "provider_slug": Json::string("openai"),
        "provider_type": Json::string("api_key"),
        "status": Json::string("connected"),
        "label": Json::string("default"),
        "connected_at": Json::string("2026-04-16T10:00:00Z"),
      }),
      Json::object({
        "provider_id": Json::string("xyz-789"),
        "provider_name": Json::string("Anthropic"),
        "provider_slug": Json::string("anthropic"),
        "provider_type": Json::string("api_key"),
        "status": Json::string("expired"),
        "connected_at": Json::string("2026-04-01T00:00:00Z"),
      }),
    ]),
  })
  match parse_nyxid_user_tokens(json) {
    Ok(tokens) => {
      assert_eq(tokens.length(), 2)
      assert_eq(tokens[0].provider_slug, "openai")
      assert_eq(tokens[0].status, "connected")
      assert_eq(tokens[0].label, Some("default"))
      assert_eq(tokens[1].provider_slug, "anthropic")
      assert_eq(tokens[1].status, "expired")
      assert_eq(tokens[1].label, None)
    }
    Err(msg) => fail(msg)
  }
}

test "parse_nyxid_user_tokens handles empty array" {
  let json = Json::object({ "tokens": Json::array([]) })
  match parse_nyxid_user_tokens(json) {
    Ok(tokens) => assert_eq(tokens.length(), 0)
    Err(msg) => fail(msg)
  }
}

test "parse_nyxid_user_tokens rejects missing tokens field" {
  let json = Json::object({})
  assert_true(parse_nyxid_user_tokens(json) is Err(_))
}

test "build_nyxid_connect_api_key_body includes required fields" {
  let body = build_nyxid_connect_api_key_body("sk-test-key")
  match body {
    Object(obj) => {
      match obj.get("api_key") {
        Some(String(k)) => assert_eq(k, "sk-test-key")
        _ => fail("missing api_key")
      }
      assert_true(obj.get("label") is None)
      assert_true(obj.get("gateway_url") is None)
    }
    _ => fail("expected object")
  }
}

test "build_nyxid_connect_api_key_body with optional label and gateway" {
  let body = build_nyxid_connect_api_key_body(
    "sk-test",
    label=Some("my-key"),
    gateway_url=Some("https://my-ollama.example.com"),
  )
  match body {
    Object(obj) => {
      match obj.get("label") {
        Some(String(l)) => assert_eq(l, "my-key")
        _ => fail("missing label")
      }
      match obj.get("gateway_url") {
        Some(String(u)) => assert_eq(u, "https://my-ollama.example.com")
        _ => fail("missing gateway_url")
      }
    }
    _ => fail("expected object")
  }
}

test "nyxid path builders" {
  assert_eq(nyxid_connect_api_key_path("openai"), "/api/v1/providers/openai/connect/api-key")
  assert_eq(nyxid_disconnect_path("abc-123"), "/api/v1/providers/abc-123/disconnect")
  assert_eq(nyxid_user_service_proxy_path("ollama-xyz"), "/api/v1/proxy/s/ollama-xyz")
}

test "parse_nyxid_keys extracts user-registered services" {
  let json = Json::object({
    "keys": Json::array([
      Json::object({
        "id": Json::string("k-1"),
        "slug": Json::string("ollama-from-macstudio-8p2r"),
        "label": Json::string("Ollama from MacStudio"),
        "endpoint_url": Json::string("http://localhost:11434/v1"),
        "auth_method": Json::string("header"),
        "status": Json::string("active"),
        "is_active": Json::boolean(true),
        "service_type": Json::string("http"),
      }),
      Json::object({
        "id": Json::string("k-2"),
        "slug": Json::string("lark-oauth"),
        "label": Json::string("Lark"),
        "endpoint_url": Json::string("https://open.larksuite.com"),
        "auth_method": Json::string("token_exchange"),
        "status": Json::string("active"),
        "is_active": Json::boolean(true),
        "service_type": Json::string("http"),
        "catalog_service_slug": Json::string("lark"),
        "catalog_service_name": Json::string("Lark"),
      }),
    ]),
  })
  match parse_nyxid_keys(json) {
    Ok(services) => {
      assert_eq(services.length(), 2)
      assert_eq(services[0].slug, "ollama-from-macstudio-8p2r")
      assert_eq(services[0].label, "Ollama from MacStudio")
      assert_eq(services[0].endpoint_url, "http://localhost:11434/v1")
      assert_eq(services[0].auth_method, "header")
      assert_eq(services[0].active, true)
      assert_true(services[0].catalog_service_slug is None)
      assert_eq(services[1].auth_method, "token_exchange")
      assert_eq(services[1].catalog_service_slug, Some("lark"))
    }
    Err(msg) => fail(msg)
  }
}

test "parse_nyxid_keys skips malformed entries without erroring" {
  let json = Json::object({
    "keys": Json::array([
      Json::object({
        // missing slug
        "id": Json::string("k-bad"),
      }),
      Json::object({
        "id": Json::string("k-good"),
        "slug": Json::string("good"),
      }),
    ]),
  })
  match parse_nyxid_keys(json) {
    Ok(services) => {
      assert_eq(services.length(), 1)
      assert_eq(services[0].slug, "good")
    }
    Err(msg) => fail(msg)
  }
}
