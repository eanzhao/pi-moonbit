pub(all) struct SlashCommand {
  name : String
  description : String
  handler : (String, SlashCommandContext) -> Result[Unit, String]
}

pub(all) struct SlashCommandContext {
  session_manager : SessionManager
  agent : @agent.Agent
  cwd : String
  write : (String) -> Unit
}

pub(all) struct SlashCommandRegistry {
  mut commands : Array[SlashCommand]
}

pub fn SlashCommandRegistry::new() -> SlashCommandRegistry {
  { commands: [] }
}

pub fn SlashCommandRegistry::register(self : SlashCommandRegistry, command : SlashCommand) -> Unit {
  self.commands.push(command)
}

pub fn SlashCommandRegistry::get(self : SlashCommandRegistry, name : String) -> SlashCommand? {
  for cmd in self.commands {
    if cmd.name == name {
      return Some(cmd)
    }
  }
  None
}

pub fn SlashCommandRegistry::list(self : SlashCommandRegistry) -> Array[SlashCommand] {
  self.commands.copy()
}

pub fn SlashCommandRegistry::execute(
  self : SlashCommandRegistry,
  name : String,
  args : String,
  ctx : SlashCommandContext
) -> Result[Unit, String] {
  match self.get(name) {
    Some(cmd) => (cmd.handler)(args, ctx)
    None => Err("unknown command: :" + name)
  }
}

pub fn parse_slash_input(input : String) -> (String, String)? {
  if !input.has_prefix(":") || input.length() < 2 {
    return None
  }
  let rest = input[1:].to_string()
  let mut space_idx = -1
  let chars : Array[Char] = []
  for ch in rest.iter() {
    chars.push(ch)
  }
  let mut i = 0
  while i < chars.length() {
    if chars[i] == ' ' {
      space_idx = i
      break
    }
    i = i + 1
  }
  if space_idx < 0 {
    Some((rest, ""))
  } else {
    Some((rest[:space_idx].to_string(), rest[space_idx + 1:].to_string()))
  }
}

pub fn register_builtin_commands(registry : SlashCommandRegistry) -> Unit {
  registry.register({
    name: "help",
    description: "List all commands",
    handler: fn(_args, ctx) {
      for cmd in ctx.session_manager.get_entries() {
        ignore(cmd)
      }
      (ctx.write)("Use :help, :model, :thinking, :session, :tools, :compact, :clear, :quit\n")
      Ok(())
    },
  })
  registry.register({
    name: "tools",
    description: "List available tools",
    handler: fn(_args, ctx) {
      let tools = ctx.agent.state.tools
      let lines : Array[String] = []
      for tool in tools {
        lines.push("  " + tool.name + " — " + tool.description)
      }
      (ctx.write)(lines.join("\n") + "\n")
      Ok(())
    },
  })
  registry.register({
    name: "clear",
    description: "Clear screen",
    handler: fn(_args, ctx) {
      (ctx.write)("\u001b[2J\u001b[H")
      Ok(())
    },
  })
}
