pub(all) struct SystemPromptConfig {
  base_prompt : String
  tools : Array[@agent.AgentTool]
  cwd : String
  project_context : String?
  extension_snippets : Array[String]
  guidelines : Array[String]
}

pub fn build_system_prompt(config : SystemPromptConfig) -> String {
  let parts : Array[String] = [config.base_prompt]
  if config.cwd.length() > 0 {
    parts.push("\n\n## Working Directory\n" + config.cwd)
  }
  if config.tools.length() > 0 {
    parts.push("\n\n## Available Tools")
    for tool in config.tools {
      parts.push("- " + tool.name + ": " + tool.description)
    }
  }
  match config.project_context {
    Some(ctx) if ctx.length() > 0 => parts.push("\n\n## Project Context\n" + ctx)
    _ => ()
  }
  for snippet in config.extension_snippets {
    parts.push("\n\n" + snippet)
  }
  if config.guidelines.length() > 0 {
    parts.push("\n\n## Guidelines")
    for g in config.guidelines {
      parts.push("- " + g)
    }
  }
  parts.join("\n")
}
