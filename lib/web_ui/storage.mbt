priv struct InMemoryStoreEntry {
  key : String
  value : Json
}

priv struct InMemoryStoreData {
  name : String
  mut entries : Array[InMemoryStoreEntry]
}

priv struct InMemoryStorageBackendState {
  stores : Array[InMemoryStoreData]
}

pub(all) struct InMemoryStorageBackend {
  backend : StorageBackend
}

pub fn settings_store_config() -> StoreConfig {
  { name: "settings", key_path: None, auto_increment: false, indices: [] }
}

pub fn provider_keys_store_config() -> StoreConfig {
  { name: "provider-keys", key_path: None, auto_increment: false, indices: [] }
}

pub fn sessions_store_config() -> StoreConfig {
  {
    name: "sessions",
    key_path: Some("id"),
    auto_increment: false,
    indices: [{ name: "last_modified", key_path: "last_modified", unique: false }],
  }
}

pub fn sessions_metadata_store_config() -> StoreConfig {
  {
    name: "sessions-metadata",
    key_path: Some("id"),
    auto_increment: false,
    indices: [{ name: "last_modified", key_path: "last_modified", unique: false }],
  }
}

pub fn custom_providers_store_config() -> StoreConfig {
  { name: "custom-providers", key_path: None, auto_increment: false, indices: [] }
}

pub fn default_indexed_db_config(db_name? : String = "pi-web-ui", version? : Int = 1) -> IndexedDbConfig {
  {
    db_name,
    version,
    stores: [
      settings_store_config(),
      provider_keys_store_config(),
      sessions_store_config(),
      sessions_metadata_store_config(),
      custom_providers_store_config(),
    ],
  }
}

pub fn InMemoryStorageBackend::new(config? : IndexedDbConfig = default_indexed_db_config()) -> InMemoryStorageBackend {
  let state : Ref[InMemoryStorageBackendState] = Ref::new({ stores: [] })
  for store in config.stores {
    state.val.stores.push({ name: store.name, entries: [] })
  }
  {
    backend: {
      get_json: fn(store_name, key) { Ok(in_memory_backend_get_json(state.val, store_name, key)) },
      set_json: fn(store_name, key, value) {
        in_memory_backend_set_json(state.val, store_name, key, value)
        Ok(())
      },
      delete_key: fn(store_name, key) {
        in_memory_backend_delete_key(state.val, store_name, key)
        Ok(())
      },
      keys: fn(store_name, prefix) { Ok(in_memory_backend_keys(state.val, store_name, prefix)) },
      get_all_from_index: fn(store_name, index_name, direction) {
        Ok(in_memory_backend_get_all_from_index(state.val, store_name, index_name, direction))
      },
      clear_store: fn(store_name) {
        in_memory_backend_clear_store(state.val, store_name)
        Ok(())
      },
      has_key: fn(store_name, key) { Ok(in_memory_backend_has_key(state.val, store_name, key)) },
      transaction: fn(store_names, mode, operation) {
        in_memory_backend_transaction(state.val, store_names, mode, operation)
      },
      get_quota_info: fn() { Ok(in_memory_backend_quota_info(state.val)) },
      request_persistence: fn() { Ok(false) },
    },
  }
}

fn in_memory_backend_get_json(
  state : InMemoryStorageBackendState,
  store_name : String,
  key : String
) -> Json? {
  match in_memory_backend_find_store(state, store_name) {
    Some(store_index) =>
      for entry in state.stores[store_index].entries {
        if entry.key == key {
          return Some(entry.value)
        }
      }
    None => ()
  }
  None
}

fn in_memory_backend_set_json(
  state : InMemoryStorageBackendState,
  store_name : String,
  key : String,
  value : Json
) -> Unit {
  let store_index = in_memory_backend_find_or_create_store(state, store_name)
  for i in 0..<state.stores[store_index].entries.length() {
    if state.stores[store_index].entries[i].key == key {
      state.stores[store_index].entries[i] = { key, value }
      return
    }
  }
  state.stores[store_index].entries.push({ key, value })
}

fn in_memory_backend_delete_key(
  state : InMemoryStorageBackendState,
  store_name : String,
  key : String
) -> Unit {
  match in_memory_backend_find_store(state, store_name) {
    Some(store_index) => {
      let retained : Array[InMemoryStoreEntry] = []
      for entry in state.stores[store_index].entries {
        if entry.key != key {
          retained.push(entry)
        }
      }
      state.stores[store_index].entries = retained
    }
    None => ()
  }
}

fn in_memory_backend_keys(
  state : InMemoryStorageBackendState,
  store_name : String,
  prefix : String?
) -> Array[String] {
  let keys : Array[String] = []
  match in_memory_backend_find_store(state, store_name) {
    Some(store_index) =>
      for entry in state.stores[store_index].entries {
        match prefix {
          Some(value) =>
            if entry.key.has_prefix(value) {
              keys.push(entry.key)
            }
          None => keys.push(entry.key)
        }
      }
    None => ()
  }
  keys
}

fn in_memory_backend_get_all_from_index(
  state : InMemoryStorageBackendState,
  store_name : String,
  index_name : String,
  direction : SortDirection
) -> Array[Json] {
  let values : Array[Json] = []
  match in_memory_backend_find_store(state, store_name) {
    Some(store_index) =>
      for entry in state.stores[store_index].entries {
        values.push(entry.value)
      }
    None => ()
  }
  in_memory_backend_sort_values(values, index_name, direction)
}

fn in_memory_backend_clear_store(
  state : InMemoryStorageBackendState,
  store_name : String
) -> Unit {
  match in_memory_backend_find_store(state, store_name) {
    Some(store_index) => state.stores[store_index].entries.clear()
    None => ()
  }
}

fn in_memory_backend_has_key(
  state : InMemoryStorageBackendState,
  store_name : String,
  key : String
) -> Bool {
  in_memory_backend_get_json(state, store_name, key) is Some(_)
}

fn in_memory_backend_quota_info(state : InMemoryStorageBackendState) -> StorageQuotaInfo {
  let mut usage = 0
  for store in state.stores {
    for entry in store.entries {
      usage = usage + entry.key.length() + entry.value.stringify(escape_slash=false).length()
    }
  }
  let quota = 1024 * 1024
  {
    usage,
    quota,
    percent: usage.to_double() / quota.to_double() * 100.0,
  }
}

fn in_memory_backend_transaction(
  state : InMemoryStorageBackendState,
  store_names : Array[String],
  mode : TransactionMode,
  operation : (StorageTransaction) -> Result[Unit, String]
) -> Result[Unit, String] {
  ignore(store_names)
  ignore(mode)
  let transaction : StorageTransaction = {
    get_json: fn(store_name, key) { Ok(in_memory_backend_get_json(state, store_name, key)) },
    set_json: fn(store_name, key, value) {
      in_memory_backend_set_json(state, store_name, key, value)
      Ok(())
    },
    delete_key: fn(store_name, key) {
      in_memory_backend_delete_key(state, store_name, key)
      Ok(())
    },
  }
  operation(transaction)
}

fn in_memory_backend_find_store(
  state : InMemoryStorageBackendState,
  store_name : String
) -> Int? {
  for i in 0..<state.stores.length() {
    if state.stores[i].name == store_name {
      return Some(i)
    }
  }
  None
}

fn in_memory_backend_find_or_create_store(
  state : InMemoryStorageBackendState,
  store_name : String
) -> Int {
  match in_memory_backend_find_store(state, store_name) {
    Some(index) => index
    None => {
      state.stores.push({ name: store_name, entries: [] })
      state.stores.length() - 1
    }
  }
}

fn in_memory_backend_sort_values(
  values : Array[Json],
  index_name : String,
  direction : SortDirection
) -> Array[Json] {
  let mut remaining = values.copy()
  let sorted : Array[Json] = []
  while remaining.length() > 0 {
    let index = in_memory_backend_pick_sorted_index(remaining, index_name, direction)
    sorted.push(remaining[index])
    remaining = in_memory_backend_remove_value_at(remaining, index)
  }
  sorted
}

fn in_memory_backend_pick_sorted_index(
  values : Array[Json],
  index_name : String,
  direction : SortDirection
) -> Int {
  let mut selected = 0
  for i in 1..<values.length() {
    let left = in_memory_backend_index_value(values[i], index_name)
    let right = in_memory_backend_index_value(values[selected], index_name)
    let should_replace = match direction {
      SortDirection::Asc => left < right
      SortDirection::Desc => left > right
    }
    if should_replace {
      selected = i
    }
  }
  selected
}

fn in_memory_backend_index_value(value : Json, index_name : String) -> String {
  match value {
    Object(obj) =>
      match obj.get(index_name) {
        Some(String(text)) => text
        Some(Number(number, ..)) => number.to_string()
        Some(True) => "true"
        Some(False) => "false"
        Some(other) => other.stringify(escape_slash=false)
        None => ""
      }
    _ => ""
  }
}

fn in_memory_backend_remove_value_at(values : Array[Json], index : Int) -> Array[Json] {
  let retained : Array[Json] = []
  for i in 0..<values.length() {
    if i != index {
      retained.push(values[i])
    }
  }
  retained
}
