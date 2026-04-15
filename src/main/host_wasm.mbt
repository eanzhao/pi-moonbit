fn host_read_text(_path : String) -> Result[String, String] {
  Err("host filesystem is not implemented for wasm target yet")
}

fn host_write_text(_path : String, _content : String) -> Result[Unit, String] {
  Err("host filesystem is not implemented for wasm target yet")
}

fn host_file_exists(_path : String) -> Bool {
  false
}

fn host_run_command(
  _command : String,
  _cwd : String
) -> Result[@coding_agent.CommandExecutionResult, String] {
  Err("host command execution is not implemented for wasm target yet")
}

fn host_stdout_write(text : String) -> Unit {
  write_console_line(text)
}

fn host_stderr_write(text : String) -> Unit {
  write_console_line(text)
}

fn host_read_line(_prompt : String) -> String? {
  None
}

fn host_now_iso() -> String {
  @env.now().to_string()
}

fn host_wasm_exit(code : Int) -> Unit = "__moonbit_sys_unstable" "exit"

fn host_exit_process(code : Int) -> Unit {
  host_wasm_exit(code)
}

fn write_console_line(text : String) -> Unit {
  match text.strip_suffix("\n") {
    Some(view) => println(view.to_string())
    None => println(text)
  }
}
