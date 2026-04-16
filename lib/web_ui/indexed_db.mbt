pub impl Show for IndexConfig with output(self, logger) {
  logger.write_string("IndexConfig(")
  logger.write_string("name=")
  logger.write_object(self.name)
  logger.write_string(", key_path=")
  logger.write_object(self.key_path)
  logger.write_string(", unique=")
  logger.write_object(self.unique)
  logger.write_string(")")
}

pub impl Show for StoreConfig with output(self, logger) {
  logger.write_string("StoreConfig(")
  logger.write_string("name=")
  logger.write_object(self.name)
  logger.write_string(", key_path=")
  logger.write_object(self.key_path)
  logger.write_string(", auto_increment=")
  logger.write_object(self.auto_increment)
  logger.write_string(", indices=")
  logger.write_object(self.indices)
  logger.write_string(")")
}

pub(all) struct IndexedDbBackendConfig {
  db_name : String
  store_config : StoreConfig
} derive(Show)

pub fn create_indexed_db_backend(config : IndexedDbBackendConfig) -> StorageBackend {
  let backend = InMemoryStorageBackend::new(config={
    db_name: config.db_name,
    version: 1,
    stores: [config.store_config],
  })
  backend.backend
}
