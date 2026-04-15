///|
/// API identifier (open union — any string value allowed).
pub(all) struct ApiId(String) derive(Eq, Hash, Show)

///|
/// Provider identifier (open union — any string value allowed).
pub(all) struct ProviderId(String) derive(Eq, Hash, Show)

///|
pub(all) enum InputModality {
  Text
  Image
} derive(Show, Eq)

///|
pub(all) struct ModelCost {
  input : Double
  output : Double
  cache_read : Double
  cache_write : Double
} derive(Show, Eq)

///|
pub(all) struct Model {
  id : String
  name : String
  api : ApiId
  provider : ProviderId
  base_url : String?
  reasoning : Bool
  input_modalities : Array[InputModality]
  cost : ModelCost
  context_window : Int
  max_tokens : Int
} derive(Show)

// --- Known API identifiers ---

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

// --- Known provider identifiers ---

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

///|
pub fn calculate_cost(model : Model, usage : Usage) -> Double {
  let c = model.cost
  let input_cost = c.input * usage.input.to_double() / 1_000_000.0
  let output_cost = c.output * usage.output.to_double() / 1_000_000.0
  let cache_read_cost = c.cache_read * usage.cache_read.to_double() / 1_000_000.0
  let cache_write_cost = c.cache_write * usage.cache_write.to_double() / 1_000_000.0
  input_cost + output_cost + cache_read_cost + cache_write_cost
}

///|
pub fn models_are_equal(a : Model, b : Model) -> Bool {
  a.id == b.id && a.provider == b.provider
}
