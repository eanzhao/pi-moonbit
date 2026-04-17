///| Amazon Bedrock Converse Stream API 请求构建器。
///
/// Bedrock 的 Converse API 是跨模型统一接口，支持 Claude/Llama/Mistral 等。
/// 使用 AWS SigV4 认证（实际签名在 host 层，此模块只负责请求体）。
pub fn build_bedrock_request_body(model : Model, context : Context, options : StreamOptions) -> Json {
  let messages : Array[Json] = []
  for message in context.messages {
    messages.push(bedrock_message_json(message))
  }
  let body : Map[String, Json] = {
    "messages": Json::array(messages),
    "inferenceConfig": Json::object({
      "maxTokens": Json::number(bedrock_max_tokens(model, options).to_double()),
    }),
  }
  match context.system_prompt {
    Some(system_prompt) if system_prompt.length() > 0 =>
      body["system"] = Json::array([Json::object({
        "text": Json::string(system_prompt),
      })])
    _ => ()
  }
  match options.temperature {
    Some(t) => bedrock_inference_config(body)["temperature"] = Json::number(t)
    None => ()
  }
  match options.top_p {
    Some(p) => bedrock_inference_config(body)["topP"] = Json::number(p)
    None => ()
  }
  if context.tools.length() > 0 {
    let tool_specs : Array[Json] = []
    for tool in context.tools {
      tool_specs.push(Json::object({
        "toolSpec": Json::object({
          "name": Json::string(tool.name),
          "description": Json::string(tool.description),
          "inputSchema": Json::object({ "json": tool.parameters }),
        }),
      }))
    }
    body["toolConfig"] = Json::object({ "tools": Json::array(tool_specs) })
  }
  Json::object(body)
}

fn bedrock_inference_config(body : Map[String, Json]) -> Map[String, Json] {
  match body.get("inferenceConfig") {
    Some(Object(cfg)) => cfg
    _ => {
      let cfg : Map[String, Json] = {}
      body["inferenceConfig"] = Json::object(cfg)
      cfg
    }
  }
}

fn bedrock_message_json(message : Message) -> Json {
  match message {
    User(user) => Json::object({
      "role": Json::string("user"),
      "content": Json::array(user.content.map(bedrock_content_block_json)),
    })
    Assistant(assistant) => Json::object({
      "role": Json::string("assistant"),
      "content": Json::array(assistant.content.map(bedrock_content_block_json)),
    })
    ToolResult(result) => Json::object({
      "role": Json::string("user"),
      "content": Json::array([Json::object({
        "toolResult": Json::object({
          "toolUseId": Json::string(result.tool_call_id),
          "content": Json::array(result.content.map(bedrock_tool_result_content)),
          "status": Json::string(if result.error { "error" } else { "success" }),
        }),
      })]),
    })
  }
}

fn bedrock_content_block_json(block : ContentBlock) -> Json {
  match block {
    Text(text) => Json::object({ "text": Json::string(text) })
    Thinking(text) => Json::object({
      "reasoningContent": Json::object({
        "reasoningText": Json::object({ "text": Json::string(text) }),
      }),
    })
    ContentBlock::ToolCall(tc) => Json::object({
      "toolUse": Json::object({
        "toolUseId": Json::string(tc.id),
        "name": Json::string(tc.name),
        "input": tc.arguments,
      }),
    })
    Image(_) => Json::object({ "text": Json::string("[image]") })
  }
}

fn bedrock_tool_result_content(block : ContentBlock) -> Json {
  match block {
    Text(text) => Json::object({ "text": Json::string(text) })
    _ => Json::object({ "text": Json::string("") })
  }
}

fn bedrock_max_tokens(model : Model, options : StreamOptions) -> Int {
  match options.max_tokens {
    Some(m) => m
    None => model.max_tokens
  }
}

///| Bedrock Converse stop reason 到通用 StopReason 的映射。
pub fn bedrock_stop_reason_to_stop_reason(reason : String) -> StopReason {
  match reason {
    "end_turn" => Stop
    "max_tokens" => Length
    "tool_use" => ToolUse
    "stop_sequence" => Stop
    _ => Error
  }
}
