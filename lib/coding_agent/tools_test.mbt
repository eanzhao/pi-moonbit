test "write and read tools operate on in-memory workspace" {
  let workspace = Ref::new(InMemoryWorkspace::new())
  let runtime = in_memory_workspace_runtime(workspace)
  let write_tool = create_write_tool(runtime)
  let read_tool = create_read_tool(runtime)

  let write_result = (write_tool.execute)(
    "tool-write",
    Json::object({
      "path": Json::string("notes.md"),
      "content": Json::string("hello from moonbit"),
    }),
    @agent.AgentToolUpdateHandler(fn(_partial) { }),
  )
  assert_true(write_result is Ok(_))

  let read_result = (read_tool.execute)(
    "tool-read",
    Json::object({ "path": Json::string("notes.md") }),
    @agent.AgentToolUpdateHandler(fn(_partial) { }),
  )
  assert_true(read_result is Ok(_))
  match read_result.unwrap().content[0] {
    @ai.ContentBlock::Text(text) => assert_eq(text, "hello from moonbit")
    _ => fail("expected read tool text result")
  }
}

test "edit tool replaces the first matching chunk" {
  let workspace = Ref::new(InMemoryWorkspace::new(files=[
    { path: "draft.txt", content: "hello world hello" },
  ]))
  let runtime = in_memory_workspace_runtime(workspace)
  let edit_tool = create_edit_tool(runtime)

  let edit_result = (edit_tool.execute)(
    "tool-edit",
    Json::object({
      "path": Json::string("draft.txt"),
      "old_text": Json::string("hello"),
      "new_text": Json::string("hi"),
    }),
    @agent.AgentToolUpdateHandler(fn(_partial) { }),
  )
  assert_true(edit_result is Ok(_))
  assert_eq(workspace.val.get_content("draft.txt"), Some("hi world hello"))

  let missing_result = (edit_tool.execute)(
    "tool-edit-miss",
    Json::object({
      "path": Json::string("draft.txt"),
      "old_text": Json::string("missing"),
      "new_text": Json::string("unused"),
    }),
    @agent.AgentToolUpdateHandler(fn(_partial) { }),
  )
  assert_true(missing_result is Err(_))
}

test "bash tool surfaces non-zero exit code as error" {
  let bash_tool = create_bash_tool({
    run: fn(command) {
      Ok({
        stdout: "",
        stderr: "boom from " + command,
        exit_code: 1,
        cancelled: false,
        truncated: false,
        full_output_path: None,
      })
    },
  })

  let result = (bash_tool.execute)(
    "tool-bash",
    Json::object({ "command": Json::string("false") }),
    @agent.AgentToolUpdateHandler(fn(_partial) { }),
  )
  assert_true(result is Err(_))
  assert_true(result.unwrap_err().contains("code 1"))
}
