pub(all) enum AttachmentKind {
  Image
  Document
} derive(Eq, ToJson, FromJson)

pub(all) struct Attachment {
  id : String
  kind : AttachmentKind
  file_name : String
  mime_type : String
  size : Int
  content_base64 : String
  extracted_text : String?
  preview_base64 : String?
} derive(Eq, ToJson, FromJson)

pub(all) struct UserMessageWithAttachments {
  content : Array[@ai.ContentBlock]
  timestamp : Double
  attachments : Array[Attachment]
} derive(Eq, ToJson, FromJson)

pub(all) enum ArtifactAction {
  Create
  Update
  Delete
} derive(Eq, ToJson, FromJson)

pub(all) struct ArtifactMessage {
  action : ArtifactAction
  filename : String
  content : String?
  title : String?
  timestamp : String
} derive(Eq, ToJson, FromJson)

pub(all) enum ChatMessage {
  Standard(@ai.Message)
  UserWithAttachments(UserMessageWithAttachments)
  Artifact(ArtifactMessage)
} derive(Eq, ToJson, FromJson)

pub(all) struct SessionMetadata {
  id : String
  title : String
  created_at : String
  last_modified : String
  message_count : Int
  usage : @ai.Usage
  thinking_level : @agent.AgentThinkingLevel
  preview : String
} derive(Eq, ToJson, FromJson)

pub(all) struct SessionData {
  id : String
  title : String
  model : @ai.Model
  thinking_level : @agent.AgentThinkingLevel
  messages : Array[ChatMessage]
  created_at : String
  last_modified : String
} derive(Eq, ToJson, FromJson)

pub(all) struct InMemorySessionsStore {
  mut sessions : Array[SessionData]
  mut metadata : Array[SessionMetadata]
}

pub(all) enum AutoDiscoveryProviderType {
  Ollama
  LlamaCpp
  Vllm
  Lmstudio
} derive(Eq, ToJson, FromJson)

pub(all) enum CustomProviderType {
  AutoDiscovery(AutoDiscoveryProviderType)
  OpenaiCompletions
  OpenaiResponses
  AnthropicMessages
} derive(Eq, ToJson, FromJson)

pub(all) struct CustomProvider {
  id : String
  name : String
  provider_type : CustomProviderType
  base_url : String
  api_key : String?
  models : Array[@ai.Model]?
} derive(Eq, ToJson, FromJson)

pub(all) enum SortDirection {
  Asc
  Desc
} derive(Eq)

pub(all) enum TransactionMode {
  ReadOnly
  ReadWrite
} derive(Eq)

pub(all) struct IndexConfig {
  name : String
  key_path : String
  unique : Bool
} derive(Eq)

pub(all) struct StoreConfig {
  name : String
  key_path : String?
  auto_increment : Bool
  indices : Array[IndexConfig]
} derive(Eq)

pub(all) struct IndexedDbConfig {
  db_name : String
  version : Int
  stores : Array[StoreConfig]
} derive(Eq)

pub(all) struct StorageQuotaInfo {
  usage : Int
  quota : Int
  percent : Double
} derive(Eq)

pub(all) struct StorageTransaction {
  get_json : (String, String) -> Result[Json?, String]
  set_json : (String, String, Json) -> Result[Unit, String]
  delete_key : (String, String) -> Result[Unit, String]
}

pub(all) struct StorageBackend {
  get_json : (String, String) -> Result[Json?, String]
  set_json : (String, String, Json) -> Result[Unit, String]
  delete_key : (String, String) -> Result[Unit, String]
  keys : (String, String?) -> Result[Array[String], String]
  get_all_from_index : (String, String, SortDirection) -> Result[Array[Json], String]
  clear_store : (String) -> Result[Unit, String]
  has_key : (String, String) -> Result[Bool, String]
  transaction : (
    Array[String],
    TransactionMode,
    (StorageTransaction) -> Result[Unit, String]
  ) -> Result[Unit, String]
  get_quota_info : () -> Result[StorageQuotaInfo, String]
  request_persistence : () -> Result[Bool, String]
}

pub(all) struct SettingsStore {
  backend : StorageBackend
}

pub(all) struct ProviderKeysStore {
  backend : StorageBackend
}

pub(all) struct SessionsStore {
  backend : StorageBackend
}

pub(all) struct CustomProvidersStore {
  backend : StorageBackend
}

pub(all) struct AppStorage {
  backend : StorageBackend
  settings : SettingsStore
  provider_keys : ProviderKeysStore
  sessions : SessionsStore
  custom_providers : CustomProvidersStore
}

pub(all) struct ProxySettings {
  enabled : Bool
  url : String
} derive(Eq, ToJson, FromJson)

pub(all) struct SelectableModel {
  provider : String
  model : @ai.Model
} derive(Eq)
