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

extern "js" fn host_list_files_ffi(path : String) -> Array[String] =
  #| function(path) {
  #|   const fs = require("node:fs");
  #|   const nodePath = require("node:path");
  #|   try {
  #|     if (!fs.existsSync(path)) {
  #|       return ["ok"];
  #|     }
  #|     const stat = fs.statSync(path);
  #|     if (!stat.isDirectory()) {
  #|       return ["err", "not a directory: " + path];
  #|     }
  #|     const entries = fs.readdirSync(path, { withFileTypes: true })
  #|       .filter((entry) => entry.isFile())
  #|       .map((entry) => nodePath.join(path, entry.name));
  #|     return ["ok", ...entries];
  #|   } catch (error) {
  #|     return ["err", error && error.message ? String(error.message) : String(error)];
  #|   }
  #| }

fn host_list_files(path : String) -> Result[Array[String], String] {
  let result = host_list_files_ffi(path)
  if result.length() >= 2 && result[0] == "err" {
    return Err(result[1])
  }
  let files : Array[String] = []
  for i in 1..<result.length() {
    files.push(result[i])
  }
  Ok(files)
}

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
  #|   const readBlocking = () => {
  #|     while (true) {
  #|       try {
  #|         return fs.readSync(0, buf, 0, buf.length, null);
  #|       } catch (e) {
  #|         if (e && (e.code === "EAGAIN" || e.code === "EWOULDBLOCK")) {
  #|           const tmp = new Int32Array(new SharedArrayBuffer(4));
  #|           Atomics.wait(tmp, 0, 0, 20);
  #|           continue;
  #|         }
  #|         throw e;
  #|       }
  #|     }
  #|   };
  #|   while (true) {
  #|     const cached = globalThis[key];
  #|     const newlineIndex = cached.indexOf("\n");
  #|     if (newlineIndex !== -1) {
  #|       const line = cached.slice(0, newlineIndex).replace(/\r$/, "");
  #|       globalThis[key] = cached.slice(newlineIndex + 1);
  #|       return line;
  #|     }
  #|     const read = readBlocking();
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

///| 交互式单选（方向键导航 + Enter 确认）。返回选中的索引；取消或非法输入返回 -1。
///
/// 如果 stdin/stdout 是 TTY：raw mode + ANSI 高亮 + 原地重绘。
/// 否则：退化到「编号列表 + 输入数字」的同步 prompt（兼容管道/CI）。
extern "js" fn host_select_from_list_ffi(
  title : String,
  items : Array[String],
  initial : Int
) -> Int =
  #| function(title, items, initial) {
  #|   const fs = require("node:fs");
  #|   const stdout = process.stdout;
  #|   const stdin = process.stdin;
  #|   const n = items.length;
  #|   if (n === 0) return -1;
  #|   const start = Math.max(0, Math.min(initial | 0, n - 1));
  #|
  #|   const isTty = stdout && stdout.isTTY && stdin && stdin.isTTY &&
  #|     typeof stdin.setRawMode === "function";
  #|
  #|   // Node puts TTY stdin into non-blocking mode once a readable stream (or
  #|   // setRawMode) touches it, so fs.readSync can throw EAGAIN. Wrap reads
  #|   // in a retry loop with a short Atomics.wait to avoid a busy spin.
  #|   const readBlocking = (fd, buf) => {
  #|     while (true) {
  #|       try {
  #|         return fs.readSync(fd, buf, 0, buf.length, null);
  #|       } catch (e) {
  #|         if (e && (e.code === "EAGAIN" || e.code === "EWOULDBLOCK")) {
  #|           const tmp = new Int32Array(new SharedArrayBuffer(4));
  #|           Atomics.wait(tmp, 0, 0, 20);
  #|           continue;
  #|         }
  #|         throw e;
  #|       }
  #|     }
  #|   };
  #|
  #|   if (!isTty) {
  #|     // Non-TTY fallback: numbered prompt. Shares the line buffer with
  #|     // host_read_line so leftover bytes from stacked prompts are preserved.
  #|     const bufKey = "__pi_moonbit_line_buffer";
  #|     if (typeof globalThis[bufKey] !== "string") globalThis[bufKey] = "";
  #|     if (title) stdout.write(title + "\n");
  #|     for (let i = 0; i < n; i++) {
  #|       stdout.write("  " + (i + 1) + ". " + items[i] + "\n");
  #|     }
  #|     stdout.write("Choice [1-" + n + "]: ");
  #|     const buf = Buffer.alloc(1024);
  #|     let line = null;
  #|     while (line === null) {
  #|       const cached = globalThis[bufKey];
  #|       const nlIdx = cached.indexOf("\n");
  #|       if (nlIdx !== -1) {
  #|         line = cached.slice(0, nlIdx).replace(/\r$/, "");
  #|         globalThis[bufKey] = cached.slice(nlIdx + 1);
  #|         break;
  #|       }
  #|       const r = readBlocking(0, buf);
  #|       if (r <= 0) {
  #|         if (globalThis[bufKey].length === 0) return -1;
  #|         line = globalThis[bufKey].replace(/\r$/, "");
  #|         globalThis[bufKey] = "";
  #|         break;
  #|       }
  #|       globalThis[bufKey] += buf.toString("utf8", 0, r);
  #|     }
  #|     const trimmed = line.trim();
  #|     if (!trimmed) return -1;
  #|     const parsed = parseInt(trimmed, 10);
  #|     if (isNaN(parsed) || parsed < 1 || parsed > n) return -1;
  #|     return parsed - 1;
  #|   }
  #|
  #|   // Raw-mode TTY picker.
  #|   const viewport = Math.max(1, Math.min(n, 12));
  #|   let cursor = start;
  #|   let top = 0;
  #|   if (cursor >= viewport) top = cursor - viewport + 1;
  #|
  #|   const render = (firstFrame) => {
  #|     if (!firstFrame) {
  #|       // Move up over: title (1) + viewport rows + hint (1)
  #|       stdout.write("\x1b[" + (viewport + 2) + "A");
  #|     }
  #|     stdout.write("\x1b[2K" + (title || "") + "\n");
  #|     for (let i = 0; i < viewport; i++) {
  #|       const idx = top + i;
  #|       stdout.write("\x1b[2K");
  #|       if (idx >= n) { stdout.write("\n"); continue; }
  #|       const label = items[idx];
  #|       if (idx === cursor) {
  #|         stdout.write("\x1b[36m\u276f\x1b[0m \x1b[7m " + label + " \x1b[0m");
  #|       } else {
  #|         stdout.write("  " + label);
  #|       }
  #|       stdout.write("\n");
  #|     }
  #|     const shown = Math.min(top + viewport, n);
  #|     const hint = "\x1b[2m(\u2191/\u2193 move \u00b7 Enter select \u00b7 Esc/q cancel \u00b7 " +
  #|       (cursor + 1) + "/" + n + (shown < n ? ", scroll for more" : "") + ")\x1b[0m";
  #|     stdout.write("\x1b[2K" + hint + "\n");
  #|   };
  #|
  #|   const wasRaw = stdin.isRaw === true;
  #|   let selected = -1;
  #|   try {
  #|     stdin.setRawMode(true);
  #|     render(true);
  #|     const buf = Buffer.alloc(16);
  #|     let running = true;
  #|     while (running) {
  #|       const r = readBlocking(0, buf);
  #|       if (r <= 0) break;
  #|       const data = buf.toString("utf8", 0, r);
  #|       // Ctrl+C
  #|       if (data === "\x03") { selected = -1; break; }
  #|       // Enter
  #|       if (data === "\r" || data === "\n" || data === "\r\n") { selected = cursor; break; }
  #|       // Arrow keys
  #|       if (data === "\x1b[A" || data === "\x1bOA") {
  #|         if (cursor > 0) cursor--;
  #|         if (cursor < top) top = cursor;
  #|         render(false); continue;
  #|       }
  #|       if (data === "\x1b[B" || data === "\x1bOB") {
  #|         if (cursor < n - 1) cursor++;
  #|         if (cursor >= top + viewport) top = cursor - viewport + 1;
  #|         render(false); continue;
  #|       }
  #|       // Page Up/Down
  #|       if (data === "\x1b[5~") {
  #|         cursor = Math.max(0, cursor - viewport);
  #|         top = Math.max(0, Math.min(top, cursor));
  #|         render(false); continue;
  #|       }
  #|       if (data === "\x1b[6~") {
  #|         cursor = Math.min(n - 1, cursor + viewport);
  #|         if (cursor >= top + viewport) top = cursor - viewport + 1;
  #|         render(false); continue;
  #|       }
  #|       // Home / End
  #|       if (data === "\x1b[H" || data === "\x1b[1~") {
  #|         cursor = 0; top = 0; render(false); continue;
  #|       }
  #|       if (data === "\x1b[F" || data === "\x1b[4~") {
  #|         cursor = n - 1; top = Math.max(0, n - viewport); render(false); continue;
  #|       }
  #|       // Esc alone
  #|       if (data === "\x1b") { selected = -1; break; }
  #|       // q/Q to cancel
  #|       if (data === "q" || data === "Q") { selected = -1; break; }
  #|       // Digit shortcut 1-9
  #|       if (data.length === 1 && data >= "1" && data <= "9") {
  #|         const d = parseInt(data, 10) - 1;
  #|         if (d < n) { selected = d; break; }
  #|       }
  #|     }
  #|   } finally {
  #|     try { stdin.setRawMode(wasRaw); } catch {}
  #|   }
  #|   stdout.write("\n");
  #|   return selected;
  #| }

fn host_select_from_list(title : String, items : Array[String], initial : Int) -> Int {
  host_select_from_list_ffi(title, items, initial)
}

fn parse_int_string(text : String) -> Int {
  let parsed : Result[Int, Error] = try? @string.parse_int(text)
  match parsed {
    Ok(value) => value
    Err(_) => -1
  }
}
