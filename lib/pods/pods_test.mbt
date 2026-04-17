test "pod registry add, get, remove" {
  let registry = PodRegistry::new()
  let pod : PodConfig = {
    name: "gpu-1",
    host: "1.2.3.4",
    user: "ubuntu",
    port: 22,
    ssh_key: Some("~/.ssh/id_rsa"),
    gpu_type: "A100",
    workspace: "/workspace",
  }
  registry.add(pod)
  assert_eq(registry.list().length(), 1)
  match registry.get("gpu-1") {
    Some(p) => assert_eq(p.host, "1.2.3.4")
    None => fail("expected pod")
  }
  registry.remove("gpu-1")
  assert_eq(registry.list().length(), 0)
}

test "pod registry active pod tracking" {
  let registry = PodRegistry::new()
  registry.add({ name: "a", host: "h1", user: "u", port: 22, ssh_key: None, gpu_type: "A100", workspace: "/w" })
  registry.add({ name: "b", host: "h2", user: "u", port: 22, ssh_key: None, gpu_type: "H100", workspace: "/w" })
  match registry.set_active("a") {
    Ok(_) => ()
    Err(msg) => fail(msg)
  }
  match registry.get_active() {
    Some(p) => assert_eq(p.name, "a")
    None => fail("expected active pod")
  }
  assert_true(registry.set_active("nonexistent") is Err(_))
}

test "ssh command construction" {
  let pod : PodConfig = {
    name: "test", host: "1.2.3.4", user: "ubuntu", port: 2222,
    ssh_key: Some("~/.ssh/key"), gpu_type: "A100", workspace: "/w",
  }
  let cmd = build_ssh_command(pod, "echo hello")
  assert_true(cmd.contains("ssh"))
  assert_true(cmd.contains("-p 2222"))
  assert_true(cmd.contains("-i"))
  assert_true(cmd.contains("ubuntu@1.2.3.4"))
  assert_true(cmd.contains("echo hello"))
}

test "vllm serve command" {
  let config : ModelConfig = {
    name: "my-model",
    model_path: "meta-llama/Llama-3-8B",
    tensor_parallel_size: 2,
    max_model_len: Some(8192),
    dtype: "auto",
    gpu_memory_utilization: 0.9,
    port: 8000,
    extra_args: ["--trust-remote-code"],
  }
  let cmd = build_vllm_serve_command(config)
  assert_true(cmd.contains("vllm.entrypoints.openai.api_server"))
  assert_true(cmd.contains("meta-llama/Llama-3-8B"))
  assert_true(cmd.contains("--tensor-parallel-size 2"))
  assert_true(cmd.contains("--max-model-len"))
  assert_true(cmd.contains("--trust-remote-code"))
}

test "pod registry json roundtrip" {
  let registry = PodRegistry::new()
  registry.add({ name: "gpu", host: "h", user: "u", port: 22, ssh_key: None, gpu_type: "A100", workspace: "/w" })
  ignore(registry.set_active("gpu"))
  let json = registry.to_json()
  match json {
    Object(obj) => {
      assert_true(obj.get("pods") is Some(_))
      assert_true(obj.get("active_pod") is Some(_))
    }
    _ => fail("expected object")
  }
}
