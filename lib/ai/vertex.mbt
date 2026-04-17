///| Google Vertex AI 请求构建器。
///
/// Vertex AI 与 Generative AI API 消息结构相同，但 endpoint 和认证不同：
/// endpoint: `https://{region}-aiplatform.googleapis.com/v1/projects/{project}/locations/{region}/publishers/google/models/{model}:streamGenerateContent`
/// 认证：Google Cloud OAuth token (通过 Application Default Credentials)
///
/// 因此 Vertex 可以复用 gemini 的 request body 构建器，只是 URL 和 auth 不同。

///| 构建 Vertex AI 的 endpoint URL。
pub fn build_vertex_url(project_id : String, region : String, model_id : String) -> String {
  "https://\{region}-aiplatform.googleapis.com/v1/projects/\{project_id}/locations/\{region}/publishers/google/models/\{model_id}:streamGenerateContent"
}

///| Vertex AI 的请求体（与 Gemini Generative AI 相同）。
pub fn build_vertex_request_body(model : Model, context : Context, options : StreamOptions) -> Json {
  build_gemini_request_body(model, context, options)
}

///| Vertex AI 的 SSE 解析（与 Gemini 相同）。
pub fn parse_vertex_sse_line(line : String, state : GeminiStreamState) -> Array[AssistantMessageEvent] {
  parse_gemini_sse_line(line, state)
}
