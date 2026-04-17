#external
type NativeFile

#borrow(path, mode)
extern "c" fn host_native_fopen_ffi(
  path : Bytes,
  mode : Bytes
) -> NativeFile = "moonbit_fopen_ffi"

#borrow(buffer, file)
extern "c" fn host_native_fread_ffi(
  buffer : Bytes,
  size : Int,
  nitems : Int,
  file : NativeFile
) -> Int = "moonbit_fread_ffi"

#borrow(buffer, file)
extern "c" fn host_native_fwrite_ffi(
  buffer : Bytes,
  size : Int,
  nitems : Int,
  file : NativeFile
) -> Int = "moonbit_fwrite_ffi"

#borrow(file)
extern "c" fn host_native_fseek_ffi(
  file : NativeFile,
  offset : Int,
  whence : Int
) -> Int = "moonbit_fseek_ffi"

#borrow(file)
extern "c" fn host_native_ftell_ffi(file : NativeFile) -> Int = "moonbit_ftell_ffi"

#borrow(file)
extern "c" fn host_native_fflush_ffi(file : NativeFile) -> Int = "moonbit_fflush_ffi"

#borrow(file)
extern "c" fn host_native_fclose_ffi(file : NativeFile) -> Int = "moonbit_fclose_ffi"

#borrow(file)
extern "c" fn host_native_is_null_file_ffi(file : NativeFile) -> Bool = "moonbit_is_null"

#borrow(path)
extern "c" fn host_native_stat_ffi(path : Bytes) -> Int = "moonbit_stat_ffi"

#borrow(path)
extern "c" fn host_native_is_dir_ffi(path : Bytes) -> Int = "moonbit_is_dir_ffi"

#borrow(path)
extern "c" fn host_native_is_file_ffi(path : Bytes) -> Int = "moonbit_is_file_ffi"

#borrow(path)
extern "c" fn host_native_create_dir_ffi(path : Bytes) -> Int = "moonbit_create_dir_ffi"

#borrow(path)
extern "c" fn host_native_read_dir_ffi(path : Bytes) -> FixedArray[Bytes] = "moonbit_read_dir_ffi"

#borrow(path)
extern "c" fn host_native_remove_file_ffi(path : Bytes) -> Int = "moonbit_remove_file_ffi"

#borrow(command)
extern "c" fn host_native_system_ffi(command : Bytes) -> Int = "system"

extern "c" fn host_native_getchar_ffi() -> Int = "getchar"

#borrow(buffer)
extern "c" fn host_native_write_ffi(
  fd : Int,
  buffer : Bytes,
  count : Int
) -> Int = "write"

extern "c" fn host_native_error_message_ffi() -> Bytes = "moonbit_get_error_message"

extern "c" fn host_native_exit_ffi(code : Int) = "exit"

let host_native_seek_set : Int = 0
let host_native_seek_end : Int = 2

fn host_read_text(path : String) -> Result[String, String] {
  let file = host_native_fopen_ffi(
    mbt_string_to_utf8_bytes(path, true),
    mbt_string_to_utf8_bytes("rb", true),
  )
  if host_native_is_null_file_ffi(file) {
    return Err(host_native_last_error("failed to open file: " + path))
  }
  if host_native_fseek_ffi(file, 0, host_native_seek_end) != 0 {
    let error = host_native_last_error("failed to seek file: " + path)
    ignore(host_native_fclose_ffi(file))
    return Err(error)
  }
  let size = host_native_ftell_ffi(file)
  if size < 0 {
    let error = host_native_last_error("failed to determine file size: " + path)
    ignore(host_native_fclose_ffi(file))
    return Err(error)
  }
  if host_native_fseek_ffi(file, 0, host_native_seek_set) != 0 {
    let error = host_native_last_error("failed to rewind file: " + path)
    ignore(host_native_fclose_ffi(file))
    return Err(error)
  }
  let buffer = Bytes::new(size)
  if size > 0 {
    let read_count = host_native_fread_ffi(buffer, 1, size, file)
    if read_count != size {
      let error = host_native_last_error("failed to read file: " + path)
      ignore(host_native_fclose_ffi(file))
      return Err(error)
    }
  }
  if host_native_fclose_ffi(file) != 0 {
    return Err(host_native_last_error("failed to close file: " + path))
  }
  Ok(utf8_bytes_to_mbt_string(buffer))
}

fn host_write_text(path : String, content : String) -> Result[Unit, String] {
  match host_native_parent_directory(path) {
    Some(parent) =>
      match host_native_ensure_directory(parent) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    None => ()
  }
  let file = host_native_fopen_ffi(
    mbt_string_to_utf8_bytes(path, true),
    mbt_string_to_utf8_bytes("wb", true),
  )
  if host_native_is_null_file_ffi(file) {
    return Err(host_native_last_error("failed to open file for writing: " + path))
  }
  let bytes = mbt_string_to_utf8_bytes(content, false)
  if bytes.length() > 0 {
    let written = host_native_fwrite_ffi(bytes, 1, bytes.length(), file)
    if written != bytes.length() {
      let error = host_native_last_error("failed to write file: " + path)
      ignore(host_native_fclose_ffi(file))
      return Err(error)
    }
  }
  if host_native_fflush_ffi(file) != 0 {
    let error = host_native_last_error("failed to flush file: " + path)
    ignore(host_native_fclose_ffi(file))
    return Err(error)
  }
  if host_native_fclose_ffi(file) != 0 {
    return Err(host_native_last_error("failed to close file: " + path))
  }
  Ok(())
}

fn host_file_exists(path : String) -> Bool {
  host_native_stat_ffi(mbt_string_to_utf8_bytes(path, true)) == 0
}

fn host_list_files(path : String) -> Result[Array[String], String] {
  let path_bytes = mbt_string_to_utf8_bytes(path, true)
  if host_native_stat_ffi(path_bytes) != 0 {
    return Ok([])
  }
  if host_native_is_dir_ffi(path_bytes) != 1 {
    return Err("not a directory: " + path)
  }
  let entries = host_native_read_dir_ffi(path_bytes)
  let files : Array[String] = []
  for entry in entries {
    let name = utf8_bytes_to_mbt_string(entry)
    let full_path = host_native_join_path(path, name)
    if host_native_is_file_ffi(mbt_string_to_utf8_bytes(full_path, true)) == 1 {
      files.push(full_path)
    }
  }
  Ok(files)
}

fn host_run_command(
  command : String,
  cwd : String
) -> Result[@coding_agent.CommandExecutionResult, String] {
  let base = host_native_temp_base("pimbt-cmd")
  let stdout_path = base + ".stdout"
  let stderr_path = base + ".stderr"
  let exit_path = base + ".exit"
  let working_dir = if cwd.length() == 0 { "." } else { cwd }
  let shell_command =
    "(cd " +
    host_native_shell_quote(working_dir) +
    " && /bin/zsh -lc " +
    host_native_shell_quote(command) +
    ") > " +
    host_native_shell_quote(stdout_path) +
    " 2> " +
    host_native_shell_quote(stderr_path) +
    "; printf %s \"$?\" > " +
    host_native_shell_quote(exit_path)
  let status = host_native_system_ffi(mbt_string_to_utf8_bytes(shell_command, true))
  if status < 0 {
    host_native_cleanup_temp_files([stdout_path, stderr_path, exit_path])
    return Err(host_native_last_error("failed to invoke shell"))
  }
  let stdout = match host_read_text(stdout_path) {
    Ok(text) => text
    Err(error) => {
      host_native_cleanup_temp_files([stdout_path, stderr_path, exit_path])
      return Err("failed to read command stdout: " + error)
    }
  }
  let stderr = match host_read_text(stderr_path) {
    Ok(text) => text
    Err(error) => {
      host_native_cleanup_temp_files([stdout_path, stderr_path, exit_path])
      return Err("failed to read command stderr: " + error)
    }
  }
  let exit_code_text = match host_read_text(exit_path) {
    Ok(text) => text.trim().to_string()
    Err(error) => {
      host_native_cleanup_temp_files([stdout_path, stderr_path, exit_path])
      return Err("failed to read command exit code: " + error)
    }
  }
  host_native_cleanup_temp_files([stdout_path, stderr_path, exit_path])
  Ok({
    stdout,
    stderr,
    exit_code: parse_int_string(exit_code_text),
    cancelled: false,
    truncated: false,
    full_output_path: None,
  })
}

fn host_stdout_write(text : String) -> Unit {
  write_console_line(text)
}

fn host_stderr_write(text : String) -> Unit {
  write_console_line(text)
}

fn host_read_line(prompt : String) -> String? {
  if prompt.length() > 0 {
    host_native_write_text_fd(1, prompt)
  }
  let bytes : Array[Byte] = []
  while true {
    let value = host_native_getchar_ffi()
    if value < 0 {
      if bytes.length() == 0 {
        return None
      }
      break
    }
    if value == '\n'.to_int() {
      break
    }
    if value != '\r'.to_int() {
      bytes.push(value.to_byte())
    }
  }
  Some(utf8_bytes_to_mbt_string(Bytes::from_array(bytes)))
}

fn host_now_iso() -> String {
  let now_ms = @env.now()
  let days = now_ms / 86_400_000UL
  let day_ms = now_ms % 86_400_000UL
  let z = days.to_int64() + 719_468L
  let era = if z >= 0L { z / 146_097L } else { (z - 146_096L) / 146_097L }
  let doe = z - era * 146_097L
  let yoe = (doe - doe / 1_460L + doe / 36_524L - doe / 146_096L) / 365L
  let y = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let mp = (5L * doy + 2L) / 153L
  let day = doy - (153L * mp + 2L) / 5L + 1L
  let month = mp + (if mp < 10L { 3L } else { -9L })
  let year = y + (if month <= 2L { 1L } else { 0L })
  let hour = day_ms / 3_600_000UL
  let minute = (day_ms % 3_600_000UL) / 60_000UL
  let second = (day_ms % 60_000UL) / 1_000UL
  let millis = day_ms % 1_000UL
  host_native_pad_uint64(year.to_uint64(), 4) +
  "-" +
  host_native_pad_uint64(month.to_uint64(), 2) +
  "-" +
  host_native_pad_uint64(day.to_uint64(), 2) +
  "T" +
  host_native_pad_uint64(hour, 2) +
  ":" +
  host_native_pad_uint64(minute, 2) +
  ":" +
  host_native_pad_uint64(second, 2) +
  "." +
  host_native_pad_uint64(millis, 3) +
  "Z"
}

fn host_exit_process(code : Int) -> Unit {
  host_native_exit_ffi(code)
}

fn write_console_line(text : String) -> Unit {
  match text.strip_suffix("\n") {
    Some(view) => println(view.to_string())
    None => println(text)
  }
}

fn host_native_write_text_fd(fd : Int, text : String) -> Unit {
  let bytes = mbt_string_to_utf8_bytes(text, false)
  if bytes.length() > 0 {
    ignore(host_native_write_ffi(fd, bytes, bytes.length()))
  }
}

fn host_native_last_error(context : String) -> String {
  let message = utf8_bytes_to_mbt_string(host_native_error_message_ffi())
  if message.length() == 0 {
    context
  } else {
    context + ": " + message
  }
}

fn host_native_temp_base(prefix : String) -> String {
  let timestamp = @env.now().to_string()
  let mut attempt = 0
  while true {
    let suffix = if attempt == 0 {
      ""
    } else {
      "-" + attempt.to_string()
    }
    let base = "/tmp/" + prefix + "-" + timestamp + suffix
    if !host_file_exists(base + ".stdout") &&
      !host_file_exists(base + ".stderr") &&
      !host_file_exists(base + ".exit") {
      return base
    }
    attempt += 1
  }
  "/tmp/" + prefix + "-" + timestamp
}

fn host_native_cleanup_temp_files(paths : Array[String]) -> Unit {
  for path in paths {
    ignore(host_native_remove_file_ffi(mbt_string_to_utf8_bytes(path, true)))
  }
}

fn host_native_shell_quote(text : String) -> String {
  let builder = StringBuilder::new()
  builder.write_char('\'')
  for ch in text {
    if ch == '\'' {
      builder.write_string("'\"'\"'")
    } else {
      builder.write_char(ch)
    }
  }
  builder.write_char('\'')
  builder.to_string()
}

fn host_native_parent_directory(path : String) -> String? {
  let mut index = -1
  for i in 0..<path.length() {
    let code = path.unsafe_get(i).to_int()
    if code == '/'.to_int() || code == '\\'.to_int() {
      index = i
    }
  }
  if index < 0 {
    None
  } else if index == 0 {
    Some("/")
  } else {
    Some(path[:index].to_string())
  }
}

fn host_native_ensure_directory(path : String) -> Result[Unit, String] {
  if path.length() == 0 || path == "." {
    return Ok(())
  }
  let path_bytes = mbt_string_to_utf8_bytes(path, true)
  if host_native_is_dir_ffi(path_bytes) == 1 {
    return Ok(())
  }
  match host_native_parent_directory(path) {
    Some(parent) if parent != path =>
      match host_native_ensure_directory(parent) {
        Ok(_) => ()
        Err(error) => return Err(error)
      }
    _ => ()
  }
  if host_native_create_dir_ffi(path_bytes) == 0 || host_native_is_dir_ffi(path_bytes) == 1 {
    Ok(())
  } else {
    Err(host_native_last_error("failed to create directory: " + path))
  }
}

fn host_native_join_path(base : String, name : String) -> String {
  if base.has_suffix("/") || base.has_suffix("\\") {
    base + name
  } else {
    base + "/" + name
  }
}

fn host_native_pad_uint64(value : UInt64, width : Int) -> String {
  let text = value.to_string()
  if text.length() >= width {
    text
  } else {
    String::make(width - text.length(), '0') + text
  }
}

fn parse_int_string(text : String) -> Int {
  let parsed : Result[Int, Error] = try? @string.parse_int(text)
  match parsed {
    Ok(value) => value
    Err(_) => -1
  }
}

fn utf8_bytes_to_mbt_string(bytes : Bytes) -> String {
  let result = StringBuilder::new()
  let len = bytes.length()
  let mut i = 0
  while i < len {
    let mut code = bytes[i].to_int()
    if code == 0 {
      break
    } else if code < 0x80 {
      result.write_char(code.unsafe_to_char())
      i += 1
    } else if code < 0xE0 {
      if i + 1 >= len {
        break
      }
      code = ((code & 0x1F) << 6) | (bytes[i + 1].to_int() & 0x3F)
      result.write_char(code.unsafe_to_char())
      i += 2
    } else if code < 0xF0 {
      if i + 2 >= len {
        break
      }
      code = ((code & 0x0F) << 12) |
        ((bytes[i + 1].to_int() & 0x3F) << 6) |
        (bytes[i + 2].to_int() & 0x3F)
      result.write_char(code.unsafe_to_char())
      i += 3
    } else {
      if i + 3 >= len {
        break
      }
      code = ((code & 0x07) << 18) |
        ((bytes[i + 1].to_int() & 0x3F) << 12) |
        ((bytes[i + 2].to_int() & 0x3F) << 6) |
        (bytes[i + 3].to_int() & 0x3F)
      code -= 0x10000
      result.write_char(((code >> 10) + 0xD800).unsafe_to_char())
      result.write_char(((code & 0x3FF) + 0xDC00).unsafe_to_char())
      i += 4
    }
  }
  result.to_string()
}

fn mbt_string_to_utf8_bytes(str : String, append_nul : Bool) -> Bytes {
  let bytes : Array[Byte] = []
  let len = str.length()
  let mut i = 0
  while i < len {
    let mut code = str.code_unit_at(i).to_int()
    if 0xD800 <= code && code <= 0xDBFF {
      code -= 0xD800
      i += 1
      let low = str.code_unit_at(i).to_int() - 0xDC00
      code = (code << 10) + low + 0x10000
    }
    if code < 0x80 {
      bytes.push(code.to_byte())
    } else if code < 0x800 {
      bytes.push((0xC0 + (code >> 6)).to_byte())
      bytes.push((0x80 + (code & 0x3F)).to_byte())
    } else if code < 0x10000 {
      bytes.push((0xE0 + (code >> 12)).to_byte())
      bytes.push((0x80 + ((code >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 + (code & 0x3F)).to_byte())
    } else {
      bytes.push((0xF0 + (code >> 18)).to_byte())
      bytes.push((0x80 + ((code >> 12) & 0x3F)).to_byte())
      bytes.push((0x80 + ((code >> 6) & 0x3F)).to_byte())
      bytes.push((0x80 + (code & 0x3F)).to_byte())
    }
    i += 1
  }
  if append_nul {
    bytes.push(b'\x00')
  }
  Bytes::from_array(bytes)
}
