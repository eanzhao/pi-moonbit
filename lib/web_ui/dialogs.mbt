///| 对话框数据模型（纯数据，不含 DOM）。

///| API key 输入对话框。
pub(all) struct ApiKeyDialog {
  provider_name : String
  provider_id : String
  current_value : String?
  help_text : String?
}

pub fn ApiKeyDialog::new(provider_id : String, provider_name : String) -> ApiKeyDialog {
  { provider_name, provider_id, current_value: None, help_text: None }
}

///| 模型选择器对话框状态。
pub(all) struct ModelSelectorDialog {
  available_models : Array[SelectableModel]
  current_model : SelectableModel?
  filter_query : String
  filter_reasoning : Bool
  filter_vision : Bool
}

pub fn ModelSelectorDialog::new(models : Array[SelectableModel]) -> ModelSelectorDialog {
  { available_models: models, current_model: None, filter_query: "", filter_reasoning: false, filter_vision: false }
}

pub fn ModelSelectorDialog::filtered(self : ModelSelectorDialog) -> Array[SelectableModel] {
  filter_selectable_models(
    self.available_models,
    search_query=self.filter_query,
    filter_reasoning=self.filter_reasoning,
    filter_vision=self.filter_vision,
  )
}

///| 自定义 provider 对话框。
pub(all) struct CustomProviderDialog {
  mode : CustomProviderDialogMode
  editing : CustomProvider
}

pub(all) enum CustomProviderDialogMode {
  Create
  Edit(String)  // existing provider id
} derive(Show)

pub fn CustomProviderDialog::new_for_create() -> CustomProviderDialog {
  {
    mode: Create,
    editing: {
      id: "",
      name: "",
      provider_type: CustomProviderType::OpenaiCompletions,
      base_url: "",
      api_key: None,
      models: None,
    },
  }
}

pub fn CustomProviderDialog::new_for_edit(provider : CustomProvider) -> CustomProviderDialog {
  { mode: Edit(provider.id), editing: provider }
}

///| 设置对话框。
pub(all) struct SettingsDialog {
  sections : Array[SettingsSection]
  active_section : String?
}

pub(all) struct SettingsSection {
  id : String
  title : String
  description : String
}

pub fn SettingsDialog::new() -> SettingsDialog {
  {
    sections: [
      { id: "providers", title: "Providers", description: "Manage API keys and custom providers" },
      { id: "models", title: "Models", description: "Default model and thinking level" },
      { id: "proxy", title: "Proxy", description: "CORS proxy settings" },
      { id: "storage", title: "Storage", description: "Session and settings persistence" },
      { id: "appearance", title: "Appearance", description: "Theme and UI preferences" },
    ],
    active_section: None,
  }
}

///| 会话列表对话框。
pub(all) struct SessionListDialog {
  sessions : Array[SessionMetadata]
  selected_id : String?
  search_query : String
}

pub fn SessionListDialog::new(sessions : Array[SessionMetadata]) -> SessionListDialog {
  { sessions, selected_id: None, search_query: "" }
}

pub fn SessionListDialog::filtered(self : SessionListDialog) -> Array[SessionMetadata] {
  if self.search_query == "" { return self.sessions.copy() }
  let query = self.search_query.to_lower()
  let result : Array[SessionMetadata] = []
  for session in self.sessions {
    if session.title.to_lower().contains(query) ||
       session.preview.to_lower().contains(query) {
      result.push(session)
    }
  }
  result
}

///| 存储持久化对话框（请求浏览器授予持久化存储权限）。
pub(all) struct PersistentStorageDialog {
  storage_info : StorageQuotaInfo
  has_persistence : Bool
  message : String
}

pub fn PersistentStorageDialog::new(
  storage_info : StorageQuotaInfo,
  has_persistence : Bool
) -> PersistentStorageDialog {
  let message = if has_persistence {
    "Persistent storage granted. Your sessions are safe from auto-eviction."
  } else {
    "Request persistent storage to protect your sessions from browser cleanup."
  }
  { storage_info, has_persistence, message }
}
