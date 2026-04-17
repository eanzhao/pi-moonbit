///| `pimbt models` 命令的实现。
///
/// 调 NyxID 的 `GET /api/v1/llm/status` 端点，列出：
///   - providers: 用户已连接的 provider 及其状态 (ready/expired/not_connected)
///   - supported_models: 网关支持的 model id（用于传给 `--model`）
///
/// 认证用 Bearer（从 ~/.pimbt/nyxid-credentials.json 的 access_token 读取，
/// 或 `--bearer` 手动指定）。

pub fn run_models_command(config : ModelsConfig, runtime : CliHostRuntime) -> Int {
  let write_out = runtime.stdout_write
  let write_err = runtime.stderr_write

  // Resolve Bearer token
  let (base_url, bearer) = match config.bearer_override {
    Some(tok) if tok.length() > 0 => (config.base_url, tok)
    _ => {
      match (runtime.read_text)(config.credentials_path) {
        Ok(text) => {
          let json = try { @json.parse(text) } catch {
            _ => {
              write_err(@tui.ansi_error("credentials file is not valid JSON: " + config.credentials_path) + "\n")
              return 2
            }
          }
          match @ai.parse_nyxid_stored_credentials(json) {
            Ok(stored) => (stored.base_url, stored.credentials.access_token)
            Err(msg) => {
              write_err(@tui.ansi_error("credentials file invalid: " + msg) + "\n")
              return 2
            }
          }
        }
        Err(_) => {
          write_err(@tui.ansi_error(
            "no NyxID credentials found at " + config.credentials_path +
            ".\nRun `pimbt login --client-id <your-client-id>` first.",
          ) + "\n")
          return 2
        }
      }
    }
  }

  let status_url = if base_url.has_suffix("/") {
    base_url + "api/v1/llm/status"
  } else {
    base_url + "/api/v1/llm/status"
  }

  match host_get_bearer(status_url, bearer) {
    Err(msg) => {
      write_err(@tui.ansi_error("request failed: " + msg) + "\n")
      1
    }
    Ok((status, body)) => {
      if status == 401 {
        write_err(@tui.ansi_error(
          "NyxID rejected the token (401). Run `pimbt login` to re-authenticate.",
        ) + "\n")
        return 3
      }
      if status >= 400 {
        write_err(@tui.ansi_error(
          "HTTP " + status.to_string() + " from NyxID:\n" + body,
        ) + "\n")
        return 1
      }
      let json = try { @json.parse(body) } catch {
        _ => {
          write_err(@tui.ansi_error("response is not valid JSON:\n" + body) + "\n")
          return 1
        }
      }
      write_out(format_llm_status(json))
      0
    }
  }
}

///| 把 /api/v1/llm/status 的 JSON 格式化成人类可读输出。
///
/// 预期 shape（LlmStatusResponse）：
/// ```json
/// {
///   "providers": [{ "name": "openai", "status": "ready", ... }, ...],
///   "gateway_url": "...",
///   "supported_models": ["gpt-4o", "claude-sonnet-4-5", ...]
/// }
/// ```
pub fn format_llm_status(json : Json) -> String {
  let sb = StringBuilder::new()

  // Providers
  sb.write_string(@tui.ansi_section_header("Connected Providers") + "\n")
  match json {
    Object({ "providers": Array(providers), .. }) => {
      if providers.length() == 0 {
        sb.write_string("  " + @tui.ansi_info("(none — add providers in the NyxID web panel)") + "\n")
      } else {
        for p in providers {
          sb.write_string("  " + format_provider(p) + "\n")
        }
      }
    }
    _ => sb.write_string("  " + @tui.ansi_info("(providers field missing in response)") + "\n")
  }
  sb.write_string("\n")

  // Supported models
  sb.write_string(@tui.ansi_section_header("Supported Models") + "\n")
  match json {
    Object({ "supported_models": Array(models), .. }) => {
      if models.length() == 0 {
        sb.write_string("  " + @tui.ansi_info("(none)") + "\n")
      } else {
        for m in models {
          match m {
            String(id) => sb.write_string("  " + id + "\n")
            _ => ()
          }
        }
      }
    }
    _ => sb.write_string("  " + @tui.ansi_info("(supported_models field missing)") + "\n")
  }

  // Usage hint
  sb.write_string("\n")
  sb.write_string(@tui.ansi_info(
    "Use with: pimbt --api nyxid-gateway --model <id> \"...\"",
  ) + "\n")

  sb.to_string()
}

fn format_provider(p : Json) -> String {
  match p {
    Object(fields) => {
      let name = match fields.get("name") {
        Some(String(s)) => s
        _ => "(unknown)"
      }
      let status = match fields.get("status") {
        Some(String(s)) => s
        _ => "?"
      }
      let (icon, colored_status) = match status {
        "ready" => ("✓", @tui.ansi_green() + status + @tui.ansi_reset())
        "expired" => ("⚠", @tui.ansi_yellow() + status + @tui.ansi_reset())
        "not_connected" => ("—", @tui.ansi_dim() + status + @tui.ansi_reset())
        _ => ("·", status)
      }
      icon + " " + name + " " + @tui.ansi_dim() + "(" + @tui.ansi_reset() + colored_status + @tui.ansi_dim() + ")" + @tui.ansi_reset()
    }
    _ => "(malformed provider entry)"
  }
}
