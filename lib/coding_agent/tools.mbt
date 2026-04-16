///| 创建内存工作区。
pub fn InMemoryWorkspace::new(files? : Array[WorkspaceFile] = []) -> InMemoryWorkspace {
  { files: files.copy() }
}

///| 读取内存工作区中的文件内容。
pub fn InMemoryWorkspace::get_content(self : InMemoryWorkspace, path : String) -> String? {
  for file in self.files {
    if file.path == path {
      return Some(file.content)
    }
  }
  None
}

///| 把内存工作区适配成工具运行时。
pub fn in_memory_workspace_runtime(workspace : Ref[InMemoryWorkspace]) -> WorkspaceRuntime {
  {
    read_text: fn(path) {
      match workspace.val.get_content(path) {
        Some(content) => Ok(content)
        None => Err("File \{path} not found")
      }
    },
    write_text: fn(path, content) {
      in_memory_workspace_write(workspace.val, path, content)
      Ok(())
    },
  }
}

///| 创建 read tool。
pub fn create_read_tool(runtime : WorkspaceRuntime) -> @agent.AgentTool {
  {
    name: "read",
    label: "Read",
    description: "Read a text file from the workspace",
    parameters: tool_parameters(["path"]),
    prepare_arguments: None,
    validate_arguments: Some(validate_read_arguments),
    execute: fn(_tool_call_id, args, _on_update) {
      match read_path_argument(args) {
        Err(message) => Err(message)
        Ok(path) =>
          match (runtime.read_text)(path) {
            Err(message) => Err(message)
            Ok(content) =>
              Ok({
                content: [@ai.ContentBlock::Text(content)],
                details: Json::object({
                  "path": Json::string(path),
                  "length": Json::number(content.length().to_double()),
                }),
              })
          }
      }
    },
  }
}

///| 创建 write tool。
pub fn create_write_tool(runtime : WorkspaceRuntime) -> @agent.AgentTool {
  {
    name: "write",
    label: "Write",
    description: "Create or overwrite a text file in the workspace",
    parameters: tool_parameters(["path", "content"]),
    prepare_arguments: None,
    validate_arguments: Some(validate_write_arguments),
    execute: fn(_tool_call_id, args, _on_update) {
      match write_arguments(args) {
        Err(message) => Err(message)
        Ok((path, content)) =>
          match (runtime.write_text)(path, content) {
            Err(message) => Err(message)
            Ok(_) =>
              Ok({
                content: [@ai.ContentBlock::Text("Wrote \{content.length()} characters to \{path}.")],
                details: Json::object({
                  "path": Json::string(path),
                  "length": Json::number(content.length().to_double()),
                }),
              })
          }
      }
    },
  }
}

///| 创建 edit tool，支持 replace_all 参数。
pub fn create_edit_tool(runtime : WorkspaceRuntime) -> @agent.AgentTool {
  {
    name: "edit",
    label: "Edit",
    description: "Replace matching text in a file. Set replace_all to true to replace all occurrences.",
    parameters: tool_parameters(["path", "old_text", "new_text"]),
    prepare_arguments: None,
    validate_arguments: Some(validate_edit_arguments),
    execute: fn(_tool_call_id, args, _on_update) {
      match edit_arguments(args) {
        Err(message) => Err(message)
        Ok((path, old_text, new_text)) => {
          let replace_all = match args {
            Object({ "replace_all": True, .. }) => true
            _ => false
          }
          match (runtime.read_text)(path) {
            Err(message) => Err(message)
            Ok(content) => {
              if !content.contains(old_text) {
                return Err("Text to replace was not found in \{path}")
              }
              let next_content = if replace_all {
                replace_all_occurrences(content, old_text, new_text)
              } else {
                content.replace(old=old_text, new=new_text)
              }
              match (runtime.write_text)(path, next_content) {
                Err(message) => Err(message)
                Ok(_) =>
                  Ok({
                    content: [@ai.ContentBlock::Text("Updated \{path}.")],
                    details: Json::object({
                      "path": Json::string(path),
                      "old_length": Json::number(old_text.length().to_double()),
                      "new_length": Json::number(new_text.length().to_double()),
                      "replace_all": Json::boolean(replace_all),
                    }),
                  })
              }
            }
          }
        }
      }
    },
  }
}

///| 创建 bash tool。
pub fn create_bash_tool(runtime : CommandRuntime) -> @agent.AgentTool {
  {
    name: "bash",
    label: "Bash",
    description: "Run a shell command through the injected command runtime",
    parameters: tool_parameters(["command"]),
    prepare_arguments: None,
    validate_arguments: Some(validate_bash_arguments),
    execute: fn(_tool_call_id, args, _on_update) {
      match bash_argument(args) {
        Err(message) => Err(message)
        Ok(command) =>
          match (runtime.run)(command) {
            Err(message) => Err(message)
            Ok(execution) => {
              let text = bash_tool_output_text(command, execution)
              if execution.cancelled || execution.exit_code != 0 {
                Err(text)
              } else {
                Ok({
                  content: [@ai.ContentBlock::Text(text)],
                  details: Json::object({
                    "command": Json::string(command),
                    "exit_code": Json::number(execution.exit_code.to_double()),
                    "cancelled": Json::boolean(execution.cancelled),
                    "truncated": Json::boolean(execution.truncated),
                  }),
                })
              }
            }
          }
      }
    },
  }
}

fn in_memory_workspace_write(workspace : InMemoryWorkspace, path : String, content : String) -> Unit {
  for i in 0..<workspace.files.length() {
    if workspace.files[i].path == path {
      workspace.files[i] = { path, content }
      return
    }
  }
  workspace.files.push({ path, content })
}

fn tool_parameters(required : Array[String]) -> Json {
  let required_json : Array[Json] = []
  for field in required {
    required_json.push(Json::string(field))
  }
  Json::object({
    "type": Json::string("object"),
    "required": Json::array(required_json),
  })
}

fn validate_read_arguments(args : Json) -> Result[Unit, String] {
  match read_path_argument(args) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}

fn validate_write_arguments(args : Json) -> Result[Unit, String] {
  match write_arguments(args) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}

fn validate_edit_arguments(args : Json) -> Result[Unit, String] {
  match edit_arguments(args) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}

fn validate_bash_arguments(args : Json) -> Result[Unit, String] {
  match bash_argument(args) {
    Ok(_) => Ok(())
    Err(message) => Err(message)
  }
}

fn read_path_argument(args : Json) -> Result[String, String] {
  guard args is Object({ "path": String(path), .. }) else {
    return Err("missing path")
  }
  Ok(path)
}

fn write_arguments(args : Json) -> Result[(String, String), String] {
  guard args is Object({ "path": String(path), "content": String(content), .. }) else {
    return Err("missing path or content")
  }
  Ok((path, content))
}

fn edit_arguments(args : Json) -> Result[(String, String, String), String] {
  guard args is Object({
    "path": String(path),
    "old_text": String(old_text),
    "new_text": String(new_text),
    ..
  }) else {
    return Err("missing path, old_text, or new_text")
  }
  Ok((path, old_text, new_text))
}

fn bash_argument(args : Json) -> Result[String, String] {
  guard args is Object({ "command": String(command), .. }) else {
    return Err("missing command")
  }
  Ok(command)
}

///| 创建 grep tool — 在文件内容中搜索文本模式。
pub fn create_grep_tool(runtime : WorkspaceRuntime) -> @agent.AgentTool {
  {
    name: "grep",
    label: "Grep",
    description: "Search for a text pattern in a file. Returns matching lines with line numbers.",
    parameters: tool_parameters(["path", "pattern"]),
    prepare_arguments: None,
    validate_arguments: None,
    execute: fn(_tool_call_id, args, _on_update) {
      guard args is Object({ "path": String(path), "pattern": String(pattern), .. }) else {
        return Err("missing path or pattern")
      }
      match (runtime.read_text)(path) {
        Err(message) => Err(message)
        Ok(content) => {
          let lines : Array[String] = []
          for line in content.split("\n") {
            lines.push(line.to_string())
          }
          let matches : Array[String] = []
          let pattern_lower = pattern.to_lower()
          for i = 0; i < lines.length(); i = i + 1 {
            if lines[i].to_lower().contains(pattern_lower) {
              matches.push("\{i + 1}: \{lines[i]}")
            }
          }
          if matches.length() == 0 {
            Ok({
              content: [@ai.ContentBlock::Text("No matches found for '\{pattern}' in \{path}")],
              details: Json::object({
                "path": Json::string(path),
                "pattern": Json::string(pattern),
                "match_count": Json::number(0.0),
              }),
            })
          } else {
            let result_text = matches.join("\n")
            Ok({
              content: [@ai.ContentBlock::Text(result_text)],
              details: Json::object({
                "path": Json::string(path),
                "pattern": Json::string(pattern),
                "match_count": Json::number(matches.length().to_double()),
              }),
            })
          }
        }
      }
    },
  }
}

///| 创建 ls tool — 列出目录内容。
pub fn create_ls_tool(command_runtime : CommandRuntime) -> @agent.AgentTool {
  {
    name: "ls",
    label: "List",
    description: "List files and directories. Runs `ls -la` on the given path.",
    parameters: tool_parameters(["path"]),
    prepare_arguments: None,
    validate_arguments: None,
    execute: fn(_tool_call_id, args, _on_update) {
      guard args is Object({ "path": String(path), .. }) else {
        return Err("missing path")
      }
      match (command_runtime.run)("ls -la " + shell_quote(path)) {
        Err(message) => Err(message)
        Ok(execution) => {
          let text = if execution.stdout.length() > 0 {
            execution.stdout
          } else if execution.stderr.length() > 0 {
            execution.stderr
          } else {
            "(empty directory)"
          }
          if execution.exit_code != 0 {
            Err(text)
          } else {
            Ok({
              content: [@ai.ContentBlock::Text(text)],
              details: Json::object({
                "path": Json::string(path),
              }),
            })
          }
        }
      }
    },
  }
}

fn shell_quote(s : String) -> String {
  "'" + s.replace(old="'", new="'\\''") + "'"
}

fn replace_all_occurrences(text : String, old_text : String, new_text : String) -> String {
  let mut result = text
  while result.contains(old_text) {
    let next = result.replace(old=old_text, new=new_text)
    if next == result {
      break
    }
    result = next
  }
  result
}

fn bash_tool_output_text(command : String, execution : CommandExecutionResult) -> String {
  let mut output = ""
  if execution.stdout.length() > 0 {
    output = execution.stdout
  }
  if execution.stderr.length() > 0 {
    if output.length() > 0 {
      output = output + "\n" + execution.stderr
    } else {
      output = execution.stderr
    }
  }
  if output.length() == 0 {
    output = "(no output)"
  }
  let mut text = "Ran `\{command}`\n```\n" + output + "\n```"
  if execution.cancelled {
    text = text + "\n\n(command cancelled)"
  } else if execution.exit_code != 0 {
    text = text + "\n\nCommand exited with code \{execution.exit_code}"
  }
  if execution.truncated {
    match execution.full_output_path {
      Some(path) =>
        text = text + "\n\n[Output truncated. Full output: " + path + "]"
      None => text = text + "\n\n[Output truncated]"
    }
  }
  text
}
