test "system prompt is platform neutral and includes events skills and memory" {
  let prompt = build_mom_system_prompt(
    "/workspace",
    { id: "C123", name: "build", kind: ChannelKind::Channel },
    "### Global Workspace Memory\nUse apply_patch for edits.",
    SandboxConfig::Docker({ container: "mom-sandbox" }),
    {
      adapter: "slack-acme",
      channels: [{ id: "C123", name: "build", kind: ChannelKind::Channel }],
      users: [{ id: "U1", username: "mario", display_name: Some("Mario") }],
    },
    skills=[
      {
        name: "gmail",
        description: "Read and send Gmail",
        file_path: "/workspace/skills/gmail/SKILL.md",
        base_dir: "/workspace/skills/gmail",
        source: "workspace",
      },
    ],
  )

  assert_true(prompt.contains("Use standard markdown"))
  assert_true(prompt.contains("@mario"))
  assert_true(prompt.contains("#build"))
  assert_true(prompt.contains("slack-acme/C123"))
  assert_true(prompt.contains("Read and send Gmail"))
  assert_true(prompt.contains("\"type\":\"periodic\""))
}
