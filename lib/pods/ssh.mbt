///| SSH 命令构建（纯字符串拼接，实际执行由调用方完成）。

///| 构建 SSH 命令。
pub fn build_ssh_command(pod : PodConfig, remote_command : String) -> String {
  let key_arg = match pod.ssh_key {
    Some(path) => "-i " + shell_quote(path) + " "
    None => ""
  }
  "ssh " + key_arg + "-p " + pod.port.to_string() + " " +
  shell_quote(pod.user + "@" + pod.host) + " " + shell_quote(remote_command)
}

///| 构建 SCP 上传命令。
pub fn build_scp_upload_command(pod : PodConfig, local_path : String, remote_path : String) -> String {
  let key_arg = match pod.ssh_key {
    Some(path) => "-i " + shell_quote(path) + " "
    None => ""
  }
  "scp " + key_arg + "-P " + pod.port.to_string() + " " +
  shell_quote(local_path) + " " +
  shell_quote(pod.user + "@" + pod.host + ":" + remote_path)
}

///| 构建 SCP 下载命令。
pub fn build_scp_download_command(pod : PodConfig, remote_path : String, local_path : String) -> String {
  let key_arg = match pod.ssh_key {
    Some(path) => "-i " + shell_quote(path) + " "
    None => ""
  }
  "scp " + key_arg + "-P " + pod.port.to_string() + " " +
  shell_quote(pod.user + "@" + pod.host + ":" + remote_path) + " " +
  shell_quote(local_path)
}

fn shell_quote(s : String) -> String {
  "'" + s.replace(old="'", new="'\\''") + "'"
}
