pub fn parse_cli_args(
  argv : Array[String],
  cwd? : String = "."
) -> Result[CliParseResult, String] {
  let mut mode = CliMode::Interactive
  let mut system_prompt = default_system_prompt()
  let mut session_path : String? = None
  let mut persist_session = true
  let mut effective_cwd = cwd
  let mut model_id = "mock-cli"
  let mut provider_id = "openai"
  let mut api_id = "openai-responses"
  let mut thinking_level = @agent.AgentThinkingLevel::Off
  let messages : Array[String] = []

  let mut i = if argv.length() > 0 { 1 } else { 0 }
  while i < argv.length() {
    let arg = argv[i]
    if arg == "--help" || arg == "-h" {
      return Ok(CliParseResult::Help(cli_help_text()))
    } else if arg == "--print" || arg == "-p" {
      mode = CliMode::Print
    } else if arg == "--system-prompt" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --system-prompt")
      }
      i = i + 1
      system_prompt = argv[i]
    } else if arg == "--session" {
      guard i + 1 < argv.length() else {
        return Err("missing value for --session")
      }
      i = i + 1
      session_path = Some(resolve_cli_path(effective_cwd, argv[i]))
    } else if arg == "--no-session" {
      persist_session = false
      session_path = None
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

  if !persist_session && session_path is Some(_) {
    return Err("--session and --no-session cannot be used together")
  }
  if mode == CliMode::Print && messages.length() == 0 {
    return Err("print mode requires at least one message")
  }

  Ok(CliParseResult::Run({
    mode,
    system_prompt,
    session_path,
    persist_session,
    cwd: effective_cwd,
    model: cli_model(model_id, provider_id, api_id, thinking_level),
    thinking_level,
    messages,
  }))
}

pub fn default_system_prompt() -> String {
  "You are a coding assistant. Be concise, inspect the project state before making changes, and use tools when they materially help."
}

pub fn cli_help_text() -> String {
  [
    "pi-moonbit - minimal coding agent CLI",
    "",
    "Usage:",
    "  pi-moonbit [options] [messages...]",
    "",
    "Options:",
    "  -h, --help                 Show this help",
    "  -p, --print                Run prompts and exit",
    "  --system-prompt <text>     Override the system prompt",
    "  --session <path>           Persist or resume a JSONL session file",
    "  --no-session               Disable session persistence",
    "  --cwd <path>               Override working directory for tools",
    "  --model <id>               Set model id",
    "  --provider <id>            Set provider id",
    "  --api <id>                 Set API id",
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
  thinking_level : @agent.AgentThinkingLevel
) -> @ai.Model {
  {
    id: model_id,
    name: model_id,
    api: @ai.ApiId(api_id),
    provider: @ai.ProviderId(provider_id),
    base_url: None,
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
