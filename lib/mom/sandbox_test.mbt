test "parse sandbox arg handles host and docker" {
  let host = parse_sandbox_arg("host")
  assert_true(host == Ok(SandboxConfig::Host))

  let docker = parse_sandbox_arg("docker:mom-sandbox")
  assert_true(docker == Ok(SandboxConfig::Docker({ container: "mom-sandbox" })))
  assert_true(parse_sandbox_arg("docker:") is Err(_))
  assert_true(parse_sandbox_arg("podman:test") is Err(_))
}

test "translate host paths into container workspace when needed" {
  let sandbox = SandboxConfig::Docker({ container: "mom-sandbox" })
  assert_eq(sandbox_workspace_root(sandbox, "/Users/me/mom/workspace"), "/workspace")
  assert_eq(
    translate_host_path_to_workspace(sandbox, "/Users/me/mom/workspace", "/Users/me/mom/workspace/channels/slack/C1/log.jsonl"),
    "/workspace/channels/slack/C1/log.jsonl",
  )
  assert_eq(
    translate_host_path_to_workspace(SandboxConfig::Host, "/Users/me/mom/workspace", "/Users/me/mom/workspace/log.jsonl"),
    "/Users/me/mom/workspace/log.jsonl",
  )
}
