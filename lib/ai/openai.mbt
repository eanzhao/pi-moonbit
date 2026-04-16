struct OpenAiToolCallState {
  stream_index : Int
  block_index : Int
  mut id : String
  mut name : String
  mut arguments_text : String
  mut ended : Bool
}

///| OpenAI Chat Completions 流式解析状态。
pub(all) struct OpenAiStreamState {
  model : Model
  mut started : Bool
  mut content : Array[ContentBlock]
  mut text_index : Int?
  mut text_ended : Bool
  mut tool_calls : Array[OpenAiToolCallState]
  mut usage : Usage
  mut terminal_emitted : Bool
}

///| 创建新的 OpenAI 流式解析状态。
pub fn OpenAiStreamState::new(model : Model) -> OpenAiStreamState {
  {
    model,
    started: false,
    content: [],
    text_index: None,
    text_ended: false,
    tool_calls: [],
    usage: Usage::zero(),
    terminal_emitted: false,
  }
}

///| 将通用上下文映射为 OpenAI Chat Completions 请求体。
pub fn build_openai_request_body(model : Model, context : Context, options : StreamOptions) -> Json {
  let messages : Array[Json] = []
  match context.system_prompt {
    Some(system_prompt) =>
      messages.push(Json::object({
        "role": Json::string("system"),
        "content": Json::string(system_prompt),
      }))
    None => ()
  }
  for message in context.messages {
    messages.push(openai_message_json(message))
  }

  let body : Map[String, Json] = {
    "model": Json::string(model.id),
    "messages": Json::array(messages),
    "stream": Json::boolean(true),
    "max_tokens": Json::number(openai_max_tokens(model, options).to_double()),
    "stream_options": Json::object({
      "include_usage": Json::boolean(true),
    }),
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
    body["tools"] = Json::array(context.tools.map(openai_tool_definition_json))
  }
  Json::object(body)
}

///| 解析一行 OpenAI SSE 数据并转换为内部流式事件。
pub fn parse_openai_sse_line(
  line : String,
  state : OpenAiStreamState
) -> Array[AssistantMessageEvent] {
  let trimmed = line.trim().to_string()
  if trimmed == "" || !trimmed.has_prefix("data:") {
    return []
  }

  let payload = trimmed[5:].trim().to_string()
  if payload == "[DONE]" {
    if state.started && !state.terminal_emitted {
      let events : Array[AssistantMessageEvent] = []
      openai_emit_terminal_events("stop", state, events)
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
    events.push(Start(openai_build_assistant_message(state, Stop, None)))
  }

  openai_update_usage(state, json)

  match openai_first_choice(json) {
    Some(choice) => {
      match json_object_field(choice, "delta") {
        Some(delta) => openai_parse_delta(delta, state, events)
        None => ()
      }
      match json_string_field(choice, "finish_reason") {
        Some(reason) => openai_emit_terminal_events(reason, state, events)
        None => ()
      }
    }
    None => ()
  }

  events
}

///| OpenAI finish_reason 到通用 StopReason 的映射。
pub fn openai_finish_reason_to_stop_reason(reason : String) -> StopReason {
  match reason {
    "stop" => Stop
    "length" => Length
    "tool_calls" | "function_call" => ToolUse
    _ => Error
  }
}

fn openai_message_json(message : Message) -> Json {
  match message {
    User(user) =>
      Json::object({
        "role": Json::string("user"),
        "content": openai_user_content_json(user.content),
      })
    Assistant(assistant) => openai_assistant_message_json(assistant)
    ToolResult(result) =>
      Json::object({
        "role": Json::string("tool"),
        "tool_call_id": Json::string(result.tool_call_id),
        "content": openai_tool_result_content_json(result.content),
      })
  }
}

fn openai_assistant_message_json(message : AssistantMessage) -> Json {
  let tool_calls = openai_assistant_tool_calls(message.content)
  let content = openai_assistant_content_json(message.content)
  if tool_calls.length() == 0 {
    Json::object({
      "role": Json::string("assistant"),
      "content": content,
    })
  } else {
    Json::object({
      "role": Json::string("assistant"),
      "content": content,
      "tool_calls": Json::array(tool_calls),
    })
  }
}

fn openai_user_content_json(content : Array[ContentBlock]) -> Json {
  let parts : Array[Json] = []
  let text_parts : Array[String] = []
  let mut has_image = false
  for block in content {
    match block {
      Text(text) | Thinking(text) => {
        text_parts.push(text)
        parts.push(Json::object({
          "type": Json::string("text"),
          "text": Json::string(text),
        }))
      }
      Image(image) => {
        has_image = true
        parts.push(Json::object({
          "type": Json::string("image_url"),
          "image_url": Json::object({
            "url": Json::string(openai_image_url(image)),
          }),
        }))
      }
      ContentBlock::ToolCall(_) => ()
    }
  }
  if !has_image && text_parts.length() == 1 {
    Json::string(text_parts[0])
  } else if !has_image {
    Json::string(text_parts.join("\n\n"))
  } else {
    Json::array(parts)
  }
}

fn openai_tool_result_content_json(content : Array[ContentBlock]) -> Json {
  Json::string(openai_join_text_blocks(content))
}

fn openai_assistant_content_json(content : Array[ContentBlock]) -> Json {
  let text = openai_join_text_blocks(content)
  if text == "" {
    Json::null()
  } else {
    Json::string(text)
  }
}

fn openai_assistant_tool_calls(content : Array[ContentBlock]) -> Array[Json] {
  let tool_calls : Array[Json] = []
  for block in content {
    match block {
      ContentBlock::ToolCall(tool_call) => tool_calls.push(openai_tool_call_json(tool_call))
      _ => ()
    }
  }
  tool_calls
}

fn openai_tool_definition_json(tool : Tool) -> Json {
  Json::object({
    "type": Json::string("function"),
    "function": Json::object({
      "name": Json::string(tool.name),
      "description": Json::string(tool.description),
      "parameters": tool.parameters,
    }),
  })
}

fn openai_tool_call_json(tool_call : ToolCall) -> Json {
  Json::object({
    "id": Json::string(tool_call.id),
    "type": Json::string("function"),
    "function": Json::object({
      "name": Json::string(tool_call.name),
      "arguments": Json::string(tool_call.arguments.stringify(escape_slash=false)),
    }),
  })
}

fn openai_image_url(image : ImageContent) -> String {
  match image.url {
    Some(url) => url
    None =>
      "data:\{openai_mime_type_string(image.mime_type)};base64,\{image.data}"
  }
}

fn openai_mime_type_string(mime_type : ImageMimeType) -> String {
  match mime_type {
    Jpeg => "image/jpeg"
    Png => "image/png"
    Gif => "image/gif"
    Webp => "image/webp"
  }
}

fn openai_join_text_blocks(content : Array[ContentBlock]) -> String {
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

fn openai_max_tokens(model : Model, options : StreamOptions) -> Int {
  match options.max_tokens {
    Some(max_tokens) => max_tokens
    None => model.max_tokens
  }
}

fn openai_first_choice(json : Json) -> Json? {
  match json_array_field(json, "choices") {
    Some(choices) if choices.length() > 0 => Some(choices[0])
    _ => None
  }
}

fn openai_parse_delta(
  delta : Json,
  state : OpenAiStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  match json_string_field(delta, "content") {
    Some(text) if text.length() > 0 => {
      let index = openai_ensure_text_block(state, events)
      openai_append_text(state, index, text)
      events.push(TextDelta(index, text))
    }
    _ => ()
  }

  match json_array_field(delta, "tool_calls") {
    Some(tool_calls) =>
      for tool_call_chunk in tool_calls {
        openai_parse_tool_call_chunk(tool_call_chunk, state, events)
      }
    None => ()
  }
}

fn openai_ensure_text_block(
  state : OpenAiStreamState,
  events : Array[AssistantMessageEvent]
) -> Int {
  match state.text_index {
    Some(index) => index
    None => {
      let index = state.content.length()
      state.text_index = Some(index)
      state.text_ended = false
      state.content.push(Text(""))
      events.push(TextStart(index))
      index
    }
  }
}

fn openai_append_text(state : OpenAiStreamState, index : Int, delta : String) -> Unit {
  let current = match state.content[index] {
    Text(text) => text
    _ => ""
  }
  state.content[index] = Text(current + delta)
}

fn openai_parse_tool_call_chunk(
  tool_call_chunk : Json,
  state : OpenAiStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  let stream_index = json_int_field(tool_call_chunk, "index").unwrap_or(0)
  let state_index = openai_get_or_create_tool_call_state(stream_index, state)
  let block_index = state.tool_calls[state_index].block_index
  let was_empty =
    state.tool_calls[state_index].id == "" &&
    state.tool_calls[state_index].name == "" &&
    state.tool_calls[state_index].arguments_text == ""

  match json_string_field(tool_call_chunk, "id") {
    Some(id) if id.length() > 0 => state.tool_calls[state_index].id = id
    _ => ()
  }

  let mut arguments_delta = ""
  match json_object_field(tool_call_chunk, "function") {
    Some(function_json) => {
      match json_string_field(function_json, "name") {
        Some(name) if name.length() > 0 =>
          state.tool_calls[state_index].name = state.tool_calls[state_index].name + name
        _ => ()
      }
      match json_string_field(function_json, "arguments") {
        Some(arguments) if arguments.length() > 0 => {
          state.tool_calls[state_index].arguments_text =
            state.tool_calls[state_index].arguments_text + arguments
          arguments_delta = arguments
        }
        _ => ()
      }
    }
    None => ()
  }

  let partial_tool_call = openai_tool_call_from_state(state.tool_calls[state_index], false)
  state.content[block_index] = ContentBlock::ToolCall(partial_tool_call)

  if was_empty {
    events.push(ToolCallStart(block_index, partial_tool_call))
  }
  if arguments_delta.length() > 0 {
    events.push(ToolCallDelta(block_index, arguments_delta))
  }
}

fn openai_get_or_create_tool_call_state(stream_index : Int, state : OpenAiStreamState) -> Int {
  for i = 0; i < state.tool_calls.length(); i = i + 1 {
    if state.tool_calls[i].stream_index == stream_index {
      return i
    }
  }

  let block_index = state.content.length()
  let tool_call_state : OpenAiToolCallState = {
    stream_index,
    block_index,
    id: "",
    name: "",
    arguments_text: "",
    ended: false,
  }
  state.tool_calls.push(tool_call_state)
  state.content.push(ContentBlock::ToolCall({
    id: "",
    name: "",
    arguments: Json::object({}),
  }))
  state.tool_calls.length() - 1
}

fn openai_tool_call_from_state(
  tool_call_state : OpenAiToolCallState,
  is_complete : Bool
) -> ToolCall {
  {
    id: tool_call_state.id,
    name: tool_call_state.name,
    arguments: openai_arguments_json(tool_call_state.arguments_text, is_complete),
  }
}

fn openai_arguments_json(arguments_text : String, is_complete : Bool) -> Json {
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

fn openai_emit_terminal_events(
  reason : String,
  state : OpenAiStreamState,
  events : Array[AssistantMessageEvent]
) -> Unit {
  if state.terminal_emitted {
    return
  }

  match state.text_index {
    Some(index) if !state.text_ended => {
      let text = match state.content[index] {
        Text(value) => value
        _ => ""
      }
      state.text_ended = true
      events.push(TextEnd(index, text))
    }
    _ => ()
  }

  for i = 0; i < state.tool_calls.length(); i = i + 1 {
    if !state.tool_calls[i].ended {
      state.tool_calls[i].ended = true
      let tool_call = openai_tool_call_from_state(state.tool_calls[i], true)
      state.content[state.tool_calls[i].block_index] = ContentBlock::ToolCall(tool_call)
      events.push(ToolCallEnd(state.tool_calls[i].block_index, tool_call))
    }
  }

  let stop_reason = openai_finish_reason_to_stop_reason(reason)
  let error_message = if stop_reason == Error { Some(reason) } else { None }
  let message = openai_build_assistant_message(state, stop_reason, error_message)
  state.terminal_emitted = true
  match stop_reason {
    Error => events.push(Error(stop_reason, message))
    _ => events.push(Done(stop_reason, message))
  }
}

fn openai_build_assistant_message(
  state : OpenAiStreamState,
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

fn openai_update_usage(state : OpenAiStreamState, json : Json) -> Unit {
  let usage_json = match json_object_field(json, "usage") {
    Some(usage) => usage
    None => return
  }

  let input = json_int_field(usage_json, "prompt_tokens").unwrap_or(0)
  let output = json_int_field(usage_json, "completion_tokens").unwrap_or(0)
  let total_tokens = json_int_field(usage_json, "total_tokens").unwrap_or(input + output)

  let input_cost = state.model.cost.input * input.to_double() / 1_000_000.0
  let output_cost = state.model.cost.output * output.to_double() / 1_000_000.0
  state.usage = {
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

fn json_string_field(json : Json, key : String) -> String? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(String(value)) => Some(value)
      _ => None
    }
  } else {
    None
  }
}

fn json_int_field(json : Json, key : String) -> Int? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Number(value, ..)) => Some(value.to_int())
      _ => None
    }
  } else {
    None
  }
}

fn json_array_field(json : Json, key : String) -> Array[Json]? {
  if json is Object(obj) {
    match obj.get(key) {
      Some(Array(items)) => Some(items.copy())
      _ => None
    }
  } else {
    None
  }
}

fn json_object_field(json : Json, key : String) -> Json? {
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
