test "extension factory registry lookup" {
  let registry = ExtensionFactoryRegistry::new()
  registry.register("test-ext", fn() {
    Ok(CodingExtension::empty("test-ext"))
  })
  assert_eq(registry.list(), ["test-ext"])
  match registry.create("test-ext") {
    Ok(ext) => assert_eq(ext.name, "test-ext")
    Err(_) => fail("expected factory success")
  }
  match registry.create("unknown") {
    Err(NotFound(name)) => assert_eq(name, "unknown")
    _ => fail("expected NotFound error")
  }
}

test "parse extension configs from JSON" {
  let json = Json::array([
    Json::object({
      "name": Json::string("ext-a"),
      "enabled": Json::boolean(true),
    }),
    Json::object({
      "name": Json::string("ext-b"),
      "enabled": Json::boolean(false),
      "options": Json::object({ "foo": Json::string("bar") }),
    }),
    Json::object({
      "name": Json::string("ext-c"),
    }),
  ])
  match parse_extension_configs(json) {
    Ok(configs) => {
      assert_eq(configs.length(), 3)
      assert_eq(configs[0].name, "ext-a")
      assert_eq(configs[0].enabled, true)
      assert_eq(configs[1].name, "ext-b")
      assert_eq(configs[1].enabled, false)
      assert_true(configs[1].options is Some(_))
      assert_eq(configs[2].enabled, true)  // default
    }
    Err(msg) => fail(msg)
  }
}

test "load_extensions respects enabled flag" {
  let registry = ExtensionFactoryRegistry::new()
  let created : Ref[Array[String]] = Ref::new([])
  registry.register("a", fn() {
    created.val.push("a")
    Ok(CodingExtension::empty("a"))
  })
  registry.register("b", fn() {
    created.val.push("b")
    Ok(CodingExtension::empty("b"))
  })
  let configs : Array[ExtensionConfig] = [
    { name: "a", enabled: true, options: None },
    { name: "b", enabled: false, options: None },
  ]
  match load_extensions(registry, configs) {
    Ok(runtime) => {
      assert_eq(runtime.extensions.length(), 1)
      assert_eq(runtime.extensions[0].name, "a")
      assert_eq(created.val, ["a"])
    }
    Err(_) => fail("expected Ok")
  }
}

test "load_extensions propagates NotFound" {
  let registry = ExtensionFactoryRegistry::new()
  let configs : Array[ExtensionConfig] = [{ name: "missing", enabled: true, options: None }]
  match load_extensions(registry, configs) {
    Err(NotFound(name)) => assert_eq(name, "missing")
    _ => fail("expected NotFound")
  }
}
