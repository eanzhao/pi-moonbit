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
      // Route by client_id: empty → simplified CLI flow; non-empty → standard OAuth 2.0 + PKCE.
      let exit_code = if config.client_id.length() > 0 {
        run_nyxid_oauth_login(config, runtime)
      } else {
        run_nyxid_login(config, runtime)
      }
      if exit_code != 0 {
        exit_process(exit_code)
      }
    }
    Ok(CliParseResult::Models(config)) => {
      let exit_code = run_models_command(config, runtime)
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
