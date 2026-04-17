pub fn parse_cli_args(
  argv : Array[String],
  cwd? : String = "."
) -> Result[CliParseResult, String] {
  // Normalise argv so argv[0] is the "pimbt" program name regardless of host.
  // JS target's @env.args() returns [node, script.js, ...user_args]; the native
  // and test call sites pass [pimbt, ...user_args] directly. Strip the node /
  // script-path preamble so subcommand dispatch works in both shapes.
  let argv = normalise_argv(argv)
  // Check for subcommands first
  if argv.length() >= 2 && argv[1] == "login" {
    return parse_login_args(argv, cwd)
  }
  if argv.length() >= 2 && argv[1] == "models" {
    return parse_models_args(argv, cwd)
  }
  let mut mode = CliMode::Interactive
  let mut system_prompt = default_system_prompt()
  let mut session_path_arg : String? = None
  let mut session_dir_arg : String? = None
  let mut persist_session = true
  let mut continue_session = false
  let mut resume_session = false
  let mut effective_cwd = cwd
  let mut model_id = "mock-cli"
  let mut provider_id = "openai"
  let mut api_id = "openai-responses"
  let mut base_url : String? = None
  let mut thinking_level = @agent.AgentThinkingLevel::Off
  let messages : Array[String] = []

  let mut i = if argv.length() > 0 { 1 } else { 0 }
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--help" || arg == "-h" {
      return Ok(CliParseResult::Help(cli_help_text()))
    } else if arg == "--print" || arg == "-p" {
      mode = CliMode::Print
    } else if arg == "--rpc" {
      mode = CliMode::Rpc
    } else if arg == "--system-prompt" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --system-prompt")
      }
      i = i + 1
      system_prompt = argv[i]
    } else if arg == "--continue" || arg == "-c" {
      continue_session = true
    } else if arg == "--resume" || arg == "-r" {
      resume_session = true
    } else if arg == "--session" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --session")
      }
      i = i + 1
      session_path_arg = Some(argv[i])
    } else if arg == "--session-dir" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --session-dir")
      }
      i = i + 1
      session_dir_arg = Some(argv[i])
    } else if arg == "--no-session" {
      persist_session = false
      session_path_arg = None
    } else if arg == "--cwd" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --cwd")
      }
      i = i + 1
      effective_cwd = argv[i]
    } else if arg == "--model" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --model")
      }
      i = i + 1
      model_id = argv[i]
    } else if arg == "--provider" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --provider")
      }
      i = i + 1
      provider_id = argv[i]
    } else if arg == "--api" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --api")
      }
      i = i + 1
      api_id = argv[i]
    } else if arg == "--base-url" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --base-url")
      }
      i = i + 1
      base_url = Some(argv[i])
    } else if arg == "--thinking" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --thinking")
      }
      i = i + 1
      match parse_thinking_level(argv[i]) {
        Some(level) => thinking_level = level
        None => return Err("unknown thinking level: " + argv[i])
      }
    } else if arg.has_prefix("-") {
      return Err("unknown option: " + arg)
    } else {
      messages.push(arg)
    }
    i = i + 1
  }

  let session_path = match session_path_arg {
    Some(path) => Some(resolve_cli_path(effective_cwd, path))
    None => None
  }
  let session_dir = match session_dir_arg {
    Some(path) => Some(resolve_cli_path(effective_cwd, path))
    None => None
  }

  if !persist_session && session_path is Some(_) {
    return Err("--session and --no-session cannot be used together")
  }
  if !persist_session && continue_session {
    return Err("--continue and --no-session cannot be used together")
  }
  if !persist_session && resume_session {
    return Err("--resume and --no-session cannot be used together")
  }
  let session_mode_count =
    cli_bool_to_int(session_path is Some(_)) +
    cli_bool_to_int(continue_session) +
    cli_bool_to_int(resume_session)
  if session_mode_count > 1 {
    return Err("--session, --continue, and --resume cannot be used together")
  }
  if mode == CliMode::Print && messages.length() == 0 {
    return Err("print mode requires at least one message")
  }

  Ok(CliParseResult::Run({
    mode,
    system_prompt,
    session_path,
    session_dir,
    persist_session,
    continue_session,
    resume_session,
    cwd: effective_cwd,
    model: cli_model(model_id, provider_id, api_id, base_url, thinking_level),
    thinking_level,
    messages,
  }))
}

pub fn default_system_prompt() -> String {
  "You are a coding assistant. Be concise, inspect the project state before making changes, and use tools when they materially help."
}

pub fn cli_help_text() -> String {
  [
    "pimbt - minimal coding agent CLI",
    "",
    "Usage:",
    "  pimbt [options] [messages...]",
    "  pimbt login --client-id <id>   # OAuth login (NyxID)",
    "  pimbt models                   # list providers + models on your NyxID account",
    "",
    "Options:",
    "  -h, --help                 Show this help",
    "  -p, --print                Run prompts and exit",
    "  --rpc                      Run JSONL RPC mode over stdin/stdout",
    "  --system-prompt <text>     Override the system prompt",
    "  -c, --continue             Continue the most recent saved session",
    "  -r, --resume               Choose a saved session to resume",
    "  --session <path>           Persist or resume a JSONL session file",
    "  --session-dir <path>       Directory used for multi-session storage",
    "  --no-session               Disable session persistence",
    "  --cwd <path>               Override working directory for tools",
    "  --model <id>               Set model id",
    "  --provider <id>            Set provider id",
    "  --api <id>                 Set API id (openai-responses, anthropic-messages, mistral-conversation, nyxid-gateway, etc.)",
    "  --base-url <url>           Override LLM API base URL",
    "  --thinking <level>         off|minimal|low|medium|high|xhigh",
    "",
    "Interactive commands:",
    "  :help                      Show REPL commands",
    "  :session                   Show current session info",
    "  :model <id>                Switch model id in-session",
    "  :thinking <level>          Switch thinking level in-session",
    "  :quit                      Exit the REPL",
  ].join("\n")
}

pub fn parse_thinking_level(raw : String) -> @agent.AgentThinkingLevel? {
  match raw {
    "off" => Some(@agent.AgentThinkingLevel::Off)
    "minimal" => Some(@agent.AgentThinkingLevel::Minimal)
    "low" => Some(@agent.AgentThinkingLevel::Low)
    "medium" => Some(@agent.AgentThinkingLevel::Medium)
    "high" => Some(@agent.AgentThinkingLevel::High)
    "xhigh" => Some(@agent.AgentThinkingLevel::XHigh)
    _ => None
  }
}

pub fn thinking_level_name(level : @agent.AgentThinkingLevel) -> String {
  match level {
    @agent.AgentThinkingLevel::Off => "off"
    @agent.AgentThinkingLevel::Minimal => "minimal"
    @agent.AgentThinkingLevel::Low => "low"
    @agent.AgentThinkingLevel::Medium => "medium"
    @agent.AgentThinkingLevel::High => "high"
    @agent.AgentThinkingLevel::XHigh => "xhigh"
  }
}

pub fn resolve_cli_path(cwd : String, path : String) -> String {
  if is_absolute_path(path) {
    path
  } else if cwd.has_suffix("/") {
    cwd + path
  } else {
    cwd + "/" + path
  }
}

fn cli_model(
  model_id : String,
  provider_id : String,
  api_id : String,
  base_url : String?,
  thinking_level : @agent.AgentThinkingLevel
) -> @ai.Model {
  {
    id: model_id,
    name: model_id,
    api: @ai.ApiId(api_id),
    provider: @ai.ProviderId(provider_id),
    base_url,
    reasoning: thinking_level != @agent.AgentThinkingLevel::Off,
    input_modalities: [@ai.InputModality::Text],
    cost: { input: 0.0, output: 0.0, cache_read: 0.0, cache_write: 0.0 },
    context_window: 128000,
    max_tokens: 8192,
  }
}

fn is_absolute_path(path : String) -> Bool {
  path.has_prefix("/") ||
  path.has_prefix("\\") ||
  (path.length() >= 3 && (path[1:3] == ":/" || path[1:3] == ":\\")) ||
  path.has_prefix("~")
}

fn cli_bool_to_int(value : Bool) -> Int {
  if value { 1 } else { 0 }
}

///| 解析 `pimbt login [options]` 子命令。
fn parse_login_args(argv : Array[String], cwd : String) -> Result[CliParseResult, String] {
  let mut config = LoginConfig::defaults(cwd)
  config = { ..config, client_id: host_env_var("NYXID_CLIENT_ID").unwrap_or("") }
  config = { ..config, base_url: host_env_var("NYXID_BASE_URL").unwrap_or(config.base_url) }

  let mut i = 2  // skip argv[0]=program, argv[1]=login
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--help" || arg == "-h" {
      return Ok(CliParseResult::Help(login_help_text()))
    } else if arg == "--provider" {
      guard i + 1 < argv.length() else { return Err("missing value for --provider") }
      i = i + 1
      config = { ..config, provider: argv[i] }
    } else if arg == "--client-id" {
      guard i + 1 < argv.length() else { return Err("missing value for --client-id") }
      i = i + 1
      config = { ..config, client_id: argv[i] }
    } else if arg == "--client-secret" {
      guard i + 1 < argv.length() else { return Err("missing value for --client-secret") }
      i = i + 1
      config = { ..config, client_secret: Some(argv[i]) }
    } else if arg == "--base-url" {
      guard i + 1 < argv.length() else { return Err("missing value for --base-url") }
      i = i + 1
      config = { ..config, base_url: argv[i] }
    } else if arg == "--scope" {
      guard i + 1 < argv.length() else { return Err("missing value for --scope") }
      i = i + 1
      config = { ..config, scope: argv[i] }
    } else if arg == "--port" {
      guard i + 1 < argv.length() else { return Err("missing value for --port") }
      i = i + 1
      try @string.parse_int(argv[i]) catch {
        _ => return Err("invalid port: " + argv[i])
      } noraise {
        port => config = { ..config, redirect_port: port }
      }
    } else if arg == "--credentials-path" {
      guard i + 1 < argv.length() else { return Err("missing value for --credentials-path") }
      i = i + 1
      config = { ..config, credentials_path: argv[i] }
    } else if arg.has_prefix("-") {
      return Err("unknown login option: " + arg)
    }
    i = i + 1
  }

  if config.provider != "nyxid" {
    return Err("only --provider nyxid is supported right now")
  }
  // client_id optional: if set, use standard OAuth 2.0 + PKCE flow;
  // otherwise use the simpler CLI flow (/cli-auth).
  Ok(CliParseResult::Login(config))
}

///| 如果 argv 前缀看起来是 `[node, /path/to/main.js, ...]`（JS target 下
/// `@env.args()` 的形状），丢掉这两个 entry，使后续 argv[0] 回到 "pimbt"。
/// 其它情况（测试用 ["pimbt", ...]、native binary 等）保持原样。
fn normalise_argv(argv : Array[String]) -> Array[String] {
  if argv.length() < 2 { return argv }
  let first = argv[0]
  let second = argv[1]
  let looks_like_node = first == "node" || first.has_suffix("/node") || first.has_suffix("/node.exe")
  let looks_like_js_script = second.has_suffix(".js") || second.has_suffix(".mjs") || second.has_suffix(".cjs")
  if looks_like_node && looks_like_js_script {
    let rest : Array[String] = ["pimbt"]
    for i in 2..<argv.length() {
      rest.push(argv[i])
    }
    return rest
  }
  argv
}

///| 解析 `pimbt models` 子命令。
fn parse_models_args(argv : Array[String], cwd : String) -> Result[CliParseResult, String] {
  let mut base_url = host_env_var("NYXID_BASE_URL").unwrap_or(@ai.nyxid_default_base_url)
  let mut creds_path = credentials_default_path(cwd)
  let mut bearer_override : String? = None

  let mut i = 2
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--help" || arg == "-h" {
      return Ok(CliParseResult::Help(models_help_text()))
    } else if arg == "--base-url" {
      guard i + 1 < argv.length() else { return Err("missing value for --base-url") }
      i = i + 1
      base_url = argv[i]
    } else if arg == "--credentials-path" {
      guard i + 1 < argv.length() else { return Err("missing value for --credentials-path") }
      i = i + 1
      creds_path = argv[i]
    } else if arg == "--bearer" {
      guard i + 1 < argv.length() else { return Err("missing value for --bearer") }
      i = i + 1
      bearer_override = Some(argv[i])
    } else if arg.has_prefix("-") {
      return Err("unknown models option: " + arg)
    }
    i = i + 1
  }
  Ok(CliParseResult::Models({
    base_url,
    credentials_path: creds_path,
    bearer_override,
  }))
}

pub fn models_help_text() -> String {
  [
    "pimbt models - list LLM providers and models available on your NyxID account",
    "",
    "Calls GET {base_url}/api/v1/llm/status with your stored NyxID access token",
    "and prints: connected providers (ready/expired/not_connected) + supported",
    "model IDs you can pass to `--model`.",
    "",
    "Usage:",
    "  pimbt models [options]",
    "",
    "Options:",
    "  --base-url <url>           NyxID base URL (default: https://nyx.chrono-ai.fun)",
    "  --credentials-path <path>  Credentials file (default: ~/.pimbt/nyxid-credentials.json)",
    "  --bearer <token>           Skip credentials file and use this Bearer token directly",
    "",
    "If you haven't logged in yet, run `pimbt login --client-id <your-client-id>` first.",
  ].join("\n")
}

pub fn login_help_text() -> String {
  [
    "pimbt login - authenticate with NyxID",
    "",
    "NyxID (https://nyx.chrono-ai.fun) is a credential-brokering LLM gateway.",
    "Configure your LLM API keys once in NyxID's web panel; pimbt never touches them.",
    "",
    "Default flow (no client_id needed):",
    "  1. pimbt opens https://nyx.chrono-ai.fun/cli-auth in your browser",
    "  2. You log in (or register with an invite code)",
    "  3. NyxID sends tokens back to pimbt automatically",
    "",
    "If you prefer standard OAuth 2.0 + PKCE, pass --client-id <id> to use a",
    "pre-registered OAuth application instead.",
    "",
    "Usage:",
    "  pimbt login                     # simplified flow, recommended",
    "  pimbt login --base-url <url>    # use a self-hosted NyxID",
    "  pimbt login --client-id <id>    # standard OAuth 2.0 + PKCE flow",
    "",
    "Options:",
    "  --provider <id>            OAuth provider (default: nyxid)",
    "  --client-id <id>           OAuth client id (required; or NYXID_CLIENT_ID env)",
    "  --client-secret <secret>   OAuth client secret (optional; confidential clients)",
    "  --base-url <url>           Provider base URL (default: https://nyx.chrono-ai.fun)",
    "  --scope <scope>            OAuth scope (default: empty, uses client's allowed_scopes)",
    "  --port <port>              Local callback port (default: 54545)",
    "  --credentials-path <path>  Where to save credentials (default: ~/.pimbt/nyxid-credentials.json)",
    "",
    "After login, run `pimbt models` to see which providers and models are available.",
  ].join("\n")
}
