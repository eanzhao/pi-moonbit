///| Azure OpenAI 请求构建器。
///
/// Azure OpenAI 使用 OpenAI 兼容格式，但 endpoint 和认证方式不同：
/// endpoint: `https://{resource}.openai.azure.com/openai/deployments/{deployment}/chat/completions?api-version={version}`
/// 认证：api-key header（不是 Bearer token）

///| 构建 Azure OpenAI 的 endpoint URL。
pub fn build_azure_url(
  resource_name : String,
  deployment : String,
  api_version? : String = "2024-08-01-preview"
) -> String {
  "https://\{resource_name}.openai.azure.com/openai/deployments/\{deployment}/chat/completions?api-version=\{api_version}"
}

///| Azure OpenAI 的请求体（与 OpenAI Chat Completions 相同）。
pub fn build_azure_request_body(model : Model, context : Context, options : StreamOptions) -> Json {
  build_openai_request_body(model, context, options)
}

///| Azure OpenAI 的 SSE 解析（与 OpenAI 相同）。
pub fn parse_azure_sse_line(line : String, state : OpenAiStreamState) -> Array[AssistantMessageEvent] {
  parse_openai_sse_line(line, state)
}
