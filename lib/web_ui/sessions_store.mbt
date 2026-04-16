pub fn SessionsStore::new(backend : StorageBackend) -> SessionsStore {
  { backend: backend }
}

pub fn SessionsStore::get_config(self : SessionsStore) -> StoreConfig {
  ignore(self)
  sessions_store_config()
}

pub fn metadata_store_config() -> StoreConfig {
  sessions_metadata_store_config()
}

pub fn SessionsStore::save(
  self : SessionsStore,
  data : SessionData,
  metadata? : SessionMetadata? = None
) -> Result[Unit, String] {
  let resolved_metadata = match metadata {
    Some(value) => value
    None => session_metadata_from_data(data)
  }
  (self.backend.transaction)(
    ["sessions", "sessions-metadata"],
    TransactionMode::ReadWrite,
    fn(transaction) {
      match (transaction.set_json)("sessions", data.id, data.to_json()) {
        Ok(_) => ()
        Err(message) => return Err(message)
      }
      (transaction.set_json)(
        "sessions-metadata",
        resolved_metadata.id,
        resolved_metadata.to_json(),
      )
    },
  )
}

pub fn SessionsStore::get(
  self : SessionsStore,
  id : String
) -> Result[SessionData?, String] {
  match (self.backend.get_json)("sessions", id) {
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

pub fn SessionsStore::get_metadata(
  self : SessionsStore,
  id : String
) -> Result[SessionMetadata?, String] {
  match (self.backend.get_json)("sessions-metadata", id) {
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

pub fn SessionsStore::get_all_metadata(self : SessionsStore) -> Result[Array[SessionMetadata], String] {
  match (self.backend.get_all_from_index)("sessions-metadata", "last_modified", SortDirection::Desc) {
    Err(message) => Err(message)
    Ok(items) => {
      let metadata_list : Array[SessionMetadata] = []
      for item in items {
        let metadata : Result[SessionMetadata, String] = try @json.from_json(item) catch {
          error => Err(error.to_string())
        } noraise {
          value => Ok(value)
        }
        match metadata {
          Ok(value) => metadata_list.push(value)
          Err(message) => return Err(message)
        }
      }
      Ok(metadata_list)
    }
  }
}

pub fn SessionsStore::delete(self : SessionsStore, id : String) -> Result[Unit, String] {
  (self.backend.transaction)(
    ["sessions", "sessions-metadata"],
    TransactionMode::ReadWrite,
    fn(transaction) {
      match (transaction.delete_key)("sessions", id) {
        Ok(_) => ()
        Err(message) => return Err(message)
      }
      (transaction.delete_key)("sessions-metadata", id)
    },
  )
}

pub fn SessionsStore::update_title(
  self : SessionsStore,
  id : String,
  title : String
) -> Result[Unit, String] {
  let metadata = match self.get_metadata(id) {
    Ok(value) => value
    Err(message) => return Err(message)
  }
  match metadata {
    Some(current_metadata) =>
      match self.save(
        match self.get(id) {
          Ok(Some(data)) => {
            {
              id: data.id,
              title,
              model: data.model,
              thinking_level: data.thinking_level,
              messages: data.messages.copy(),
              created_at: data.created_at,
              last_modified: data.last_modified,
            }
          }
          Ok(None) => return Err("session not found: " + id)
          Err(message) => return Err(message)
        },
        metadata=Some({
          id: current_metadata.id,
          title,
          created_at: current_metadata.created_at,
          last_modified: current_metadata.last_modified,
          message_count: current_metadata.message_count,
          usage: current_metadata.usage,
          thinking_level: current_metadata.thinking_level,
          preview: current_metadata.preview,
        }),
      ) {
        Ok(_) => Ok(())
        Err(message) => Err(message)
      }
    None => Err("session metadata not found: " + id)
  }
}

pub fn SessionsStore::get_latest_session_id(self : SessionsStore) -> Result[String?, String] {
  match self.get_all_metadata() {
    Ok(metadata_list) =>
      if metadata_list.length() == 0 {
        Ok(None)
      } else {
        Ok(Some(metadata_list[0].id))
      }
    Err(message) => Err(message)
  }
}

pub fn SessionsStore::delete_session(self : SessionsStore, id : String) -> Result[Unit, String] {
  self.delete(id)
}

pub fn SessionsStore::load_session(
  self : SessionsStore,
  id : String
) -> Result[SessionData?, String] {
  self.get(id)
}

pub fn SessionsStore::get_quota_info(self : SessionsStore) -> Result[StorageQuotaInfo, String] {
  (self.backend.get_quota_info)()
}

pub fn SessionsStore::request_persistence(self : SessionsStore) -> Result[Bool, String] {
  (self.backend.request_persistence)()
}
