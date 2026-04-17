fn main {
  let runtime = default_host_runtime()
  match parse_cli_args(@env.args(), cwd=(runtime.current_dir)()) {
    Ok(CliParseResult::Help(text)) => {
      (runtime.stdout_write)(text + "\n")
    }
    Ok(CliParseResult::Run(config)) => {
      let exit_code = run_cli(config, runtime)
      if exit_code != 0 {
        exit_process(exit_code)
      }
    }
    Ok(CliParseResult::Login(config)) => {
      let exit_code = run_nyxid_login(config, runtime)
      if exit_code != 0 {
        exit_process(exit_code)
      }
    }
    Err(message) => {
      (runtime.stderr_write)(message + "\n")
      exit_process(1)
    }
  }
}
