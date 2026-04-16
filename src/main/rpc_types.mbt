pub(all) enum RpcCommandType {
  Prompt
  Steer
  FollowUp
  Abort
  SetModel
  SetThinking
  SessionInfo
  ListTools
  Quit
} derive(Eq)

pub(all) struct RpcCommand {
  id : String?
  command : String
  data : Json?
} derive(Eq, ToJson, FromJson)

pub(all) struct RpcResponse {
  id : String?
  command : String
  success : Bool
  data : Json?
  error : String?
} derive(Eq, ToJson, FromJson)

pub(all) struct RpcEvent {
  event_type : String
  data : Json?
} derive(Eq, ToJson, FromJson)

pub fn parse_rpc_command(line : String) -> Result[RpcCommand, String] {
  if line.trim() == "" {
    return Err("command line is empty")
  }
  let json = try @json.parse(line) catch {
    _ => return Err("command must be valid JSON")
  } noraise {
    value => value
  }
  let command : RpcCommand = try @json.from_json(json) catch {
    error => return Err(error.to_string())
  } noraise {
    value => value
  }
  match rpc_command_type_from_name(command.command) {
    Some(command_type) =>
      Ok({
        id: command.id,
        command: rpc_command_type_name(command_type),
        data: command.data,
      })
    None => Err("unknown rpc command: " + command.command)
  }
}

pub fn rpc_response_json(response : RpcResponse) -> String {
  Json::object({
    "id": rpc_optional_string_json_field(response.id),
    "command": Json::string(response.command),
    "success": Json::boolean(response.success),
    "data": rpc_optional_json_field(response.data),
    "error": rpc_optional_string_json_field(response.error),
  }).stringify(escape_slash=false)
}

pub fn rpc_event_json(event : RpcEvent) -> String {
  Json::object({
    "event_type": Json::string(event.event_type),
    "data": rpc_optional_json_field(event.data),
  }).stringify(escape_slash=false)
}

fn rpc_command_type_from_name(name : String) -> RpcCommandType? {
  let normalized = name.trim().to_lower().replace(old="-", new="_")
  match normalized {
    "prompt" => Some(RpcCommandType::Prompt)
    "steer" => Some(RpcCommandType::Steer)
    "follow_up" => Some(RpcCommandType::FollowUp)
    "abort" => Some(RpcCommandType::Abort)
    "set_model" => Some(RpcCommandType::SetModel)
    "set_thinking" => Some(RpcCommandType::SetThinking)
    "session_info" => Some(RpcCommandType::SessionInfo)
    "list_tools" => Some(RpcCommandType::ListTools)
    "quit" => Some(RpcCommandType::Quit)
    _ => None
  }
}

fn rpc_command_type_name(command_type : RpcCommandType) -> String {
  match command_type {
    RpcCommandType::Prompt => "prompt"
    RpcCommandType::Steer => "steer"
    RpcCommandType::FollowUp => "follow_up"
    RpcCommandType::Abort => "abort"
    RpcCommandType::SetModel => "set_model"
    RpcCommandType::SetThinking => "set_thinking"
    RpcCommandType::SessionInfo => "session_info"
    RpcCommandType::ListTools => "list_tools"
    RpcCommandType::Quit => "quit"
  }
}

fn rpc_optional_string_json_field(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}

fn rpc_optional_json_field(value : Json?) -> Json {
  match value {
    Some(json) => json
    None => Json::null()
  }
}
