pub(all) struct SettingsManager {
  mut settings : Map[String, Json]
}

pub fn SettingsManager::new() -> SettingsManager {
  { settings: {} }
}

pub fn SettingsManager::get(self : SettingsManager, key : String) -> Json? {
  self.settings.get(key)
}

pub fn SettingsManager::set(self : SettingsManager, key : String, value : Json) -> Unit {
  self.settings[key] = value
}

pub fn SettingsManager::delete(self : SettingsManager, key : String) -> Unit {
  self.settings.remove(key)
}

pub fn SettingsManager::get_string(self : SettingsManager, key : String) -> String? {
  match self.settings.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

pub fn SettingsManager::get_bool(self : SettingsManager, key : String) -> Bool? {
  match self.settings.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

pub fn SettingsManager::get_int(self : SettingsManager, key : String) -> Int? {
  match self.settings.get(key) {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

pub fn SettingsManager::get_model_id(self : SettingsManager) -> String? {
  self.get_string("model_id")
}

pub fn SettingsManager::set_model_id(self : SettingsManager, id : String) -> Unit {
  self.set("model_id", Json::string(id))
}

pub fn SettingsManager::get_thinking_level(self : SettingsManager) -> String? {
  self.get_string("thinking_level")
}

pub fn SettingsManager::set_thinking_level(self : SettingsManager, level : String) -> Unit {
  self.set("thinking_level", Json::string(level))
}

pub fn SettingsManager::get_active_tools(self : SettingsManager) -> Array[String] {
  match self.settings.get("active_tools") {
    Some(Array(arr)) => {
      let result : Array[String] = []
      for item in arr {
        match item {
          String(s) => result.push(s)
          _ => ()
        }
      }
      result
    }
    _ => []
  }
}

pub fn SettingsManager::set_active_tools(self : SettingsManager, tools : Array[String]) -> Unit {
  self.set("active_tools", Json::array(tools.map(fn(t) { Json::string(t) })))
}

pub fn SettingsManager::to_json(self : SettingsManager) -> Json {
  Json::object(self.settings)
}

pub fn SettingsManager::load_from_json(json : Json) -> SettingsManager {
  match json {
    Object(map) => { settings: map }
    _ => SettingsManager::new()
  }
}
