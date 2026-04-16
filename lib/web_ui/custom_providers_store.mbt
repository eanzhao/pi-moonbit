pub fn CustomProvidersStore::new(backend : StorageBackend) -> CustomProvidersStore {
  { backend: backend }
}

pub fn CustomProvidersStore::get_config(self : CustomProvidersStore) -> StoreConfig {
  ignore(self)
  custom_providers_store_config()
}

pub fn CustomProvidersStore::get(
  self : CustomProvidersStore,
  id : String
) -> Result[CustomProvider?, String] {
  match (self.backend.get_json)("custom-providers", id) {
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

pub fn CustomProvidersStore::set(
  self : CustomProvidersStore,
  provider : CustomProvider
) -> Result[Unit, String] {
  (self.backend.set_json)("custom-providers", provider.id, provider.to_json())
}

pub fn CustomProvidersStore::delete(
  self : CustomProvidersStore,
  id : String
) -> Result[Unit, String] {
  (self.backend.delete_key)("custom-providers", id)
}

pub fn CustomProvidersStore::get_all(self : CustomProvidersStore) -> Result[Array[CustomProvider], String] {
  let ids = match (self.backend.keys)("custom-providers", None) {
    Ok(keys) => keys
    Err(message) => return Err(message)
  }
  let providers : Array[CustomProvider] = []
  for id in ids {
    match self.get(id) {
      Ok(Some(provider)) => providers.push(provider)
      Ok(None) => ()
      Err(message) => return Err(message)
    }
  }
  Ok(providers)
}

pub fn CustomProvidersStore::has(
  self : CustomProvidersStore,
  id : String
) -> Result[Bool, String] {
  (self.backend.has_key)("custom-providers", id)
}
