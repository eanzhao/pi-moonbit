///| 缓存保留策略，控制 prompt 缓存的生命周期。
pub(all) enum CacheRetention {
  None
  Short
  Long
} derive(Show, Eq, ToJson, FromJson)

///| 思维链的深度级别。
pub(all) enum ThinkingLevel {
  Minimal
  Low
  Medium
  High
  XHigh
} derive(Show, Eq, ToJson, FromJson)

///| 思维链模式。
pub(all) enum ThinkingMode {
  /// 禁用思维链
  Disabled
  /// 始终启用思维链
  Enabled
  /// 由模型自行决定是否使用思维链
  Adaptive
} derive(Show, Eq, ToJson, FromJson)

///| 工具定义，描述一个可供 LLM 调用的外部工具。
pub(all) struct Tool {
  /// 工具名称（LLM 通过此名称调用工具）
  name : String
  /// 工具功能描述
  description : String
  /// 工具参数的 JSON Schema
  parameters : Json
} derive(Show, Eq, ToJson, FromJson)

///| 流式请求的配置选项。
/// 所有字段均为可选，未设置时使用供应商的默认值。
pub(all) struct StreamOptions {
  /// 采样温度，值越高输出越随机
  temperature : Double?
  /// 最大输出 token 数
  max_tokens : Int?
  /// 核采样参数
  top_p : Double?
  /// API 密钥（覆盖默认配置）
  api_key : String?
  /// 缓存保留策略
  cache_retention : CacheRetention?
  /// 失败时的重试次数
  retry_count : Int?
  /// 重试间隔（毫秒）
  retry_delay_ms : Int?
  /// 思维链模式
  thinking_mode : ThinkingMode?
  /// 思维链 token 预算
  thinking_budget_tokens : Int?
  /// 推理深度级别
  reasoning : ThinkingLevel?
} derive(Show, Eq, ToJson, FromJson)

///| 创建一个所有字段为 None 的默认 StreamOptions。
pub fn StreamOptions::default() -> StreamOptions {
  {
    temperature: None,
    max_tokens: None,
    top_p: None,
    api_key: None,
    cache_retention: None,
    retry_count: None,
    retry_delay_ms: None,
    thinking_mode: None,
    thinking_budget_tokens: None,
    reasoning: None,
  }
}

///| 对话上下文，包含系统提示、对话历史和可用工具。
pub(all) struct Context {
  /// 系统提示词
  system_prompt : String?
  /// 对话历史消息列表
  messages : Array[Message]
  /// 可用工具列表
  tools : Array[Tool]
} derive(Show, Eq, ToJson, FromJson)
