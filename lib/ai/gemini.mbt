///| Gemini Generative AI 流式解析状态。
pub(all) struct GeminiStreamState {
  model : Model
  mut started : Bool
  mut content : Array[ContentBlock]
  mut active_text_index : Int?
  mut active_text_thinking : Bool
  mut usage : Usage
  mut terminal_emitted : Bool
  mut next_tool_call_id : Int
}

///| 创建新的 Gemini 流式解析状态。
pub fn GeminiStreamState::new(model : Model) -> GeminiStreamState {
  {
    model,
    started: false,
    content: [],
    active_text_index: None,
    active_text_thinking: false,
    usage: Usage::zero(),
    terminal_emitted: false,
    next_tool_call_id: 0,
  }
}

///| 将通用上下文映射为 Gemini GenerateContent 请求体。
pub fn build_gemini_request_body(model : Model, context : Context, options : StreamOptions) -> Json {
  let body : Map[String, Json] = {
    "contents": Json::array(context.messages.map(gemini_message_json)),
    "generationConfig": Json::object({
      "maxOutputTokens": Json::number(gemini_max_output_tokens(model, options).to_double()),
    }),
  }

  match context.system_prompt {
    Some(system_prompt) =>
      body["systemInstruction"] = Json::object({
        "parts": Json::array([
          Json::object({
            "text": Json::string(system_prompt),
          }),
        ]),
      })
    None => ()
  }
  match options.temperature {
    Some(temperature) =>
      gemini_generation_config(body)["temperature"] = Json::number(temperature)
    None => ()
  }
  match options.top_p {
    Some(top_p) => gemini_generation_config(body)["topP"] = Json::number(top_p)
    None => ()
  }
  if context.tools.length() > 0 {
    body["tools"] = Json::array([
      Json::object({
        "functionDeclarations": Json::array(context.tools.map(gemini_tool_definition_json)),
      }),
    ])
  }

  Json::object(body)
}

///| 构建 Gemini 流式接口 URL，API key 通过 query param 传递。
pub fn build_gemini_url(model : Model, api_key : String) -> String {
  let base_url = match model.base_url {
    Some(url) => url
    None => "https://generativelanguage.googleapis.com/v1beta"
  }
  let prefix = if base_url.has_suffix("/") { base_url } else { base_url + "/" }
  prefix + "models/\{model.id}:streamGenerateContent?key=\{api_key}&alt=sse"
}

///| 解析一行 Gemini SSE 数据并转换为内部流式事件。
pub fn parse_gemini_sse_line(
  line : String,
  state : GeminiStreamState
) -> Array[AssistantMessageEvent] {
  let trimmed = line.trim().to_string()
  if trimmed == "" || !trimmed.has_prefix("data:") {
    return []
  }

  let payload = trimmed[5:].trim().to_string()
  if payload == "" {
    return []
  }
  if payload == "[DONE]" {
    if state.started && !state.terminal_emitted {
      let events : Array[AssistantMessageEvent] = []
      gemini_emit_terminal_events("STOP", state, events)
      return events
    }
    return []
  }

  let json = try @json.parse(payload) catch {
    _ => return []
  }

  let events : Array[AssistantMessageEvent] = []
  if !state.started {
    state.started = true
    events.push(Start(gemini_build_assistant_message(state, Stop, None)))
  }

  gemini_update_usage(state, json)

  match gemini_first_candidate(json) {
    Some(candidate) => {
      match json_object_field(candidate, "content") {
        Some(content) => gemini_parse_content(content, state, events)
        None => ()
      }
      match json_string_field(candidate, "finishReason") {
        Some(reason) if reason.length() > 0 => gemini_emit_terminal_events(reason, state, events)
        _ => ()
      }
    }
    None => ()
  }

  events
}

fn gemini_message_json(message : Message) -> Json {
  match message {
    User(user) =>
      Json::object({
        "role": Json::string("user"),
        "parts": Json::array(gemini_user_parts_json(user.content)),
      })
    Assistant(assistant) =>
      Json::object({
        "role": Json::string("model"),
        "parts": Json::array(gemini_assistant_parts_json(assistant.content)),
      })
    ToolResult(result) =>
      Json::object({
        "role": Json::string("user"),
        "parts": Json::array([
          Json::object({
            "functionResponse": Json::object({
              "name": Json::string(result.tool_name),
              "response": Json::object({
                "result": Json::string(gemini_join_text_blocks(result.content)),
              }),
            }),
          }),
        ]),
      })
  }
}

fn gemini_user_parts_json(content : Array[ContentBlock]) -> Array[Json] {
  let parts : Array[Json] = []
  for block in content {
    match block {
      Text(text) | Thinking(text) => parts.push(gemini_text_part_json(text))
      Image(image) => parts.push(gemini_image_part_json(image))
      ContentBlock::ToolCall(_) => ()
    }
  }
  parts
}

fn gemini_assistant_parts_json(content : Array[ContentBlock]) -> Array[Json] {
  let parts : Array[Json] = []
  for block in content {
    match block {
      Text(text) | Thinking(text) => parts.push(gemini_text_part_json(text))
      Image(image) => parts.push(gemini_image_part_json(image))
      ContentBlock::ToolCall(tool_call) =>
        parts.push(Json::object({
          "functionCall": Json::object({
            "name": Json::string(tool_call.name),
            "args": tool_call.arguments,
          }),
        }))
    }
  }
  parts
}

fn gemini_text_part_json(text : String) -> Json {
  Json::object({
    "text": Json::string(text),
  })
}

fn gemini_image_part_json(image : ImageContent) -> Json {
  Json::object({
    "inlineData": Json::object({
      "mimeType": Json::string(gemini_mime_type_string(image.mime_type)),
      "data": Json::string(image.data),
    }),
  })
}

fn gemini_tool_definition_json(tool : Tool) -> Json {
  Json::object({
    "name": Json::string(tool.name),
    "description": Json::string(tool.description),
    "parameters": tool.parameters,
  })
}

fn gemini_mime_type_string(mime_type : ImageMimeType) -> String {
  match mime_type {
    Jpeg => "image/jpeg"
    Png => "image/png"
    Gif => "image/gif"
    Webp => "image/webp"
  }
}

fn gemini_join_text_blocks(content : Array[ContentBlock]) -> String {
  let texts : Array[String] = []
  for block in content {
    match block {
      Text(text) | Thinking(text) => texts.push(text)
      Image(_) => texts.push("[image]")
      ContentBlock::ToolCall(_) => ()
    }
  }
  texts.join("\n\n")
}

fn gemini_generation_config(body : Map[String, Json]) -> Map[String, Json] {
  match body.get("generationConfig") {
    Some(Object(config)) => config
    _ => {
      let config : Map[String, Json] = {}
      body["generationConfig"] = Json::object(config)
      config
    }
  }
}

fn gemini_max_output_tokens(model : Model, options : StreamOptions) -> Int {
  match options.max_tokens {
    Some(max_tokens) => max_tokens
    None => model.max_tokens
  }
}

fn gemini_first_candidate(json : Json) -> Json? {
  match json_array_field(json, "candidates") {
    Some(candidates) if candidates.length() > 0 => Some(candidates[0])
    _ => None
  }
}

fn gemini_parse_content(
  content : Json,
  state : GeminiStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  match json_array_field(content, "parts") {
    Some(parts) =>
      for part in parts {
        gemini_parse_part(part, state, events)
      }
    None => ()
  }
}

fn gemini_parse_part(
  part : Json,
  state : GeminiStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  match json_string_field(part, "text") {
    Some(text) if text.length() > 0 => {
      let thinking = gemini_json_bool_field(part, "thought").unwrap_or(false)
      let index = gemini_ensure_text_block(state, thinking, events)
      gemini_append_text(state, index, text, thinking)
      if thinking {
        events.push(ThinkingDelta(index, text))
      } else {
        events.push(TextDelta(index, text))
      }
    }
    _ => ()
  }

  match json_object_field(part, "functionCall") {
    Some(function_call) => {
      gemini_close_active_text_block(state, events)
      let tool_call = gemini_tool_call_json(function_call, state)
      let index = state.content.length()
      state.content.push(ContentBlock::ToolCall(tool_call))
      events.push(ToolCallStart(index, tool_call))
      let arguments_delta = tool_call.arguments.stringify(escape_slash=false)
      if arguments_delta.length() > 0 {
        events.push(ToolCallDelta(index, arguments_delta))
      }
      events.push(ToolCallEnd(index, tool_call))
    }
    None => ()
  }
}

fn gemini_ensure_text_block(
  state : GeminiStreamState,
  thinking : Bool,
  events : Array[AssistantMessageEvent]
) -> Int {
  match state.active_text_index {
    Some(index) if state.active_text_thinking == thinking => index
    Some(_) => {
      gemini_close_active_text_block(state, events)
      gemini_start_text_block(state, thinking, events)
    }
    None => gemini_start_text_block(state, thinking, events)
  }
}

fn gemini_start_text_block(
  state : GeminiStreamState,
  thinking : Bool,
  events : Array[AssistantMessageEvent]
) -> Int {
  let index = state.content.length()
  state.active_text_index = Some(index)
  state.active_text_thinking = thinking
  state.content.push(if thinking { Thinking("") } else { Text("") })
  if thinking {
    events.push(ThinkingStart(index))
  } else {
    events.push(TextStart(index))
  }
  index
}

fn gemini_append_text(
  state : GeminiStreamState,
  index : Int,
  delta : String,
  thinking : Bool
) -> Unit {
  let current = match state.content[index] {
    Text(text) | Thinking(text) => text
    _ => ""
  }
  state.content[index] =
    if thinking {
      Thinking(current + delta)
    } else {
      Text(current + delta)
    }
}

fn gemini_close_active_text_block(
  state : GeminiStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  match state.active_text_index {
    Some(index) => {
      if state.active_text_thinking {
        match state.content[index] {
          Thinking(thinking) => events.push(ThinkingEnd(index, thinking))
          _ => ()
        }
      } else {
        match state.content[index] {
          Text(text) => events.push(TextEnd(index, text))
          _ => ()
        }
      }
      state.active_text_index = None
    }
    None => ()
  }
}

fn gemini_tool_call_json(function_call : Json, state : GeminiStreamState) -> ToolCall {
  let name = json_string_field(function_call, "name").unwrap_or("")
  let arguments = match gemini_json_field(function_call, "args") {
    Some(args) => args
    None => Json::object({})
  }
  let id = match json_string_field(function_call, "id") {
    Some(id) if id.length() > 0 => id
    _ => gemini_next_tool_call_id(state)
  }
  { id, name, arguments }
}

fn gemini_next_tool_call_id(state : GeminiStreamState) -> String {
  state.next_tool_call_id = state.next_tool_call_id + 1
  "gemini_call_\{state.next_tool_call_id}"
}

fn gemini_emit_terminal_events(
  reason : String,
  state : GeminiStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  if state.terminal_emitted {
    return
  }

  gemini_close_active_text_block(state, events)

  let stop_reason =
    if gemini_has_tool_call(state.content) {
      ToolUse
    } else {
      gemini_finish_reason_to_stop_reason(reason)
    }
  let error_message = if stop_reason == Error { Some(reason) } else { None }
  let message = gemini_build_assistant_message(state, stop_reason, error_message)
  state.terminal_emitted = true
  match stop_reason {
    Error => events.push(Error(stop_reason, message))
    _ => events.push(Done(stop_reason, message))
  }
}

fn gemini_has_tool_call(content : Array[ContentBlock]) -> Bool {
  for block in content {
    match block {
      ContentBlock::ToolCall(_) => return true
      _ => ()
    }
  }
  false
}

fn gemini_build_assistant_message(
  state : GeminiStreamState,
  stop_reason : StopReason,
  error_message : String?
) -> AssistantMessage {
  {
    content: state.content.copy(),
    api: state.model.api,
    provider: state.model.provider,
    model: state.model.id,
    usage: state.usage,
    stop_reason,
    error_message,
    timestamp: 0.0,
  }
}

fn gemini_finish_reason_to_stop_reason(reason : String) -> StopReason {
  match reason {
    "STOP" => Stop
    "MAX_TOKENS" => Length
    "SAFETY" | "RECITATION" => Error
    _ => Error
  }
}

fn gemini_update_usage(state : GeminiStreamState, json : Json) -> Unit {
  let usage_json = match json_object_field(json, "usageMetadata") {
    Some(usage) => usage
    None => return
  }

  let prompt = json_int_field(usage_json, "promptTokenCount").unwrap_or(0)
  let candidates = json_int_field(usage_json, "candidatesTokenCount").unwrap_or(0)
  let thoughts = json_int_field(usage_json, "thoughtsTokenCount").unwrap_or(0)
  let cache_read = json_int_field(usage_json, "cachedContentTokenCount").unwrap_or(0)
  let input = prompt - cache_read
  let output = candidates + thoughts
  let total_tokens =
    json_int_field(usage_json, "totalTokenCount").unwrap_or(input + output + cache_read)

  let input_cost = state.model.cost.input * input.to_double() / 1_000_000.0
  let output_cost = state.model.cost.output * output.to_double() / 1_000_000.0
  let cache_read_cost = state.model.cost.cache_read * cache_read.to_double() / 1_000_000.0

  state.usage = {
    input,
    output,
    cache_read,
    cache_write: 0,
    total_tokens,
    cost: {
      input: input_cost,
      output: output_cost,
      cache_read: cache_read_cost,
      cache_write: 0.0,
      total: input_cost + output_cost + cache_read_cost,
    },
  }
}

fn gemini_json_field(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

fn gemini_json_bool_field(json : Json, key : String) -> Bool? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(True) => Some(true)
      Some(False) => Some(false)
      _ => None
    }
  } else {
    None
  }
}
