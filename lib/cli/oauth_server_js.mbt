///| 本地 HTTP 回调服务器 + OAuth token 请求（JS target）。
///
/// 使用 execSync + 临时 Node 脚本的 trick 在同步上下文中执行异步 I/O。
/// 返回值约定：["ok", ...] 或 ["err", message]。

///| 等待 NyxID CLI 流程的 callback：直接接收 access_token（无需 code 换 token）。
/// 返回 ["ok", access_token, refresh_token_or_empty, state] 或 ["err", msg] 或 ["timeout"]。
extern "js" fn host_wait_cli_callback_ffi(
  port : Int,
  expected_state : String,
  timeout_ms : Int
) -> Array[String] =
  #|(port, expectedState, timeoutMs) => {
  #|  try {
  #|    const { execSync } = require("child_process");
  #|    const fs = require("fs");
  #|    const os = require("os");
  #|    const tmp = os.tmpdir() + "/pimbt-cli-cb-" + Date.now() + "-" + process.pid + ".js";
  #|    fs.writeFileSync(tmp, `
  #|      const http = require("http");
  #|      const url = require("url");
  #|      const port = ${port};
  #|      const expectedState = ${JSON.stringify(expectedState)};
  #|      const timeoutMs = ${timeoutMs};
  #|      let finished = false;
  #|      const server = http.createServer((req, res) => {
  #|        // CORS for browser-side fetch from frontend to localhost
  #|        res.setHeader("Access-Control-Allow-Origin", "*");
  #|        res.setHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  #|        res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  #|        if (req.method === "OPTIONS") { res.writeHead(204); res.end(); return; }
  #|        const parsed = url.parse(req.url, true);
  #|        if (parsed.pathname === "/callback") {
  #|          const accessToken = parsed.query.access_token;
  #|          const refreshToken = parsed.query.refresh_token || "";
  #|          const state = parsed.query.state;
  #|          const error = parsed.query.error;
  #|          const errorDesc = parsed.query.error_description;
  #|          res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  #|          if (error) {
  #|            res.end("<!DOCTYPE html><html><head><title>Login failed</title><style>body{font-family:system-ui;text-align:center;padding:40px;color:#333}</style></head><body><h1>Login failed</h1><p>" + (errorDesc || error) + "</p></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", errorDesc || error])); server.close(); }
  #|          } else if (!accessToken) {
  #|            res.end("<!DOCTYPE html><html><body><h1>Missing access_token</h1></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", "callback missing access_token"])); server.close(); }
  #|          } else if (state !== expectedState) {
  #|            res.end("<!DOCTYPE html><html><body><h1>State mismatch</h1></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", "state mismatch"])); server.close(); }
  #|          } else {
  #|            res.end("<!DOCTYPE html><html><head><title>Login successful</title><style>body{font-family:system-ui;text-align:center;padding:40px;color:#333}</style></head><body><h1>Login successful</h1><p>You may close this window and return to the terminal.</p></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["ok", accessToken, refreshToken, state])); server.close(); }
  #|          }
  #|        } else {
  #|          res.writeHead(404);
  #|          res.end();
  #|        }
  #|      });
  #|      server.on("error", (e) => {
  #|        if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", e.message])); }
  #|      });
  #|      server.listen(port, "127.0.0.1");
  #|      setTimeout(() => {
  #|        if (!finished) { finished = true; process.stdout.write(JSON.stringify(["timeout"])); server.close(); }
  #|      }, timeoutMs);
  #|    `);
  #|    const out = execSync("node " + JSON.stringify(tmp), {
  #|      maxBuffer: 10 * 1024 * 1024,
  #|      timeout: timeoutMs + 5000,
  #|    });
  #|    try { fs.unlinkSync(tmp); } catch {}
  #|    return JSON.parse(out.toString());
  #|  } catch (e) {
  #|    return ["err", e.message || String(e)];
  #|  }
  #|}

///| 等待 NyxID CLI callback。
///
/// 返回 Ok((access_token, refresh_token_option, state))。
fn host_wait_cli_callback(
  port : Int,
  expected_state : String,
  timeout_ms : Int
) -> Result[(String, String?, String), String] {
  let result = host_wait_cli_callback_ffi(port, expected_state, timeout_ms)
  if result.length() == 0 {
    return Err("empty callback response")
  }
  match result[0] {
    "ok" => {
      if result.length() < 4 { return Err("malformed callback response") }
      let access_token = result[1]
      let refresh_token = if result[2].length() > 0 { Some(result[2]) } else { None }
      let state = result[3]
      Ok((access_token, refresh_token, state))
    }
    "timeout" => Err("OAuth callback timed out")
    _ => Err(if result.length() > 1 { result[1] } else { "unknown error" })
  }
}

///| 等待 OAuth redirect 回调。
/// 返回 ["ok", code, state] 或 ["err", message] 或 ["timeout"]。
extern "js" fn host_wait_oauth_callback_ffi(
  port : Int,
  expected_state : String,
  timeout_ms : Int
) -> Array[String] =
  #|(port, expectedState, timeoutMs) => {
  #|  try {
  #|    const { execSync } = require("child_process");
  #|    const fs = require("fs");
  #|    const os = require("os");
  #|    const tmp = os.tmpdir() + "/pimbt-oauth-cb-" + Date.now() + "-" + process.pid + ".js";
  #|    fs.writeFileSync(tmp, `
  #|      const http = require("http");
  #|      const url = require("url");
  #|      const port = ${port};
  #|      const expectedState = ${JSON.stringify(expectedState)};
  #|      const timeoutMs = ${timeoutMs};
  #|      let finished = false;
  #|      const server = http.createServer((req, res) => {
  #|        const parsed = url.parse(req.url, true);
  #|        if (parsed.pathname === "/callback") {
  #|          const code = parsed.query.code;
  #|          const state = parsed.query.state;
  #|          const error = parsed.query.error;
  #|          const errorDesc = parsed.query.error_description;
  #|          res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
  #|          if (error) {
  #|            res.end("<!DOCTYPE html><html><head><title>Login failed</title><style>body{font-family:system-ui;text-align:center;padding:40px;color:#333}</style></head><body><h1>❌ Login failed</h1><p>" + (errorDesc || error) + "</p><p>You may close this window.</p></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", errorDesc || error])); server.close(); }
  #|          } else if (!code) {
  #|            res.end("<!DOCTYPE html><html><body><h1>❌ Missing code</h1></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", "callback missing code"])); server.close(); }
  #|          } else if (state !== expectedState) {
  #|            res.end("<!DOCTYPE html><html><body><h1>❌ State mismatch</h1><p>Possible CSRF attack. Aborting.</p></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", "state mismatch"])); server.close(); }
  #|          } else {
  #|            res.end("<!DOCTYPE html><html><head><title>Login successful</title><style>body{font-family:system-ui;text-align:center;padding:40px;color:#333}</style></head><body><h1>✅ Login successful</h1><p>You may close this window and return to the terminal.</p></body></html>");
  #|            if (!finished) { finished = true; process.stdout.write(JSON.stringify(["ok", code, state])); server.close(); }
  #|          }
  #|        } else {
  #|          res.writeHead(404);
  #|          res.end();
  #|        }
  #|      });
  #|      server.on("error", (e) => {
  #|        if (!finished) { finished = true; process.stdout.write(JSON.stringify(["err", e.message])); }
  #|      });
  #|      server.listen(port, "localhost");
  #|      setTimeout(() => {
  #|        if (!finished) { finished = true; process.stdout.write(JSON.stringify(["timeout"])); server.close(); }
  #|      }, timeoutMs);
  #|    `);
  #|    const out = execSync("node " + JSON.stringify(tmp), {
  #|      maxBuffer: 10 * 1024 * 1024,
  #|      timeout: timeoutMs + 5000,
  #|    });
  #|    try { fs.unlinkSync(tmp); } catch {}
  #|    return JSON.parse(out.toString());
  #|  } catch (e) {
  #|    return ["err", e.message || String(e)];
  #|  }
  #|}

///| POST form-encoded 到 token endpoint，返回 JSON 响应文本。
extern "js" fn host_post_form_ffi(url : String, form_body : String) -> Array[String] =
  #|(url, formBody) => {
  #|  try {
  #|    const { execSync } = require("child_process");
  #|    const fs = require("fs");
  #|    const os = require("os");
  #|    const tmp = os.tmpdir() + "/pimbt-oauth-token-" + Date.now() + "-" + process.pid + ".js";
  #|    fs.writeFileSync(tmp, `
  #|      const http = require("http");
  #|      const https = require("https");
  #|      const { URL } = require("url");
  #|      const parsed = new URL(${JSON.stringify(url)});
  #|      const lib = parsed.protocol === "https:" ? https : http;
  #|      const body = ${JSON.stringify(formBody)};
  #|      const req = lib.request(parsed, {
  #|        method: "POST",
  #|        headers: {
  #|          "Content-Type": "application/x-www-form-urlencoded",
  #|          "Accept": "application/json",
  #|          "Content-Length": Buffer.byteLength(body).toString(),
  #|        },
  #|        timeout: 30000,
  #|      }, (res) => {
  #|        let data = "";
  #|        res.on("data", (chunk) => { data += chunk; });
  #|        res.on("end", () => {
  #|          process.stdout.write(JSON.stringify(["ok", res.statusCode, data]));
  #|        });
  #|        res.on("error", (e) => {
  #|          process.stdout.write(JSON.stringify(["err", e.message]));
  #|        });
  #|      });
  #|      req.on("error", (e) => {
  #|        process.stdout.write(JSON.stringify(["err", e.message]));
  #|      });
  #|      req.write(body);
  #|      req.end();
  #|    `);
  #|    const out = execSync("node " + JSON.stringify(tmp), {
  #|      maxBuffer: 10 * 1024 * 1024,
  #|      timeout: 35000,
  #|    });
  #|    try { fs.unlinkSync(tmp); } catch {}
  #|    return JSON.parse(out.toString());
  #|  } catch (e) {
  #|    return ["err", e.message || String(e)];
  #|  }
  #|}

///| 打开用户默认浏览器到指定 URL。
extern "js" fn host_open_browser_ffi(url : String) -> Unit =
  #|(url) => {
  #|  const { spawn } = require("child_process");
  #|  const platform = process.platform;
  #|  let cmd, args;
  #|  if (platform === "darwin") { cmd = "open"; args = [url]; }
  #|  else if (platform === "win32") { cmd = "cmd"; args = ["/c", "start", "", url]; }
  #|  else { cmd = "xdg-open"; args = [url]; }
  #|  try { spawn(cmd, args, { detached: true, stdio: "ignore" }).unref(); } catch {}
  #|}

///| 等待 OAuth 回调。返回 Ok((code, state)) 或 Err(message)。
fn host_wait_oauth_callback(
  port : Int,
  expected_state : String,
  timeout_ms : Int
) -> Result[(String, String), String] {
  let result = host_wait_oauth_callback_ffi(port, expected_state, timeout_ms)
  if result.length() == 0 {
    return Err("empty callback response")
  }
  match result[0] {
    "ok" => {
      if result.length() < 3 { Err("malformed callback response") }
      else { Ok((result[1], result[2])) }
    }
    "timeout" => Err("OAuth callback timed out")
    _ => Err(if result.length() > 1 { result[1] } else { "unknown error" })
  }
}

///| POST form 到 token endpoint。返回 (status_code, body) 或 Err。
fn host_post_form(url : String, form_body : String) -> Result[(Int, String), String] {
  let result = host_post_form_ffi(url, form_body)
  if result.length() == 0 {
    return Err("empty token response")
  }
  if result[0] == "err" {
    return Err(if result.length() > 1 { result[1] } else { "unknown error" })
  }
  if result.length() < 3 {
    return Err("malformed token response")
  }
  let status = try @string.parse_int(result[1]) catch {
    _ => 0
  } noraise {
    n => n
  }
  Ok((status, result[2]))
}

///| GET 请求（Bearer 认证），返回 (status_code, body) 或 Err。
extern "js" fn host_get_bearer_ffi(url : String, bearer : String) -> Array[String] =
  #|(url, bearer) => {
  #|  try {
  #|    const { execSync } = require("child_process");
  #|    const fs = require("fs");
  #|    const os = require("os");
  #|    const tmp = os.tmpdir() + "/pimbt-get-" + Date.now() + "-" + process.pid + ".js";
  #|    fs.writeFileSync(tmp, `
  #|      const http = require("http");
  #|      const https = require("https");
  #|      const { URL } = require("url");
  #|      const parsed = new URL(${JSON.stringify(url)});
  #|      const lib = parsed.protocol === "https:" ? https : http;
  #|      const headers = { "Accept": "application/json" };
  #|      const bearer = ${JSON.stringify(bearer)};
  #|      if (bearer) headers["Authorization"] = "Bearer " + bearer;
  #|      const req = lib.request(parsed, {
  #|        method: "GET",
  #|        headers,
  #|        timeout: 30000,
  #|      }, (res) => {
  #|        let data = "";
  #|        res.on("data", (c) => { data += c; });
  #|        res.on("end", () => {
  #|          process.stdout.write(JSON.stringify(["ok", res.statusCode, data]));
  #|        });
  #|        res.on("error", (e) => {
  #|          process.stdout.write(JSON.stringify(["err", e.message]));
  #|        });
  #|      });
  #|      req.on("error", (e) => {
  #|        process.stdout.write(JSON.stringify(["err", e.message]));
  #|      });
  #|      req.end();
  #|    `);
  #|    const out = execSync("node " + JSON.stringify(tmp), {
  #|      maxBuffer: 10 * 1024 * 1024,
  #|      timeout: 35000,
  #|    });
  #|    try { fs.unlinkSync(tmp); } catch {}
  #|    return JSON.parse(out.toString());
  #|  } catch (e) {
  #|    return ["err", e.message || String(e)];
  #|  }
  #|}

///| 无认证 GET 请求。
fn host_get(url : String) -> Result[(Int, String), String] {
  host_get_bearer(url, "")
}

fn host_get_bearer(url : String, bearer : String) -> Result[(Int, String), String] {
  let result = host_get_bearer_ffi(url, bearer)
  if result.length() == 0 {
    return Err("empty response")
  }
  if result[0] == "err" {
    return Err(if result.length() > 1 { result[1] } else { "unknown error" })
  }
  if result.length() < 3 {
    return Err("malformed response")
  }
  let status = try @string.parse_int(result[1]) catch {
    _ => 0
  } noraise {
    n => n
  }
  Ok((status, result[2]))
}

///| 打开浏览器（最好的尝试，失败也不报错）。
fn host_open_browser(url : String) -> Unit {
  host_open_browser_ffi(url)
}
