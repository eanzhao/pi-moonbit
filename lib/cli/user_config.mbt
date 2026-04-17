///| 用户配置（保存在 `~/.pimbt/config.json`）。
///
/// 记录用户偏好，避免每次都要传 `--api` / `--model`：
/// - default_api / default_model: 默认走哪个 API + 模型
/// - default_provider: model 选择器里默认筛选的 provider
///
/// 字段都是可选的，缺失字段表示 "由 CLI flag / env / 内置 default 决定"。

pub(all) struct PimbtUserConfig {
  default_api : String?
  default_model : String?
  default_provider : String?
  default_thinking : String?
}

pub fn PimbtUserConfig::empty() -> PimbtUserConfig {
  { default_api: None, default_model: None, default_provider: None, default_thinking: None }
}

pub fn pimbt_user_config_path(cwd : String) -> String {
  let home = host_env_var("HOME").unwrap_or(cwd)
  if home.has_suffix("/") {
    home + ".pimbt/config.json"
  } else {
    home + "/.pimbt/config.json"
  }
}

pub fn load_user_config(runtime : CliHostRuntime, path : String) -> PimbtUserConfig {
  match (runtime.read_text)(path) {
    Err(_) => PimbtUserConfig::empty()
    Ok(text) => {
      let json = try { @json.parse(text) } catch { _ => return PimbtUserConfig::empty() }
      parse_user_config(json)
    }
  }
}

fn parse_user_config(json : Json) -> PimbtUserConfig {
  match json {
    Object(obj) => {
      let get_str = fn(k) {
        match obj.get(k) {
          Some(String(s)) if s.length() > 0 => Some(s)
          _ => None
        }
      }
      {
        default_api: get_str("default_api"),
        default_model: get_str("default_model"),
        default_provider: get_str("default_provider"),
        default_thinking: get_str("default_thinking"),
      }
    }
    _ => PimbtUserConfig::empty()
  }
}

pub fn save_user_config(runtime : CliHostRuntime, path : String, config : PimbtUserConfig) -> Result[Unit, String] {
  let fields : Map[String, Json] = {}
  match config.default_api {
    Some(v) => fields["default_api"] = Json::string(v)
    None => ()
  }
  match config.default_model {
    Some(v) => fields["default_model"] = Json::string(v)
    None => ()
  }
  match config.default_provider {
    Some(v) => fields["default_provider"] = Json::string(v)
    None => ()
  }
  match config.default_thinking {
    Some(v) => fields["default_thinking"] = Json::string(v)
    None => ()
  }
  let json = Json::object(fields)
  (runtime.write_text)(path, json.stringify(escape_slash=false))
}

pub fn nyxid_credentials_exist(runtime : CliHostRuntime, path : String) -> Bool {
  (runtime.file_exists)(path)
}
