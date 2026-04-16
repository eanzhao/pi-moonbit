pub fn SettingsStore::new(backend : StorageBackend) -> SettingsStore {
  { backend: backend }
}

pub fn SettingsStore::get_config(self : SettingsStore) -> StoreConfig {
  ignore(self)
  settings_store_config()
}

pub fn[T : FromJson] SettingsStore::get(self : SettingsStore, key : String) -> Result[T?, String] {
  match (self.backend.get_json)("settings", key) {
    Err(message) => Err(message)
    Ok(None) => Ok(None)
    Ok(Some(json)) =>
      try @json.from_json(json) catch {
        error => Err(error.to_string())
      } noraise {
        value => Ok(Some(value))
      }
  }
}

pub fn[T : ToJson] SettingsStore::set(
  self : SettingsStore,
  key : String,
  value : T
) -> Result[Unit, String] {
  (self.backend.set_json)("settings", key, value.to_json())
}

pub fn SettingsStore::delete(self : SettingsStore, key : String) -> Result[Unit, String] {
  (self.backend.delete_key)("settings", key)
}

pub fn SettingsStore::list(self : SettingsStore) -> Result[Array[String], String] {
  (self.backend.keys)("settings", None)
}

pub fn SettingsStore::clear(self : SettingsStore) -> Result[Unit, String] {
  (self.backend.clear_store)("settings")
}
