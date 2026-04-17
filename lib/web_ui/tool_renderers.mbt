///| 工具渲染器 — 为每个工具类型生成可视化表示。
///
/// 数据模型，实际 DOM 渲染由 UI 层完成。

///| 工具渲染器注册表。
pub(all) struct ToolRendererRegistry {
  mut renderers : Array[ToolRendererEntry]
}

pub(all) struct ToolRendererEntry {
  tool_name : String
  renderer : ToolRenderer
}

///| 工具渲染器：把工具结果转成可视化片段。
pub(all) struct ToolRenderer {
  render_call : (String, Json) -> RenderedToolCall  // (tool_name, args)
  render_result : (String, Json, Bool) -> RenderedToolResult  // (tool_name, details, is_error)
}

///| 已渲染的工具调用视图数据。
pub(all) struct RenderedToolCall {
  label : String
  summary : String
  icon : String
  details : Array[(String, String)]  // key-value pairs
} derive(Show)

///| 已渲染的工具结果视图数据。
pub(all) struct RenderedToolResult {
  status : ToolResultStatus
  preview : String
  full_content : String?
  metadata : Array[(String, String)]
} derive(Show)

pub(all) enum ToolResultStatus {
  Success
  Failure
  Pending
} derive(Show, Eq)

pub fn ToolRendererRegistry::new() -> ToolRendererRegistry {
  { renderers: [] }
}

pub fn ToolRendererRegistry::register(self : ToolRendererRegistry, tool_name : String, renderer : ToolRenderer) -> Unit {
  for i = 0; i < self.renderers.length(); i = i + 1 {
    if self.renderers[i].tool_name == tool_name {
      self.renderers[i] = { tool_name, renderer }
      return
    }
  }
  self.renderers.push({ tool_name, renderer })
}

pub fn ToolRendererRegistry::get(self : ToolRendererRegistry, tool_name : String) -> ToolRenderer? {
  for entry in self.renderers {
    if entry.tool_name == tool_name { return Some(entry.renderer) }
  }
  None
}

///| 默认渲染器：把任何工具结果简单显示为 JSON。
pub fn default_tool_renderer() -> ToolRenderer {
  {
    render_call: fn(name, args) {
      { label: name, summary: args.stringify(), icon: "🔧", details: [] }
    },
    render_result: fn(_name, details, is_error) {
      let status = if is_error { Failure } else { Success }
      {
        status,
        preview: details.stringify(),
        full_content: None,
        metadata: [],
      }
    },
  }
}

///| bash 工具渲染器。
pub fn bash_tool_renderer() -> ToolRenderer {
  {
    render_call: fn(_name, args) {
      let command = match args {
        Object({ "command": String(cmd), .. }) => cmd
        _ => "(no command)"
      }
      { label: "bash", summary: command, icon: "💻", details: [] }
    },
    render_result: fn(_name, details, is_error) {
      let exit_code = match details {
        Object({ "exit_code": Number(n, ..), .. }) => n.to_int()
        _ => 0
      }
      let status = if is_error { Failure } else { Success }
      {
        status,
        preview: "exit " + exit_code.to_string(),
        full_content: None,
        metadata: [("exit_code", exit_code.to_string())],
      }
    },
  }
}

///| read 工具渲染器。
pub fn read_tool_renderer() -> ToolRenderer {
  {
    render_call: fn(_name, args) {
      let path = match args {
        Object({ "path": String(p), .. }) => p
        _ => "(unknown)"
      }
      { label: "read", summary: path, icon: "📖", details: [("path", path)] }
    },
    render_result: fn(_name, details, is_error) {
      let length = match details {
        Object({ "length": Number(n, ..), .. }) => n.to_int()
        _ => 0
      }
      {
        status: if is_error { Failure } else { Success },
        preview: length.to_string() + " chars",
        full_content: None,
        metadata: [("length", length.to_string())],
      }
    },
  }
}

///| write 工具渲染器。
pub fn write_tool_renderer() -> ToolRenderer {
  {
    render_call: fn(_name, args) {
      let path = match args {
        Object({ "path": String(p), .. }) => p
        _ => "(unknown)"
      }
      { label: "write", summary: path, icon: "✏️", details: [("path", path)] }
    },
    render_result: fn(_name, details, is_error) {
      let length = match details {
        Object({ "length": Number(n, ..), .. }) => n.to_int()
        _ => 0
      }
      {
        status: if is_error { Failure } else { Success },
        preview: "wrote " + length.to_string() + " chars",
        full_content: None,
        metadata: [("length", length.to_string())],
      }
    },
  }
}

///| edit 工具渲染器。
pub fn edit_tool_renderer() -> ToolRenderer {
  {
    render_call: fn(_name, args) {
      let path = match args {
        Object({ "path": String(p), .. }) => p
        _ => "(unknown)"
      }
      { label: "edit", summary: path, icon: "✂️", details: [("path", path)] }
    },
    render_result: fn(_name, _details, is_error) {
      {
        status: if is_error { Failure } else { Success },
        preview: if is_error { "edit failed" } else { "edited" },
        full_content: None,
        metadata: [],
      }
    },
  }
}

///| 注册所有内置工具渲染器。
pub fn register_builtin_tool_renderers(registry : ToolRendererRegistry) -> Unit {
  registry.register("bash", bash_tool_renderer())
  registry.register("read", read_tool_renderer())
  registry.register("write", write_tool_renderer())
  registry.register("edit", edit_tool_renderer())
}
