pub fn ProviderKeysStore::new(backend : StorageBackend) -> ProviderKeysStore {
  { backend: backend }
}

pub fn ProviderKeysStore::get_config(self : ProviderKeysStore) -> StoreConfig {
  ignore(self)
  provider_keys_store_config()
}

pub fn ProviderKeysStore::get(self : ProviderKeysStore, provider : String) -> Result[String?, String] {
  match (self.backend.get_json)("provider-keys", provider) {
    Err(message) => Err(message)
    Ok(None) => Ok(None)
    Ok(Some(String(value))) => Ok(Some(value))
    Ok(Some(_)) => Err("provider key must be a string")
  }
}

pub fn ProviderKeysStore::set(
  self : ProviderKeysStore,
  provider : String,
  key : String
) -> Result[Unit, String] {
  (self.backend.set_json)("provider-keys", provider, key.to_json())
}

pub fn ProviderKeysStore::delete(
  self : ProviderKeysStore,
  provider : String
) -> Result[Unit, String] {
  (self.backend.delete_key)("provider-keys", provider)
}

pub fn ProviderKeysStore::list(self : ProviderKeysStore) -> Result[Array[String], String] {
  (self.backend.keys)("provider-keys", None)
}

pub fn ProviderKeysStore::has(
  self : ProviderKeysStore,
  provider : String
) -> Result[Bool, String] {
  (self.backend.has_key)("provider-keys", provider)
}
