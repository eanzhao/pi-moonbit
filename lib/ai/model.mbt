///| API 标识符（开放联合类型，允许任意字符串值）。
/// 使用 newtype 包装而非枚举，以支持用户自定义的 API 协议。
pub(all) struct ApiId(String) derive(Eq, Hash, Show, ToJson, FromJson)

///| 供应商标识符（开放联合类型，允许任意字符串值）。
/// 用于区分不同的 LLM 服务商，如 Anthropic、OpenAI 等。
pub(all) struct ProviderId(String) derive(Eq, Hash, Show, ToJson, FromJson)

///| 模型支持的输入模态。
pub(all) enum InputModality {
  Text
  Image
} derive(Show, Eq, ToJson, FromJson)

///| 模型的价格信息，单位为每百万 token 的费用（美元）。
pub(all) struct ModelCost {
  input : Double
  output : Double
  cache_read : Double
  cache_write : Double
} derive(Show, Eq, ToJson, FromJson)

///| LLM 模型的完整定义，包含标识、能力、价格和上下文窗口等信息。
pub(all) struct Model {
  /// 模型标识，如 "claude-sonnet-4-20250514"
  id : String
  /// 模型显示名称
  name : String
  /// 模型使用的 API 协议
  api : ApiId
  /// 模型所属的供应商
  provider : ProviderId
  /// 自定义 API 端点（用于自托管或代理场景）
  base_url : String?
  /// 是否支持推理/思维链
  reasoning : Bool
  /// 支持的输入模态列表
  input_modalities : Array[InputModality]
  /// 价格信息
  cost : ModelCost
  /// 上下文窗口大小（token 数）
  context_window : Int
  /// 最大输出 token 数
  max_tokens : Int
} derive(Show, Eq, ToJson, FromJson)

// --- 已知 API 标识符 ---

///|
pub let api_anthropic_messages : ApiId = ApiId("anthropic-messages")

///|
pub let api_openai_completions : ApiId = ApiId("openai-chat-completions")

///|
pub let api_openai_responses : ApiId = ApiId("openai-responses")

///|
pub let api_mistral : ApiId = ApiId("mistral-conversation")

///|
pub let api_google_genai : ApiId = ApiId("google-generativeai")

///|
pub let api_google_vertex : ApiId = ApiId("google-vertex")

///|
pub let api_bedrock : ApiId = ApiId("bedrock-converse-stream")

///|
pub let api_azure_openai : ApiId = ApiId("azure-openai-responses")

// --- 已知供应商标识符 ---

///|
pub let provider_anthropic : ProviderId = ProviderId("anthropic")

///|
pub let provider_openai : ProviderId = ProviderId("openai")

///|
pub let provider_google : ProviderId = ProviderId("google")

///|
pub let provider_google_vertex : ProviderId = ProviderId("google-vertex")

///|
pub let provider_mistral : ProviderId = ProviderId("mistral")

///|
pub let provider_groq : ProviderId = ProviderId("groq")

///|
pub let provider_xai : ProviderId = ProviderId("xai")

///|
pub let provider_bedrock : ProviderId = ProviderId("amazon-bedrock")

///|
pub let provider_azure_openai : ProviderId = ProviderId("azure-openai")

///|
pub let provider_ollama : ProviderId = ProviderId("ollama")

///| 根据模型价格和实际用量计算总费用（美元）。
/// 价格按每百万 token 计算，因此需要除以 1,000,000。
pub fn calculate_cost(model : Model, usage : Usage) -> Double {
  let c = model.cost
  let input_cost = c.input * usage.input.to_double() / 1_000_000.0
  let output_cost = c.output * usage.output.to_double() / 1_000_000.0
  let cache_read_cost = c.cache_read * usage.cache_read.to_double() / 1_000_000.0
  let cache_write_cost = c.cache_write * usage.cache_write.to_double() / 1_000_000.0
  input_cost + output_cost + cache_read_cost + cache_write_cost
}

///| 判断两个模型是否等价（基于 id 和 provider 的组合）。
/// 同一 id 可能存在于不同供应商，因此需要同时比较两者。
pub fn models_are_equal(a : Model, b : Model) -> Bool {
  a.id == b.id && a.provider == b.provider
}
