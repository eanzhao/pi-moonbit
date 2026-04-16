pub fn default_host_runtime() -> CliHostRuntime {
  {
    read_text: host_read_text,
    write_text: host_write_text,
    file_exists: host_file_exists,
    list_files: host_list_files,
    run_command: host_run_command,
    stdout_write: host_stdout_write,
    stderr_write: host_stderr_write,
    read_line: host_read_line,
    current_dir: current_working_directory,
    now_iso: host_now_iso,
    agent_stream: None,
  }
}

pub fn exit_process(code : Int) -> Unit {
  host_exit_process(code)
}

fn current_working_directory() -> String {
  match @env.current_dir() {
    Some(cwd) => cwd
    None => "."
  }
}
