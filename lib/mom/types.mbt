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
