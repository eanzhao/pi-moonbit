///| 扩展加载器 — 从配置声明加载扩展。
///
/// MoonBit 不支持运行时动态链接，因此扩展以「编译期注册 + 配置激活」模式工作：
/// 1. 扩展作为 MoonBit 包导出工厂函数 `fn create_my_extension() -> CodingExtension`
/// 2. 宿主代码调用工厂函数得到扩展实例
/// 3. 通过配置文件选择启用哪些扩展
///
/// 此模块提供配置驱动的扩展管理。

///| 扩展加载错误。
pub(all) suberror ExtensionLoadError {
  NotFound(String)
  FactoryFailed(String)
  ConfigError(String)
  RegistrationFailed(String)
}

///| 扩展工厂注册表。
pub(all) struct ExtensionFactoryRegistry {
  mut factories : Array[ExtensionFactoryEntry]
}

///| 工厂函数包装。
pub(all) struct ExtensionFactoryEntry {
  name : String
  factory : () -> Result[CodingExtension, String]
}

///| 创建工厂注册表。
pub fn ExtensionFactoryRegistry::new() -> ExtensionFactoryRegistry {
  { factories: [] }
}

///| 注册扩展工厂。
pub fn ExtensionFactoryRegistry::register(
  self : ExtensionFactoryRegistry,
  name : String,
  factory : () -> Result[CodingExtension, String]
) -> Unit {
  for i = 0; i < self.factories.length(); i = i + 1 {
    if self.factories[i].name == name {
      self.factories[i] = { name, factory }
      return
    }
  }
  self.factories.push({ name, factory })
}

///| 按名称创建扩展实例。
pub fn ExtensionFactoryRegistry::create(
  self : ExtensionFactoryRegistry,
  name : String
) -> Result[CodingExtension, ExtensionLoadError] {
  for entry in self.factories {
    if entry.name == name {
      match (entry.factory)() {
        Ok(ext) => return Ok(ext)
        Err(msg) => return Err(FactoryFailed(name + ": " + msg))
      }
    }
  }
  Err(NotFound(name))
}

///| 列出所有已注册工厂。
pub fn ExtensionFactoryRegistry::list(self : ExtensionFactoryRegistry) -> Array[String] {
  let names : Array[String] = []
  for entry in self.factories {
    names.push(entry.name)
  }
  names
}

///| 扩展配置。
pub(all) struct ExtensionConfig {
  name : String
  enabled : Bool
  options : Json?
}

///| 从 JSON 解析扩展配置列表。
///
/// JSON 格式：`[{"name": "my-ext", "enabled": true, "options": {...}}, ...]`
pub fn parse_extension_configs(json : Json) -> Result[Array[ExtensionConfig], String] {
  guard json is Array(items) else {
    return Err("expected array of extension configs")
  }
  let configs : Array[ExtensionConfig] = []
  for item in items {
    guard item is Object(obj) else {
      return Err("extension config must be an object")
    }
    let name = match obj.get("name") {
      Some(String(n)) => n
      _ => return Err("extension config missing 'name'")
    }
    let enabled = match obj.get("enabled") {
      Some(True) => true
      Some(False) => false
      None => true  // default enabled
      _ => return Err("extension 'enabled' must be boolean")
    }
    let options = obj.get("options")
    configs.push({ name, enabled, options })
  }
  Ok(configs)
}

///| 从工厂注册表和配置列表构建 ExtensionRuntime。
pub fn load_extensions(
  registry : ExtensionFactoryRegistry,
  configs : Array[ExtensionConfig]
) -> Result[ExtensionRuntime, ExtensionLoadError] {
  let runtime = ExtensionRuntime::new()
  for config in configs {
    if !config.enabled {
      continue
    }
    match registry.create(config.name) {
      Ok(ext) => runtime.register(ext)
      Err(error) => return Err(error)
    }
  }
  Ok(runtime)
}

///| 格式化扩展加载错误。
pub fn extension_load_error_message(error : ExtensionLoadError) -> String {
  match error {
    NotFound(name) => "extension not found: " + name
    FactoryFailed(msg) => "factory failed: " + msg
    ConfigError(msg) => "config error: " + msg
    RegistrationFailed(msg) => "registration failed: " + msg
  }
}
