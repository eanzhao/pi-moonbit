pub(all) enum CliMode {
  Interactive
  Print
  Rpc
} derive(Eq)

pub(all) struct CliConfig {
  mode : CliMode
  system_prompt : String
  session_path : String?
  session_dir : String?
  persist_session : Bool
  continue_session : Bool
  resume_session : Bool
  cwd : String
  model : @ai.Model
  thinking_level : @agent.AgentThinkingLevel
  messages : Array[String]
} derive(Eq)

pub(all) enum CliParseResult {
  Run(CliConfig)
  Help(String)
  Login(LoginConfig)
  Models(ModelsConfig)
  Providers(ProvidersConfig)
}

pub(all) enum ProvidersAction {
  List
  Connect(String)      // provider slug
  Disconnect(String)   // provider id
}

pub(all) struct ProvidersConfig {
  action : ProvidersAction
  base_url : String
  credentials_path : String
  bearer_override : String?
  api_key : String?    // for `connect`; if None, prompt interactively
  label : String?
}

pub(all) struct ModelsConfig {
  base_url : String
  credentials_path : String
  bearer_override : String?  // allows manual override for ad-hoc checks
}

pub(all) struct CliHostRuntime {
  read_text : (String) -> Result[String, String]
  write_text : (String, String) -> Result[Unit, String]
  file_exists : (String) -> Bool
  list_files : (String) -> Result[Array[String], String]
  run_command : (String, String) -> Result[@coding_agent.CommandExecutionResult, String]
  stdout_write : (String) -> Unit
  stderr_write : (String) -> Unit
  read_line : (String) -> String?
  current_dir : () -> String
  now_iso : () -> String
  agent_stream : @agent.AgentStreamFn?
}

pub(all) struct PersistedSessionFileHeader {
  kind : String
  version : Int
  header : @coding_agent.SessionHeader
  cwd : String
  leaf_id : String?
  next_entry_id : Int
} derive(Eq, ToJson, FromJson)

pub(all) struct PersistedSessionRecord {
  kind : String
  entry : @coding_agent.SessionEntry
} derive(Eq, ToJson, FromJson)

pub(all) struct LoadedSession {
  cwd : String
  session_manager : @coding_agent.SessionManager
}

pub(all) struct SessionInfo {
  path : String
  session_id : String
  cwd : String
  timestamp : String
  parent_session : String?
  leaf_id : String?
  entry_count : Int
  preview : String
} derive(Eq)

pub(all) struct CliApp {
  session : @coding_agent.AgentSession
  runtime : CliHostRuntime
  session_path : String?
  cwd : String
}
