///| 包入口：供 `src/main/main.mbt` 的 main 函数调用。
///
/// 把原本散在 main.mbt 里的 dispatch 逻辑搬进来，这样 `src/main/` 包里
/// 只剩一个 `fn main`（符合 MoonBit 对 main 包"只放入口"的要求，避免
/// blackbox test 文件触发的结构性 warning）。
pub fn run_main(argv : Array[String]) -> Unit {
  let runtime = default_host_runtime()
  match parse_cli_args(argv, cwd=(runtime.current_dir)()) {
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
    Ok(CliParseResult::Providers(config)) => {
      let exit_code = run_providers_command(config, runtime)
      if exit_code != 0 {
        exit_process(exit_code)
      }
    }
    Ok(CliParseResult::Setup(config)) => {
      let exit_code = run_setup_command(config, runtime)
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
