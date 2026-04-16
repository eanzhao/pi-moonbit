enum AnthropicBlockKind {
  TextBlock
  ThinkingBlock
  ToolBlock
  UnknownBlock
} derive(Eq)

///| Anthropic Messages 流式解析状态。
pub(all) struct AnthropicStreamState {
  model : Model
  mut current_tool_id : String
  mut current_tool_name : String
  mut tool_input_json : String
  mut input_tokens : Int
  mut output_tokens : Int
  mut started : Bool
  mut content : Array[ContentBlock]
  mut block_kinds : Array[AnthropicBlockKind]
  mut block_closed : Array[Bool]
  mut current_tool_block_index : Int?
  mut terminal_emitted : Bool
}

///| 创建新的 Anthropic 流式解析状态。
pub fn AnthropicStreamState::new(model : Model) -> AnthropicStreamState {
  {
    model,
    current_tool_id: "",
    current_tool_name: "",
    tool_input_json: "",
    input_tokens: 0,
    output_tokens: 0,
    started: false,
    content: [],
    block_kinds: [],
    block_closed: [],
    current_tool_block_index: None,
    terminal_emitted: false,
  }
}

///| 将通用上下文映射为 Anthropic Messages 请求体。
pub fn build_anthropic_request_body(
  model : Model,
  context : Context,
  options : StreamOptions
) -> Json {
  let body : Map[String, Json] = {
    "model": Json::string(model.id),
    "messages": Json::array(context.messages.map(anthropic_message_json)),
    "stream": Json::boolean(true),
    "max_tokens": Json::number(anthropic_max_tokens(options).to_double()),
  }

  match context.system_prompt {
    Some(system_prompt) => body["system"] = Json::string(system_prompt)
    None => ()
  }
  match options.temperature {
    Some(temperature) => body["temperature"] = Json::number(temperature)
    None => ()
  }
  match options.top_p {
    Some(top_p) => body["top_p"] = Json::number(top_p)
    None => ()
  }
  if context.tools.length() > 0 {
    body["tools"] = Json::array(context.tools.map(anthropic_tool_definition_json))
  }
  match anthropic_thinking_json(options) {
    Some(thinking) => body["thinking"] = thinking
    None => ()
  }

  Json::object(body)
}

///| 解析一条 Anthropic SSE 事件并转换为内部流式事件。
pub fn parse_anthropic_sse_event(
  event_type : String,
  data : String,
  state : AnthropicStreamState
) -> Array[AssistantMessageEvent] {
  let trimmed = data.trim().to_string()
  if trimmed == "" {
    return []
  }

  let json = try @json.parse(trimmed) catch {
    _ => return []
  }

  let events : Array[AssistantMessageEvent] = []
  match event_type {
    "message_start" => anthropic_update_input_usage(state, json)
    "content_block_start" => {
      anthropic_ensure_started(state, events)
      anthropic_parse_content_block_start(json, state, events)
    }
    "content_block_delta" => {
      anthropic_ensure_started(state, events)
      anthropic_parse_content_block_delta(json, state, events)
    }
    "content_block_stop" => anthropic_parse_content_block_stop(json, state, events)
    "message_delta" => {
      anthropic_ensure_started(state, events)
      anthropic_parse_message_delta(json, state, events)
    }
    "message_stop" => ()
    _ => ()
  }
  events
}

///| Anthropic stop_reason 到通用 StopReason 的映射。
pub fn anthropic_stop_reason_to_stop_reason(reason : String) -> StopReason {
  match reason {
    "end_turn" => Stop
    "max_tokens" => Length
    "tool_use" => ToolUse
    _ => Error
  }
}

fn anthropic_message_json(message : Message) -> Json {
  match message {
    User(user) =>
      Json::object({
        "role": Json::string("user"),
        "content": anthropic_user_content_json(user.content),
      })
    Assistant(assistant) =>
      Json::object({
        "role": Json::string("assistant"),
        "content": anthropic_assistant_content_json(assistant.content),
      })
    ToolResult(result) => anthropic_tool_result_message_json(result)
  }
}

fn anthropic_user_content_json(content : Array[ContentBlock]) -> Json {
  let parts : Array[Json] = []
  for block in content {
    match block {
      Text(text) | Thinking(text) => parts.push(anthropic_text_json(text))
      Image(image) => parts.push(anthropic_image_json(image))
      ContentBlock::ToolCall(_) => ()
    }
  }
  Json::array(parts)
}

fn anthropic_assistant_content_json(content : Array[ContentBlock]) -> Json {
  let parts : Array[Json] = []
  for block in content {
    match block {
      Text(text) => parts.push(anthropic_text_json(text))
      Thinking(thinking) =>
        parts.push(Json::object({
          "type": Json::string("thinking"),
          "thinking": Json::string(thinking),
        }))
      Image(image) => parts.push(anthropic_image_json(image))
      ContentBlock::ToolCall(tool_call) => parts.push(anthropic_tool_use_json(tool_call))
    }
  }
  Json::array(parts)
}

fn anthropic_tool_result_message_json(result : ToolResultMessage) -> Json {
  let tool_result : Map[String, Json] = {
    "type": Json::string("tool_result"),
    "tool_use_id": Json::string(result.tool_call_id),
    "content": Json::string(anthropic_join_text_blocks(result.content)),
  }
  if result.error {
    tool_result["is_error"] = Json::boolean(true)
  }
  Json::object({
    "role": Json::string("user"),
    "content": Json::array([Json::object(tool_result)]),
  })
}

fn anthropic_text_json(text : String) -> Json {
  Json::object({
    "type": Json::string("text"),
    "text": Json::string(text),
  })
}

fn anthropic_image_json(image : ImageContent) -> Json {
  Json::object({
    "type": Json::string("image"),
    "source": Json::object({
      "type": Json::string("base64"),
      "media_type": Json::string(anthropic_mime_type_string(image.mime_type)),
      "data": Json::string(image.data),
    }),
  })
}

fn anthropic_tool_use_json(tool_call : ToolCall) -> Json {
  Json::object({
    "type": Json::string("tool_use"),
    "id": Json::string(tool_call.id),
    "name": Json::string(tool_call.name),
    "input": tool_call.arguments,
  })
}

fn anthropic_tool_definition_json(tool : Tool) -> Json {
  Json::object({
    "name": Json::string(tool.name),
    "description": Json::string(tool.description),
    "input_schema": tool.parameters,
  })
}

fn anthropic_mime_type_string(mime_type : ImageMimeType) -> String {
  match mime_type {
    Jpeg => "image/jpeg"
    Png => "image/png"
    Gif => "image/gif"
    Webp => "image/webp"
  }
}

fn anthropic_join_text_blocks(content : Array[ContentBlock]) -> String {
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

fn anthropic_max_tokens(options : StreamOptions) -> Int {
  match options.max_tokens {
    Some(max_tokens) => max_tokens
    None => 4096
  }
}

fn anthropic_thinking_json(options : StreamOptions) -> Json? {
  match options.thinking_mode {
    Some(Disabled) =>
      Some(Json::object({
        "type": Json::string("disabled"),
      }))
    Some(Enabled) | Some(Adaptive) => {
      let thinking : Map[String, Json] = {
        "type": Json::string("enabled"),
      }
      match options.thinking_budget_tokens {
        Some(budget_tokens) =>
          thinking["budget_tokens"] = Json::number(budget_tokens.to_double())
        None => ()
      }
      Some(Json::object(thinking))
    }
    None =>
      match options.thinking_budget_tokens {
        Some(budget_tokens) =>
          Some(Json::object({
            "type": Json::string("enabled"),
            "budget_tokens": Json::number(budget_tokens.to_double()),
          }))
        None => None
      }
  }
}

fn anthropic_ensure_started(
  state : AnthropicStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  if state.started {
    return
  }
  state.started = true
  events.push(Start(anthropic_build_assistant_message(state, Stop, None)))
}

fn anthropic_parse_content_block_start(
  json : Json,
  state : AnthropicStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  let index = anthropic_json_int_field(json, "index").unwrap_or(state.content.length())
  let content_block = match anthropic_json_object_field(json, "content_block") {
    Some(block) => block
    None => return
  }

  match anthropic_json_string_field(content_block, "type") {
    Some("text") => {
      anthropic_set_block(state, index, Text(""), TextBlock)
      events.push(TextStart(index))
      match anthropic_json_string_field(content_block, "text") {
        Some(text) if text.length() > 0 => {
          anthropic_append_text(state, index, text, false)
          events.push(TextDelta(index, text))
        }
        _ => ()
      }
    }
    Some("thinking") => {
      anthropic_set_block(state, index, Thinking(""), ThinkingBlock)
      events.push(ThinkingStart(index))
      match anthropic_json_string_field(content_block, "thinking") {
        Some(thinking) if thinking.length() > 0 => {
          anthropic_append_text(state, index, thinking, true)
          events.push(ThinkingDelta(index, thinking))
        }
        _ => ()
      }
    }
    Some("tool_use") => {
      let tool_call = anthropic_tool_call_from_start(content_block)
      state.current_tool_id = tool_call.id
      state.current_tool_name = tool_call.name
      state.tool_input_json = anthropic_tool_input_string(tool_call.arguments)
      state.current_tool_block_index = Some(index)
      anthropic_set_block(state, index, ContentBlock::ToolCall(tool_call), ToolBlock)
      events.push(ToolCallStart(index, tool_call))
    }
    _ => ()
  }
}

fn anthropic_parse_content_block_delta(
  json : Json,
  state : AnthropicStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  let index = anthropic_json_int_field(json, "index").unwrap_or(0)
  let delta = match anthropic_json_object_field(json, "delta") {
    Some(delta) => delta
    None => return
  }

  match anthropic_json_string_field(delta, "type") {
    Some("text_delta") =>
      match anthropic_json_string_field(delta, "text") {
        Some(text) if text.length() > 0 => {
          anthropic_append_text(state, index, text, false)
          events.push(TextDelta(index, text))
        }
        _ => ()
      }
    Some("thinking_delta") =>
      match anthropic_json_string_field(delta, "thinking") {
        Some(thinking) if thinking.length() > 0 => {
          anthropic_append_text(state, index, thinking, true)
          events.push(ThinkingDelta(index, thinking))
        }
        _ => ()
      }
    Some("input_json_delta") =>
      match anthropic_json_string_field(delta, "partial_json") {
        Some(partial_json) if partial_json.length() > 0 => {
          state.tool_input_json = state.tool_input_json + partial_json
          state.current_tool_block_index = Some(index)
          anthropic_update_tool_call(state, index, false)
          events.push(ToolCallDelta(index, partial_json))
        }
        _ => ()
      }
    _ => ()
  }
}

fn anthropic_parse_content_block_stop(
  json : Json,
  state : AnthropicStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  let index = anthropic_json_int_field(json, "index").unwrap_or(0)
  if index < 0 || index >= state.block_kinds.length() || state.block_closed[index] {
    return
  }

  state.block_closed[index] = true
  match state.block_kinds[index] {
    TextBlock =>
      match state.content[index] {
        Text(text) => events.push(TextEnd(index, text))
        _ => ()
      }
    ThinkingBlock =>
      match state.content[index] {
        Thinking(thinking) => events.push(ThinkingEnd(index, thinking))
        _ => ()
      }
    ToolBlock => {
      let tool_call = anthropic_complete_tool_call(state, index)
      state.content[index] = ContentBlock::ToolCall(tool_call)
      events.push(ToolCallEnd(index, tool_call))
      if state.current_tool_block_index == Some(index) {
        state.current_tool_block_index = None
      }
    }
    UnknownBlock => ()
  }
}

fn anthropic_parse_message_delta(
  json : Json,
  state : AnthropicStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  anthropic_update_output_usage(state, json)
  let delta = match anthropic_json_object_field(json, "delta") {
    Some(delta) => delta
    None => return
  }
  match anthropic_json_string_field(delta, "stop_reason") {
    Some(reason) if reason.length() > 0 => anthropic_emit_terminal_events(reason, state, events)
    _ => ()
  }
}

fn anthropic_set_block(
  state : AnthropicStreamState,
  index : Int,
  block : ContentBlock,
  kind : AnthropicBlockKind
) -> Unit {
  if index < state.content.length() {
    state.content[index] = block
    state.block_kinds[index] = kind
    state.block_closed[index] = false
    return
  }

  while state.content.length() < index {
    state.content.push(Text(""))
    state.block_kinds.push(UnknownBlock)
    state.block_closed.push(true)
  }

  state.content.push(block)
  state.block_kinds.push(kind)
  state.block_closed.push(false)
}

fn anthropic_append_text(
  state : AnthropicStreamState,
  index : Int,
  delta : String,
  thinking : Bool
) -> Unit {
  if index < 0 || index >= state.content.length() {
    return
  }

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

fn anthropic_tool_call_from_start(content_block : Json) -> ToolCall {
  let id = anthropic_json_string_field(content_block, "id").unwrap_or("")
  let name = anthropic_json_string_field(content_block, "name").unwrap_or("")
  let arguments = match anthropic_json_field(content_block, "input") {
    Some(input) => input
    None => Json::object({})
  }
  { id, name, arguments }
}

fn anthropic_tool_input_string(input : Json) -> String {
  match input {
    Object(obj) if obj.length() == 0 => ""
    _ => input.stringify(escape_slash=false)
  }
}

fn anthropic_update_tool_call(
  state : AnthropicStreamState,
  index : Int,
  is_complete : Bool
) -> Unit {
  if index < 0 || index >= state.content.length() {
    return
  }

  let tool_call = match state.content[index] {
    ContentBlock::ToolCall(tool_call) => {
      let id =
        if tool_call.id == "" {
          state.current_tool_id
        } else {
          tool_call.id
        }
      let name =
        if tool_call.name == "" {
          state.current_tool_name
        } else {
          tool_call.name
        }
      {
        id,
        name,
        arguments: anthropic_tool_arguments_json(state.tool_input_json, is_complete),
      }
    }
    _ => {
      id: state.current_tool_id,
      name: state.current_tool_name,
      arguments: anthropic_tool_arguments_json(state.tool_input_json, is_complete),
    }
  }
  state.content[index] = ContentBlock::ToolCall(tool_call)
}

fn anthropic_complete_tool_call(state : AnthropicStreamState, index : Int) -> ToolCall {
  anthropic_update_tool_call(state, index, true)
  match state.content[index] {
    ContentBlock::ToolCall(tool_call) => tool_call
    _ => {
      id: state.current_tool_id,
      name: state.current_tool_name,
      arguments: anthropic_tool_arguments_json(state.tool_input_json, true),
    }
  }
}

fn anthropic_tool_arguments_json(arguments_text : String, is_complete : Bool) -> Json {
  if arguments_text == "" {
    Json::object({})
  } else {
    try @json.parse(arguments_text) catch {
      _ =>
        if is_complete {
          Json::string(arguments_text)
        } else {
          Json::object({})
        }
    }
  }
}

fn anthropic_emit_terminal_events(
  reason : String,
  state : AnthropicStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  if state.terminal_emitted {
    return
  }

  for i = 0; i < state.block_kinds.length(); i = i + 1 {
    if state.block_closed[i] {
      continue
    }
    state.block_closed[i] = true
    match state.block_kinds[i] {
      TextBlock =>
        match state.content[i] {
          Text(text) => events.push(TextEnd(i, text))
          _ => ()
        }
      ThinkingBlock =>
        match state.content[i] {
          Thinking(thinking) => events.push(ThinkingEnd(i, thinking))
          _ => ()
        }
      ToolBlock => {
        let tool_call = anthropic_complete_tool_call(state, i)
        state.content[i] = ContentBlock::ToolCall(tool_call)
        events.push(ToolCallEnd(i, tool_call))
      }
      UnknownBlock => ()
    }
  }

  let stop_reason = anthropic_stop_reason_to_stop_reason(reason)
  let error_message = if stop_reason == Error { Some(reason) } else { None }
  let message = anthropic_build_assistant_message(state, stop_reason, error_message)
  state.terminal_emitted = true
  match stop_reason {
    Error => events.push(Error(stop_reason, message))
    _ => events.push(Done(stop_reason, message))
  }
}

fn anthropic_build_assistant_message(
  state : AnthropicStreamState,
  stop_reason : StopReason,
  error_message : String?
) -> AssistantMessage {
  {
    content: anthropic_visible_content(state),
    api: state.model.api,
    provider: state.model.provider,
    model: state.model.id,
    usage: anthropic_usage(state),
    stop_reason,
    error_message,
    timestamp: 0.0,
  }
}

fn anthropic_visible_content(state : AnthropicStreamState) -> Array[ContentBlock] {
  let content : Array[ContentBlock] = []
  for i = 0; i < state.content.length(); i = i + 1 {
    if state.block_kinds[i] != UnknownBlock {
      content.push(state.content[i])
    }
  }
  content
}

fn anthropic_usage(state : AnthropicStreamState) -> Usage {
  let input = state.input_tokens
  let output = state.output_tokens
  let total_tokens = input + output
  let input_cost = state.model.cost.input * input.to_double() / 1_000_000.0
  let output_cost = state.model.cost.output * output.to_double() / 1_000_000.0
  {
    input,
    output,
    cache_read: 0,
    cache_write: 0,
    total_tokens,
    cost: {
      input: input_cost,
      output: output_cost,
      cache_read: 0.0,
      cache_write: 0.0,
      total: input_cost + output_cost,
    },
  }
}

fn anthropic_update_input_usage(state : AnthropicStreamState, json : Json) -> Unit {
  let usage_json = match anthropic_usage_json(json) {
    Some(usage) => usage
    None => return
  }
  state.input_tokens = anthropic_json_int_field(usage_json, "input_tokens").unwrap_or(0)
}

fn anthropic_update_output_usage(state : AnthropicStreamState, json : Json) -> Unit {
  let usage_json = match anthropic_usage_json(json) {
    Some(usage) => usage
    None => return
  }
  state.output_tokens =
    anthropic_json_int_field(usage_json, "output_tokens").unwrap_or(state.output_tokens)
}

fn anthropic_usage_json(json : Json) -> Json? {
  match anthropic_json_object_field(json, "usage") {
    Some(usage) => Some(usage)
    None =>
      match anthropic_json_object_field(json, "message") {
        Some(message) => anthropic_json_object_field(message, "usage")
        None => None
      }
  }
}

fn anthropic_json_field(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    obj.get(key)
  } else {
    None
  }
}

fn anthropic_json_string_field(json : Json, key : String) -> String? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(String(value)) => Some(value)
      _ => None
    }
  } else {
    None
  }
}

fn anthropic_json_int_field(json : Json, key : String) -> Int? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Number(value, ..)) => Some(value.to_int())
      _ => None
    }
  } else {
    None
  }
}

fn anthropic_json_object_field(json : Json, key : String) -> Json? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(value) =>
        if value is Object(_) {
          Some(value)
        } else {
          None
        }
      None => None
    }
  } else {
    None
  }
}
