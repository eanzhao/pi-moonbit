let global_app_storage : Ref[AppStorage?] = Ref::new(None)

pub fn AppStorage::new(backend : StorageBackend) -> AppStorage {
  {
    backend: backend,
    settings: SettingsStore::new(backend),
    provider_keys: ProviderKeysStore::new(backend),
    sessions: SessionsStore::new(backend),
    custom_providers: CustomProvidersStore::new(backend),
  }
}

pub fn app_storage_with_in_memory_backend(
  config? : IndexedDbConfig = default_indexed_db_config()
) -> AppStorage {
  let backend = InMemoryStorageBackend::new(config=config)
  AppStorage::new(backend.backend)
}

pub fn AppStorage::get_quota_info(self : AppStorage) -> Result[StorageQuotaInfo, String] {
  (self.backend.get_quota_info)()
}

pub fn AppStorage::request_persistence(self : AppStorage) -> Result[Bool, String] {
  (self.backend.request_persistence)()
}

pub fn set_app_storage(storage : AppStorage) -> Unit {
  global_app_storage.val = Some(storage)
}

pub fn clear_app_storage() -> Unit {
  global_app_storage.val = None
}

pub fn get_app_storage() -> Result[AppStorage, String] {
  match global_app_storage.val {
    Some(storage) => Ok(storage)
    None => Err("app storage not initialized")
  }
}
