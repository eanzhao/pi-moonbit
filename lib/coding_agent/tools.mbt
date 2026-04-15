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

///| 创建 edit tool。
pub fn create_edit_tool(runtime : WorkspaceRuntime) -> @agent.AgentTool {
  {
    name: "edit",
    label: "Edit",
    description: "Replace the first matching text chunk in a file",
    parameters: tool_parameters(["path", "old_text", "new_text"]),
    prepare_arguments: None,
    validate_arguments: Some(validate_edit_arguments),
    execute: fn(_tool_call_id, args, _on_update) {
      match edit_arguments(args) {
        Err(message) => Err(message)
        Ok((path, old_text, new_text)) =>
          match (runtime.read_text)(path) {
            Err(message) => Err(message)
            Ok(content) => {
              if !content.contains(old_text) {
                return Err("Text to replace was not found in \{path}")
              }
              let next_content = content.replace(old=old_text, new=new_text)
              match (runtime.write_text)(path, next_content) {
                Err(message) => Err(message)
                Ok(_) =>
                  Ok({
                    content: [@ai.ContentBlock::Text("Updated \{path}.")],
                    details: Json::object({
                      "path": Json::string(path),
                      "old_length": Json::number(old_text.length().to_double()),
                      "new_length": Json::number(new_text.length().to_double()),
                    }),
                  })
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
