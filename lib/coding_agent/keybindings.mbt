pub(all) struct KeyBinding {
  key : String
  description : String
  command : String
}

pub fn default_keybindings() -> Array[KeyBinding] {
  [
    { key: "Ctrl+C", description: "Abort current operation", command: "abort" },
    { key: "Ctrl+D", description: "Quit", command: "quit" },
    { key: "Ctrl+L", description: "Clear screen", command: "clear" },
    { key: "Tab", description: "Autocomplete", command: "autocomplete" },
    { key: "Up", description: "Previous history", command: "history_prev" },
    { key: "Down", description: "Next history", command: "history_next" },
  ]
}

pub fn format_keybindings_help(bindings : Array[KeyBinding]) -> String {
  let lines : Array[String] = ["Key Bindings:"]
  for b in bindings {
    lines.push("  " + b.key + " — " + b.description)
  }
  lines.join("\n")
}
