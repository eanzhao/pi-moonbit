pub fn parse_sandbox_arg(value : String) -> Result[SandboxConfig, String] {
  if value == "host" {
    return Ok(SandboxConfig::Host)
  }
  if value.has_prefix("docker:") {
    let container = value["docker:".length():].to_string()
    if container.length() == 0 {
      return Err("docker sandbox requires a container name")
    }
    return Ok(SandboxConfig::Docker({ container, }))
  }
  Err("invalid sandbox: " + value)
}

pub fn sandbox_arg(config : SandboxConfig) -> String {
  match config {
    Host => "host"
    Docker(docker) => "docker:" + docker.container
  }
}

pub fn sandbox_workspace_root(
  config : SandboxConfig,
  host_workspace : String
) -> String {
  match config {
    Host => host_workspace
    Docker(_) => "/workspace"
  }
}

pub fn translate_host_path_to_workspace(
  config : SandboxConfig,
  host_workspace : String,
  host_path : String
) -> String {
  let workspace_root = sandbox_workspace_root(config, host_workspace)
  match config {
    Host => host_path
    Docker(_) =>
      if host_path == host_workspace {
        workspace_root
      } else {
        let prefix = if host_workspace.has_suffix("/") {
          host_workspace
        } else {
          host_workspace + "/"
        }
        if host_path.has_prefix(prefix) {
          mom_sandbox_join_path(workspace_root, host_path[prefix.length():].to_string())
        } else {
          host_path
        }
      }
  }
}

fn mom_sandbox_join_path(base : String, child : String) -> String {
  if base.has_suffix("/") {
    base + child
  } else {
    base + "/" + child
  }
}
