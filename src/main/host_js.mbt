extern "js" fn host_read_text_ffi(path : String) -> Array[String] =
  #| function(path) {
  #|   const fs = require("node:fs");
  #|   try {
  #|     return ["ok", fs.readFileSync(path, "utf8")];
  #|   } catch (error) {
  #|     return ["err", error && error.message ? String(error.message) : String(error)];
  #|   }
  #| }

fn host_read_text(path : String) -> Result[String, String] {
  let result = host_read_text_ffi(path)
  if result.length() >= 2 && result[0] == "ok" {
    Ok(result[1])
  } else if result.length() >= 2 {
    Err(result[1])
  } else {
    Err("failed to read file")
  }
}

extern "js" fn host_write_text_ffi(path : String, content : String) -> Array[String] =
  #| function(path, content) {
  #|   const fs = require("node:fs");
  #|   const nodePath = require("node:path");
  #|   try {
  #|     fs.mkdirSync(nodePath.dirname(path), { recursive: true });
  #|     fs.writeFileSync(path, content, "utf8");
  #|     return ["ok", ""];
  #|   } catch (error) {
  #|     return ["err", error && error.message ? String(error.message) : String(error)];
  #|   }
  #| }

fn host_write_text(path : String, content : String) -> Result[Unit, String] {
  let result = host_write_text_ffi(path, content)
  if result.length() >= 1 && result[0] == "ok" {
    Ok(())
  } else if result.length() >= 2 {
    Err(result[1])
  } else {
    Err("failed to write file")
  }
}

extern "js" fn host_file_exists(path : String) -> Bool =
  #| function(path) {
  #|   const fs = require("node:fs");
  #|   return fs.existsSync(path);
  #| }

extern "js" fn host_run_command_ffi(command : String, cwd : String) -> Array[String] =
  #| function(command, cwd) {
  #|   const childProcess = require("node:child_process");
  #|   try {
  #|     const result = childProcess.spawnSync("/bin/zsh", ["-lc", command], {
  #|       cwd,
  #|       encoding: "utf8",
  #|       maxBuffer: 10 * 1024 * 1024,
  #|     });
  #|     const status = result.status == null ? -1 : result.status;
  #|     const cancelled = result.signal != null ? "true" : "false";
  #|     return [
  #|       "ok",
  #|       result.stdout || "",
  #|       result.stderr || "",
  #|       String(status),
  #|       cancelled,
  #|       "false",
  #|       "",
  #|     ];
  #|   } catch (error) {
  #|     return ["err", error && error.message ? String(error.message) : String(error)];
  #|   }
  #| }

fn host_run_command(
  command : String,
  cwd : String
) -> Result[@coding_agent.CommandExecutionResult, String] {
  let result = host_run_command_ffi(command, cwd)
  if result.length() >= 2 && result[0] == "err" {
    return Err(result[1])
  }
  let exit_code = parse_int_string(result.get(3).unwrap_or("-1"))
  Ok({
    stdout: result.get(1).unwrap_or(""),
    stderr: result.get(2).unwrap_or(""),
    exit_code,
    cancelled: result.get(4).unwrap_or("false") == "true",
    truncated: result.get(5).unwrap_or("false") == "true",
    full_output_path: match result.get(6) {
      Some(path) if path.length() > 0 => Some(path)
      _ => None
    },
  })
}

extern "js" fn host_stdout_write(text : String) -> Unit =
  #| function(text) {
  #|   if (typeof process !== "undefined" && process.stdout) {
  #|     process.stdout.write(text);
  #|   }
  #| }

extern "js" fn host_stderr_write(text : String) -> Unit =
  #| function(text) {
  #|   if (typeof process !== "undefined" && process.stderr) {
  #|     process.stderr.write(text);
  #|   }
  #| }

extern "js" fn host_read_line(prompt : String) -> String? =
  #| function(prompt) {
  #|   const fs = require("node:fs");
  #|   const key = "__pi_moonbit_line_buffer";
  #|   if (typeof globalThis[key] !== "string") {
  #|     globalThis[key] = "";
  #|   }
  #|   if (prompt.length > 0 && typeof process !== "undefined" && process.stdout) {
  #|     process.stdout.write(prompt);
  #|   }
  #|   const buf = Buffer.alloc(1024);
  #|   while (true) {
  #|     const cached = globalThis[key];
  #|     const newlineIndex = cached.indexOf("\n");
  #|     if (newlineIndex !== -1) {
  #|       const line = cached.slice(0, newlineIndex).replace(/\r$/, "");
  #|       globalThis[key] = cached.slice(newlineIndex + 1);
  #|       return line;
  #|     }
  #|     const read = fs.readSync(0, buf, 0, buf.length, null);
  #|     if (read === 0) {
  #|       if (globalThis[key].length === 0) {
  #|         return null;
  #|       }
  #|       const line = globalThis[key].replace(/\r$/, "");
  #|       globalThis[key] = "";
  #|       return line;
  #|     }
  #|     globalThis[key] += buf.toString("utf8", 0, read);
  #|   }
  #| }

extern "js" fn host_now_iso() -> String =
  #| function() {
  #|   return new Date().toISOString();
  #| }

extern "js" fn host_exit_process(code : Int) -> Unit =
  #| function(code) {
  #|   if (typeof process !== "undefined" && typeof process.exit === "function") {
  #|     process.exit(code);
  #|   }
  #| }

fn parse_int_string(text : String) -> Int {
  let parsed : Result[Int, Error] = try? @string.parse_int(text)
  match parsed {
    Ok(value) => value
    Err(_) => -1
  }
}
