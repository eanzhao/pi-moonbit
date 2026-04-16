fn host_read_text(_path : String) -> Result[String, String] {
  Err("host filesystem is not implemented for native target yet")
}

fn host_write_text(_path : String, _content : String) -> Result[Unit, String] {
  Err("host filesystem is not implemented for native target yet")
}

fn host_file_exists(_path : String) -> Bool {
  false
}

fn host_list_files(_dir : String) -> Result[Array[String], String] {
  Err("host list_files is not implemented for native target yet")
}

fn host_run_command(
  _command : String,
  _cwd : String
) -> Result[@coding_agent.CommandExecutionResult, String] {
  Err("host command execution is not implemented for native target yet")
}

fn host_stdout_write(text : String) -> Unit {
  println(text)
}

fn host_stderr_write(text : String) -> Unit {
  println(text)
}

fn host_read_line(_prompt : String) -> String? {
  None
}

fn host_now_iso() -> String {
  @env.now().to_string()
}

fn host_env_var(name : String) -> String? {
  @env.get_env_var(name)
}

extern "c" fn host_native_exit_ffi(code : Int) = "exit"

fn host_exit_process(code : Int) -> Unit {
  host_native_exit_ffi(code)
}
