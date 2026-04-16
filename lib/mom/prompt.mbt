pub fn build_mom_system_prompt(
  workspace_path : String,
  channel : ChannelInfo,
  memory : String,
  sandbox : SandboxConfig,
  context : ChannelContext,
  skills? : Array[MomSkill] = []
) -> String {
  let qualified_id = qualified_channel_id(context.adapter, channel.id)
  let channel_path = workspace_channel_dir(workspace_path, context.adapter, channel.id)
  let scratch_path = workspace_channel_scratch_dir(workspace_path, context.adapter, channel.id)
  let env_description = match sandbox {
    Host =>
      "You are running directly on the host machine.\n" +
      "- Working directory for bash: " + scratch_path + "\n" +
      "- Be careful with system modifications."
    Docker(docker) =>
      "You are running inside a Docker container.\n" +
      "- Container name: " + docker.container + "\n" +
      "- Working directory for bash: " + scratch_path + "\n" +
      "- Prefer installing tools inside the container instead of assuming they already exist."
  }

  [
    "You are mom, a chat bot assistant. Be concise. No emojis.",
    "",
    "## Text Formatting",
    "Use standard markdown: **bold**, *italic*, `code`, ```block```, [text](url).",
    "For mentions, write @username and let the adapter translate it.",
    "",
    "## Users",
    format_users_for_prompt(context.users),
    "",
    "## Channels",
    format_channels_for_prompt(context.channels),
    "",
    "## Environment",
    env_description,
    "",
    "## Workspace Layout",
    workspace_path + "/",
    "├── MEMORY.md",
    "├── skills/",
    "├── events/",
    "└── channels/",
    "    └── " + context.adapter + "/",
    "        └── " + channel.id + "/",
    "            ├── MEMORY.md",
    "            ├── log.jsonl",
    "            ├── context.jsonl",
    "            ├── attachments/",
    "            ├── scratch/",
    "            └── skills/",
    "",
    "Current channel path: " + channel_path,
    "Qualified channel id for events: " + qualified_id,
    "",
    "## Memory",
    if memory.length() > 0 { memory } else { "(no working memory yet)" },
    "",
    "## Skills",
    format_skills_for_prompt(skills),
    "",
    "## Events",
    "Create JSON files in " + workspace_events_dir(workspace_path) + "/ to wake yourself up later.",
    "Immediate:",
    "{\"type\":\"immediate\",\"channelId\":\"" + qualified_id + "\",\"text\":\"New webhook payload arrived\"}",
    "One-shot:",
    "{\"type\":\"one-shot\",\"channelId\":\"" + qualified_id + "\",\"text\":\"Follow up tomorrow\",\"at\":\"2026-04-17T09:00:00+08:00\"}",
    "Periodic:",
    "{\"type\":\"periodic\",\"channelId\":\"" + qualified_id + "\",\"text\":\"Post daily summary\",\"schedule\":\"0 9 * * 1-5\",\"timezone\":\"Asia/Singapore\"}",
    "",
    "Search log.jsonl for older history. context.jsonl is the compact LLM-visible context snapshot.",
  ].join("\n")
}

pub fn format_skills_for_prompt(skills : Array[MomSkill]) -> String {
  if skills.length() == 0 {
    return "(no skills installed yet)"
  }

  let lines : Array[String] = []
  for skill in skills {
    lines.push(
      "- " + skill.name +
      " (" + skill.source + "): " + skill.description +
      " | file: " + skill.file_path,
    )
  }
  lines.join("\n")
}

fn format_users_for_prompt(users : Array[UserInfo]) -> String {
  if users.length() == 0 {
    return "(no users loaded)"
  }

  let lines : Array[String] = []
  for user in users {
    let suffix = match user.display_name {
      Some(value) if value.length() > 0 => " (" + value + ")"
      _ => ""
    }
    lines.push("@" + user.username + "\t" + user.id + suffix)
  }
  lines.join("\n")
}

fn format_channels_for_prompt(channels : Array[ChannelInfo]) -> String {
  if channels.length() == 0 {
    return "(no channels loaded)"
  }

  let lines : Array[String] = []
  for channel in channels {
    lines.push(prompt_channel_label(channel) + "\t" + channel.id)
  }
  lines.join("\n")
}

fn prompt_channel_label(channel : ChannelInfo) -> String {
  match channel.kind {
    Channel => "#" + channel.name
    Dm => "@" + channel.name
    Group => channel.name
  }
}
