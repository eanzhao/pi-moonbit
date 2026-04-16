priv enum RpcDispatchResult {
  Continue(RpcResponse)
  Exit(RpcResponse)
}

pub fn run_rpc_mode(app : CliApp) -> Int {
  let listener = app.session.agent.subscribe(fn(event) {
    rpc_write_event(app.runtime, rpc_event_from_agent_event(event))
  })

  while true {
    match (app.runtime.read_line)("") {
      None => {
        app.session.agent.unsubscribe(listener)
        return 0
      }
      Some(line) =>
        match parse_rpc_command(line) {
          Err(message) =>
            rpc_write_response(app.runtime, rpc_invalid_response(message))
          Ok(command) =>
            match rpc_dispatch_command(app, command) {
              Continue(response) => rpc_write_response(app.runtime, response)
              Exit(response) => {
                rpc_write_response(app.runtime, response)
                app.session.agent.unsubscribe(listener)
                return 0
              }
            }
        }
    }
  }

  app.session.agent.unsubscribe(listener)
  0
}

fn rpc_dispatch_command(app : CliApp, command : RpcCommand) -> RpcDispatchResult {
  match command.command {
    "prompt" => Continue(rpc_run_prompt_command(app, command))
    "steer" => Continue(rpc_run_steer_command(app, command))
    "follow_up" => Continue(rpc_run_follow_up_command(app, command))
    "abort" => Continue(rpc_run_abort_command(app, command))
    "set_model" => Continue(rpc_run_set_model_command(app, command))
    "set_thinking" => Continue(rpc_run_set_thinking_command(app, command))
    "session_info" => Continue(rpc_run_session_info_command(app, command))
    "list_tools" => Continue(rpc_run_list_tools_command(app, command))
    "quit" => Exit(rpc_ok_response(command))
    _ => Continue(rpc_error_response(command, "unknown rpc command: " + command.command))
  }
}

fn rpc_run_prompt_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  let text = match rpc_required_string_field(command.data, "text") {
    Ok(value) => value
    Err(message) => return rpc_error_response(command, message)
  }
  match app.session.prompt_text(text) {
    Err(error) => rpc_error_response(command, agent_error_text(error))
    Ok(_) =>
      match persist_session(app) {
        Err(message) => rpc_error_response(command, message)
        Ok(_) =>
          match last_assistant_message(app.session.session_manager.build_transcript_messages()) {
            Some(message) if assistant_message_failed(message) =>
              rpc_error_response(command, assistant_error_text(message))
            _ => rpc_ok_response(command)
          }
      }
  }
}

fn rpc_run_steer_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  let text = match rpc_required_string_field(command.data, "text") {
    Ok(value) => value
    Err(message) => return rpc_error_response(command, message)
  }
  app.session.steer_text(text)
  rpc_ok_response(command)
}

fn rpc_run_follow_up_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  let text = match rpc_required_string_field(command.data, "text") {
    Ok(value) => value
    Err(message) => return rpc_error_response(command, message)
  }
  app.session.follow_up_text(text)
  rpc_ok_response(command)
}

fn rpc_run_abort_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  app.session.agent.abort()
  rpc_ok_response(command)
}

fn rpc_run_set_model_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  let next_id = match rpc_required_string_field(command.data, "model_id") {
    Ok(value) => value
    Err(message) => return rpc_error_response(command, message)
  }
  ignore(app.session.set_model(rpc_model_with_id(app.session.agent.state.model, next_id)))
  match persist_session(app) {
    Ok(_) =>
      rpc_ok_response(
        command,
        data=Some(Json::object({ "model": Json::string(next_id) })),
      )
    Err(message) => rpc_error_response(command, message)
  }
}

fn rpc_run_set_thinking_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  let raw_level = match rpc_required_string_field(command.data, "level") {
    Ok(value) => value
    Err(message) => return rpc_error_response(command, message)
  }
  let level = match parse_thinking_level(raw_level) {
    Some(value) => value
    None => return rpc_error_response(command, "unknown thinking level: " + raw_level)
  }
  ignore(app.session.set_thinking_level(level))
  match persist_session(app) {
    Ok(_) =>
      rpc_ok_response(
        command,
        data=Some(Json::object({ "thinking": Json::string(raw_level) })),
      )
    Err(message) => rpc_error_response(command, message)
  }
}

fn rpc_run_session_info_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  rpc_ok_response(command, data=Some(rpc_session_info_json(app)))
}

fn rpc_run_list_tools_command(app : CliApp, command : RpcCommand) -> RpcResponse {
  let tools : Array[Json] = []
  for tool in app.session.agent.state.tools {
    tools.push(Json::string(tool.name))
  }
  rpc_ok_response(command, data=Some(Json::object({ "tools": Json::array(tools) })))
}

fn rpc_invalid_response(message : String) -> RpcResponse {
  { id: None, command: "invalid", success: false, data: None, error: Some(message) }
}

fn rpc_ok_response(command : RpcCommand, data? : Json? = None) -> RpcResponse {
  { id: command.id, command: command.command, success: true, data, error: None }
}

fn rpc_error_response(command : RpcCommand, message : String) -> RpcResponse {
  {
    id: command.id,
    command: command.command,
    success: false,
    data: None,
    error: Some(message),
  }
}

fn rpc_required_string_field(data : Json?, key : String) -> Result[String, String] {
  guard data is Some(Object(obj)) else {
    return Err("missing data." + key)
  }
  match obj.get(key) {
    Some(String(value)) => Ok(value)
    _ => Err("missing data." + key)
  }
}

fn rpc_model_with_id(current : @ai.Model, next_id : String) -> @ai.Model {
  {
    id: next_id,
    name: next_id,
    api: current.api,
    provider: current.provider,
    base_url: current.base_url,
    reasoning: current.reasoning,
    input_modalities: current.input_modalities.copy(),
    cost: current.cost,
    context_window: current.context_window,
    max_tokens: current.max_tokens,
  }
}

fn rpc_session_info_json(app : CliApp) -> Json {
  Json::object({
    "session_path": rpc_optional_string_json(app.session_path),
    "model": Json::string(app.session.agent.state.model.id),
    "thinking": Json::string(thinking_level_name(app.session.agent.state.thinking_level)),
    "entry_count": Json::number(app.session.session_manager.get_entries().length().to_double()),
  })
}

fn rpc_write_response(runtime : CliHostRuntime, response : RpcResponse) -> Unit {
  (runtime.stdout_write)(rpc_response_json(response) + "\n")
}

fn rpc_write_event(runtime : CliHostRuntime, event : RpcEvent) -> Unit {
  (runtime.stdout_write)(rpc_event_json(event) + "\n")
}

fn rpc_event_from_agent_event(event : @agent.AgentEvent) -> RpcEvent {
  match event {
    @agent.AgentEvent::AgentStart => { event_type: "agent_start", data: None }
    @agent.AgentEvent::AgentEnd(messages) =>
      {
        event_type: "agent_end",
        data: Some(Json::object({ "messages": Json::array(rpc_messages_json(messages)) })),
      }
    @agent.AgentEvent::TurnStart => { event_type: "turn_start", data: None }
    @agent.AgentEvent::TurnEnd(payload) =>
      {
        event_type: "turn_end",
        data: Some(Json::object({
          "message": payload.message.to_json(),
          "tool_results": Json::array(rpc_tool_result_messages_json(payload.tool_results)),
        })),
      }
    @agent.AgentEvent::MessageStart(message) =>
      { event_type: "message_start", data: Some(Json::object({ "message": message.to_json() })) }
    @agent.AgentEvent::MessageUpdate(payload) =>
      {
        event_type: "message_update",
        data: Some(Json::object({
          "message": payload.message.to_json(),
          "assistant_event": rpc_assistant_event_json(payload.assistant_event),
        })),
      }
    @agent.AgentEvent::MessageEnd(message) =>
      { event_type: "message_end", data: Some(Json::object({ "message": message.to_json() })) }
    @agent.AgentEvent::ToolExecutionStart(payload) =>
      {
        event_type: "tool_execution_start",
        data: Some(Json::object({
          "tool_call_id": Json::string(payload.tool_call_id),
          "tool_name": Json::string(payload.tool_name),
          "args": payload.args,
        })),
      }
    @agent.AgentEvent::ToolExecutionUpdate(payload) =>
      {
        event_type: "tool_execution_update",
        data: Some(Json::object({
          "tool_call_id": Json::string(payload.tool_call_id),
          "tool_name": Json::string(payload.tool_name),
          "args": payload.args,
          "partial_result": rpc_tool_result_json(payload.partial_result),
        })),
      }
    @agent.AgentEvent::ToolExecutionEnd(payload) =>
      {
        event_type: "tool_execution_end",
        data: Some(Json::object({
          "tool_call_id": Json::string(payload.tool_call_id),
          "tool_name": Json::string(payload.tool_name),
          "result": rpc_tool_result_json(payload.result),
          "is_error": Json::boolean(payload.is_error),
        })),
      }
  }
}

fn rpc_tool_result_json(result : @agent.AgentToolResult) -> Json {
  Json::object({
    "content": Json::array(rpc_content_blocks_json(result.content)),
    "details": result.details,
  })
}

fn rpc_assistant_event_json(event : @ai.AssistantMessageEvent) -> Json {
  match event {
    @ai.AssistantMessageEvent::Start(message) =>
      Json::object({
        "type": Json::string("start"),
        "message": message.to_json(),
      })
    @ai.AssistantMessageEvent::TextStart(index) =>
      Json::object({
        "type": Json::string("text_start"),
        "index": Json::number(index.to_double()),
      })
    @ai.AssistantMessageEvent::TextDelta(index, delta) =>
      Json::object({
        "type": Json::string("text_delta"),
        "index": Json::number(index.to_double()),
        "delta": Json::string(delta),
      })
    @ai.AssistantMessageEvent::TextEnd(index, text) =>
      Json::object({
        "type": Json::string("text_end"),
        "index": Json::number(index.to_double()),
        "text": Json::string(text),
      })
    @ai.AssistantMessageEvent::ThinkingStart(index) =>
      Json::object({
        "type": Json::string("thinking_start"),
        "index": Json::number(index.to_double()),
      })
    @ai.AssistantMessageEvent::ThinkingDelta(index, delta) =>
      Json::object({
        "type": Json::string("thinking_delta"),
        "index": Json::number(index.to_double()),
        "delta": Json::string(delta),
      })
    @ai.AssistantMessageEvent::ThinkingEnd(index, text) =>
      Json::object({
        "type": Json::string("thinking_end"),
        "index": Json::number(index.to_double()),
        "text": Json::string(text),
      })
    @ai.AssistantMessageEvent::ToolCallStart(index, tool_call) =>
      Json::object({
        "type": Json::string("tool_call_start"),
        "index": Json::number(index.to_double()),
        "tool_call": tool_call.to_json(),
      })
    @ai.AssistantMessageEvent::ToolCallDelta(index, delta) =>
      Json::object({
        "type": Json::string("tool_call_delta"),
        "index": Json::number(index.to_double()),
        "delta": Json::string(delta),
      })
    @ai.AssistantMessageEvent::ToolCallEnd(index, tool_call) =>
      Json::object({
        "type": Json::string("tool_call_end"),
        "index": Json::number(index.to_double()),
        "tool_call": tool_call.to_json(),
      })
    @ai.AssistantMessageEvent::Done(stop_reason, message) =>
      Json::object({
        "type": Json::string("done"),
        "stop_reason": stop_reason.to_json(),
        "message": message.to_json(),
      })
    @ai.AssistantMessageEvent::Error(stop_reason, message) =>
      Json::object({
        "type": Json::string("error"),
        "stop_reason": stop_reason.to_json(),
        "message": message.to_json(),
      })
  }
}

fn rpc_messages_json(messages : Array[@ai.Message]) -> Array[Json] {
  let items : Array[Json] = []
  for message in messages {
    items.push(message.to_json())
  }
  items
}

fn rpc_tool_result_messages_json(messages : Array[@ai.ToolResultMessage]) -> Array[Json] {
  let items : Array[Json] = []
  for message in messages {
    items.push(message.to_json())
  }
  items
}

fn rpc_content_blocks_json(content : Array[@ai.ContentBlock]) -> Array[Json] {
  let items : Array[Json] = []
  for block in content {
    items.push(block.to_json())
  }
  items
}

fn rpc_optional_string_json(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}
