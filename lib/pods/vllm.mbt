///| vLLM 启动命令构建。

///| 构建 vLLM serve 命令。
pub fn build_vllm_serve_command(config : ModelConfig) -> String {
  let parts : Array[String] = [
    "python -m vllm.entrypoints.openai.api_server",
    "--model", shell_quote_vllm(config.model_path),
    "--tensor-parallel-size", config.tensor_parallel_size.to_string(),
    "--dtype", config.dtype,
    "--gpu-memory-utilization", config.gpu_memory_utilization.to_string(),
    "--port", config.port.to_string(),
    "--served-model-name", shell_quote_vllm(config.name),
  ]
  match config.max_model_len {
    Some(len) => {
      parts.push("--max-model-len")
      parts.push(len.to_string())
    }
    None => ()
  }
  for arg in config.extra_args {
    parts.push(arg)
  }
  parts.join(" ")
}

///| 构建 vLLM 后台运行命令（nohup + log 重定向）。
pub fn build_vllm_background_command(config : ModelConfig, log_path : String) -> String {
  let serve = build_vllm_serve_command(config)
  "nohup " + serve + " > " + shell_quote_vllm(log_path) + " 2>&1 &"
}

///| 构建 vLLM 健康检查命令。
pub fn build_vllm_health_command(port : Int) -> String {
  "curl -s -o /dev/null -w '%{http_code}' http://localhost:" + port.to_string() + "/v1/models"
}

///| 构建 vLLM 停止命令（按进程查找 PID 并 kill）。
pub fn build_vllm_stop_command(model_name : String) -> String {
  "pkill -f 'served-model-name " + model_name + "' || true"
}

fn shell_quote_vllm(s : String) -> String {
  "'" + s.replace(old="'", new="'\\''") + "'"
}
