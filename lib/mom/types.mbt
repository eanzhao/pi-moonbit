pub(all) enum ChannelKind {
  Channel
  Dm
  Group
} derive(Eq)

pub(all) struct ChannelSender {
  id : String
  username : String
  display_name : String?
  is_bot : Bool
} derive(Eq)

pub(all) struct ChannelAttachment {
  filename : String
  local_path : String
  mime_type : String?
  size : Int?
} derive(Eq)

pub(all) struct ChannelMessage {
  id : String
  channel_id : String
  timestamp : String
  sender : ChannelSender
  text : String
  raw_text : String?
  attachments : Array[ChannelAttachment]
  is_mention : Bool
  reply_to : String?
  metadata : Json?
} derive(Eq)

pub(all) struct ChannelInfo {
  id : String
  name : String
  kind : ChannelKind
} derive(Eq)

pub(all) struct UserInfo {
  id : String
  username : String
  display_name : String?
} derive(Eq)

pub(all) struct ChannelContext {
  adapter : String
  channels : Array[ChannelInfo]
  users : Array[UserInfo]
} derive(Eq)

pub(all) struct AdapterOutboundMessage {
  channel_id : String
  text : String
  reply_to : String?
} derive(Eq)

pub(all) struct AdapterSentMessage {
  id : String
  channel_id : String
  text : String
  reply_to : String?
} derive(Eq)

pub(all) struct MomSkill {
  name : String
  description : String
  file_path : String
  base_dir : String
  source : String
} derive(Eq)

pub(all) struct DockerSandboxConfig {
  container : String
} derive(Eq)

pub(all) enum SandboxConfig {
  Host
  Docker(DockerSandboxConfig)
} derive(Eq)

pub(all) struct ImmediateEvent {
  channel_id : String
  text : String
} derive(Eq)

pub(all) struct OneShotEvent {
  channel_id : String
  text : String
  at : String
} derive(Eq)

pub(all) struct PeriodicEvent {
  channel_id : String
  text : String
  schedule : String
  timezone : String
} derive(Eq)

pub(all) enum MomEvent {
  Immediate(ImmediateEvent)
  OneShot(OneShotEvent)
  Periodic(PeriodicEvent)
} derive(Eq)

pub(all) struct MomEventFile {
  filename : String
  content : String
  modified_at : String?
} derive(Eq)

pub(all) struct MomEventTrigger {
  filename : String
  event : MomEvent
  message : String
  delete_after : Bool
} derive(Eq)

pub(all) struct MomScheduledOneShot {
  filename : String
  event : OneShotEvent
} derive(Eq)

pub(all) struct MomRegisteredPeriodic {
  filename : String
  event : PeriodicEvent
} derive(Eq)

pub(all) enum MomEventPlan {
  Trigger(MomEventTrigger)
  ScheduleOneShot(MomScheduledOneShot)
  RegisterPeriodic(MomRegisteredPeriodic)
  Delete(String)
  Invalid(String, String)
} derive(Eq)

pub(all) struct MomEventWorkspaceRuntime {
  read_text : (String) -> Result[String, String]
  list_files : (String) -> Result[Array[String], String]
  read_modified_at : (String) -> Result[String?, String]
  delete_file : (String) -> Result[Unit, String]
}

pub(all) struct MomEventHost {
  workspace_dir : String
  started_at : String
  mut observed_plans : Array[(String, MomEventPlan)]
  mut scheduled_one_shots : Array[MomScheduledOneShot]
  mut registered_periodics : Array[MomRegisteredPeriodic]
}

pub(all) struct MomEventHostSync {
  changed_plans : Array[MomEventPlan]
  added_one_shots : Array[MomScheduledOneShot]
  removed_one_shots : Array[MomScheduledOneShot]
  added_periodics : Array[MomRegisteredPeriodic]
  removed_periodics : Array[MomRegisteredPeriodic]
} derive(Eq)

pub(all) struct MomPendingEventFile {
  filename : String
  due_at_ms : UInt64
} derive(Eq)

pub(all) struct MomEventDebounceQueue {
  debounce_ms : UInt64
  mut pending : Array[MomPendingEventFile]
}

pub(all) struct MomScheduledTimer {
  filename : String
  event : OneShotEvent
  due_at_ms : UInt64
} derive(Eq)

pub(all) struct MomOneShotTimerRegistry {
  mut timers : Array[MomScheduledTimer]
}

pub(all) struct MomPeriodicRegistry {
  mut entries : Array[MomRegisteredPeriodic]
}

pub(all) struct MomEventLoop {
  host : MomEventHost
  debounce_queue : MomEventDebounceQueue
  one_shot_registry : MomOneShotTimerRegistry
  periodic_registry : MomPeriodicRegistry
}

pub(all) struct MomRunner {
  event_loop : MomEventLoop
  mut handle_state : MomEventHandleState
}

pub(all) struct MomEventHandleState {
  watched_dir : String?
  wakeup_due_at_ms : UInt64?
  registered_periodics : Array[MomRegisteredPeriodic]
} derive(Eq)

pub(all) struct MomEventHandlePlan {
  state : MomEventHandleState
  watch_changed : Bool
  wakeup_changed : Bool
  added_periodics : Array[MomRegisteredPeriodic]
  removed_periodics : Array[MomRegisteredPeriodic]
} derive(Eq)

pub(all) enum MomEventHandleOp {
  SetWatchDir(String?)
  SetWakeup(UInt64?)
  RegisterPeriodic(MomRegisteredPeriodic)
  RemovePeriodic(String)
} derive(Eq)

pub(all) struct MomEventTickResult {
  flushed_files : Array[String]
  workspace_results : Array[MomEventDispatchResult]
  one_shot_results : Array[MomEventDispatchResult]
} derive(Eq)

pub(all) struct MomRunnerSyncResult {
  sync : MomEventHostSync
  handle_plan : MomEventHandlePlan
} derive(Eq)

pub(all) struct MomRunnerTurnResult {
  run : MomRunResult
  handle_plan : MomEventHandlePlan
} derive(Eq)

pub(all) struct MomRunnerTickResult {
  tick : MomEventTickResult
  handle_plan : MomEventHandlePlan
} derive(Eq)

pub(all) struct MomRunnerPeriodicResult {
  dispatch : MomEventDispatchResult
  handle_plan : MomEventHandlePlan
} derive(Eq)

pub(all) enum MomEventDispatchResult {
  Triggered(MomRunResult)
  ScheduledOneShot(MomScheduledOneShot)
  RegisteredPeriodic(MomRegisteredPeriodic)
  Deleted(String)
  Invalid(String, String)
} derive(Eq)

pub(all) enum MomEventDispatchError {
  RuntimeFailed(String)
  MissingPeriodic(String)
  InvalidChannelId(String)
  AdapterMismatch(String)
  AgentFailed(MomAgentError)
} derive(Eq)

pub(all) enum MomRunnerError {
  EventRuntimeFailed(String)
  HandleRuntimeFailed(String)
  EventDispatchFailed(MomEventDispatchError)
  AgentFailed(MomAgentError)
} derive(Eq)

pub(all) struct ChannelLog {
  adapter : String
  channel_id : String
  messages : Array[ChannelMessage]
} derive(Eq)

pub(all) struct ChannelLogMetadata {
  adapter : String
  channel_id : String
  message_count : Int
  last_message_at : String?
  preview : String
} derive(Eq)

pub(all) struct InMemoryChannelStore {
  mut logs : Array[ChannelLog]
}

pub(all) struct MomAgentRuntime {
  workspace_runtime : @coding_agent.WorkspaceRuntime
  command_runtime : @coding_agent.CommandRuntime
  now_iso : () -> String
  stream_fn : @agent.AgentStreamFn?
}

pub(all) struct MomAgentConfig {
  workspace_dir : String
  sandbox : SandboxConfig
  model : @ai.Model
  thinking_level : @agent.AgentThinkingLevel
  global_memory : String?
  tools : Array[@agent.AgentTool]
  extensions : Array[@coding_agent.CodingExtension]
  runtime : MomAgentRuntime
}

pub(all) struct MomRunResult {
  stop_reason : @ai.StopReason
  error_message : String?
  assistant_text : String
  usage : @ai.Usage?
} derive(Eq)

pub(all) enum MomAgentError {
  SessionInitFailed(String)
  WorkspaceReadFailed(String)
  WorkspaceWriteFailed(String)
  AdapterFailed(String)
  AgentError(@agent.AgentError)
} derive(Eq)

pub(all) struct MomChannelSession {
  adapter : String
  channel : ChannelInfo
  session : @coding_agent.AgentSession
  mut running : Bool
}

pub(all) struct MomAgent {
  config : MomAgentConfig
  mut channel_store : InMemoryChannelStore
  mut sessions : Array[Ref[MomChannelSession]]
}

pub(all) struct InMemoryPlatformAdapter {
  adapter_name : String
  channels : Array[ChannelInfo]
  users : Array[UserInfo]
  mut started : Bool
  mut sent_messages : Array[AdapterSentMessage]
  mut observed_events : Array[String]
}

pub(all) struct InMemoryEventHandleRuntime {
  mut watched_dir : String?
  mut wakeup_due_at_ms : UInt64?
  mut registered_periodics : Array[MomRegisteredPeriodic]
  mut operations : Array[MomEventHandleOp]
}

pub(open) trait MomEventHandleRuntime {
  set_watch_dir(Self, String?) -> Result[Unit, String]
  set_wakeup_due_at_ms(Self, UInt64?) -> Result[Unit, String]
  register_periodic(Self, MomRegisteredPeriodic) -> Result[Unit, String]
  remove_periodic(Self, String) -> Result[Unit, String]
}

pub(open) trait PlatformAdapter {
  name(Self) -> String
  start(Self) -> Unit = _
  stop(Self) -> Unit = _
  get_channels(Self) -> Array[ChannelInfo]
  get_users(Self) -> Array[UserInfo]
  send_message(Self, AdapterOutboundMessage) -> Result[AdapterSentMessage, String]
  handle_agent_event(Self, ChannelMessage, @agent.AgentEvent) -> Unit = _
}
