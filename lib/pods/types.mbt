///| GPU Pod 管理（vLLM 部署编排）。
///
/// 平台无关的类型定义和配置管理。实际 SSH/命令执行由 runtime 注入。

///| Pod 配置。
pub(all) struct PodConfig {
  name : String
  host : String
  user : String
  port : Int
  ssh_key : String?
  gpu_type : String
  workspace : String
} derive(Show, Eq, ToJson, FromJson)

///| 模型部署配置。
pub(all) struct ModelConfig {
  name : String
  model_path : String      // HuggingFace repo 或本地路径
  tensor_parallel_size : Int
  max_model_len : Int?
  dtype : String           // "auto", "float16", "bfloat16", etc.
  gpu_memory_utilization : Double
  port : Int
  extra_args : Array[String]
} derive(Show, Eq, ToJson, FromJson)

///| Pod 运行状态。
pub(all) enum PodStatus {
  Offline
  Idle
  Running(String)  // model name
  Error(String)
} derive(Show, Eq)

///| 模型运行状态。
pub(all) struct ModelRunStatus {
  config : ModelConfig
  pid : Int?
  started_at : String?
  gpu_usage : Double?
} derive(Show, Eq)

///| Pod 管理器（所有 pod 的汇总）。
pub(all) struct PodRegistry {
  mut pods : Array[PodConfig]
  mut active_pod : String?
}

pub fn PodRegistry::new() -> PodRegistry {
  { pods: [], active_pod: None }
}

pub fn PodRegistry::add(self : PodRegistry, pod : PodConfig) -> Unit {
  for i = 0; i < self.pods.length(); i = i + 1 {
    if self.pods[i].name == pod.name {
      self.pods[i] = pod
      return
    }
  }
  self.pods.push(pod)
}

pub fn PodRegistry::get(self : PodRegistry, name : String) -> PodConfig? {
  for pod in self.pods {
    if pod.name == name { return Some(pod) }
  }
  None
}

pub fn PodRegistry::remove(self : PodRegistry, name : String) -> Unit {
  let retained : Array[PodConfig] = []
  for pod in self.pods {
    if pod.name != name { retained.push(pod) }
  }
  self.pods = retained
  if self.active_pod == Some(name) {
    self.active_pod = None
  }
}

pub fn PodRegistry::list(self : PodRegistry) -> Array[PodConfig] {
  self.pods.copy()
}

pub fn PodRegistry::set_active(self : PodRegistry, name : String) -> Result[Unit, String] {
  match self.get(name) {
    Some(_) => {
      self.active_pod = Some(name)
      Ok(())
    }
    None => Err("pod not found: " + name)
  }
}

pub fn PodRegistry::get_active(self : PodRegistry) -> PodConfig? {
  match self.active_pod {
    Some(name) => self.get(name)
    None => None
  }
}

///| 序列化 Pod 注册表到 JSON。
pub fn PodRegistry::to_json(self : PodRegistry) -> Json {
  let pods_json : Array[Json] = []
  for pod in self.pods {
    pods_json.push(pod.to_json())
  }
  Json::object({
    "pods": Json::array(pods_json),
    "active_pod": match self.active_pod {
      Some(name) => Json::string(name)
      None => Json::null()
    },
  })
}
