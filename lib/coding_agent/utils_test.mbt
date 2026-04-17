test "normalize_path resolves . and .." {
  assert_eq(normalize_path("/a/b/../c"), "/a/c")
  assert_eq(normalize_path("a/./b/c"), "a/b/c")
  assert_eq(normalize_path("a//b"), "a/b")
  assert_eq(normalize_path("/"), "/")
  assert_eq(normalize_path(""), ".")
  assert_eq(normalize_path("."), ".")
}

test "is_absolute_path checks" {
  assert_true(is_absolute_path("/foo/bar"))
  assert_false(is_absolute_path("foo/bar"))
  assert_false(is_absolute_path("./foo"))
  assert_true(is_absolute_path("C:/path"))
}

test "join_path combines" {
  assert_eq(join_path("/a/b", "c"), "/a/b/c")
  assert_eq(join_path("/a/b/", "c"), "/a/b/c")
  assert_eq(join_path("/a", "/absolute"), "/absolute")
  assert_eq(join_path("", "child"), "child")
}

test "basename extracts file name" {
  assert_eq(basename("/a/b/c.txt"), "c.txt")
  assert_eq(basename("c.txt"), "c.txt")
  assert_eq(basename("/"), "/")
  assert_eq(basename("/a/b/"), "b")
}

test "extension extracts suffix" {
  assert_eq(extension("file.txt"), ".txt")
  assert_eq(extension("archive.tar.gz"), ".gz")
  assert_eq(extension("noext"), "")
  assert_eq(extension(".hidden"), "")
}

test "parent_path returns directory" {
  assert_eq(parent_path("/a/b/c"), Some("/a/b"))
  assert_eq(parent_path("/a"), Some("/"))
  assert_eq(parent_path("/"), None)
  assert_eq(parent_path("."), None)
}

test "mime_type_for_path detects types" {
  assert_eq(mime_type_for_path("foo.txt"), "text/plain")
  assert_eq(mime_type_for_path("foo.json"), "application/json")
  assert_eq(mime_type_for_path("foo.png"), "image/png")
  assert_eq(mime_type_for_path("foo.mbt"), "text/x-moonbit")
  assert_eq(mime_type_for_path("foo.unknown"), "application/octet-stream")
}

test "is_text_mime_type classifies" {
  assert_true(is_text_mime_type("text/plain"))
  assert_true(is_text_mime_type("application/json"))
  assert_false(is_text_mime_type("image/png"))
  assert_false(is_text_mime_type("application/pdf"))
}

test "git commands are shell-safe" {
  let cmd = git_status_command("/path/with spaces/here")
  assert_true(cmd.contains("git status --porcelain"))
  assert_true(cmd.contains("'/path/with spaces/here'"))
}

test "parse_git_status extracts entries" {
  let output = " M file1.txt\n?? file2.txt\nA  file3.txt"
  let entries = parse_git_status(output)
  assert_eq(entries.length(), 3)
  assert_eq(entries[0].status, " M")
  assert_eq(entries[0].path, "file1.txt")
  assert_eq(entries[1].status, "??")
  assert_eq(entries[2].status, "A ")
}

test "parse_frontmatter extracts metadata and body" {
  let text = "---\nname: Test Skill\ndescription: does something\n---\nbody content\nline 2"
  let result = parse_frontmatter(text)
  assert_eq(result.metadata.get("name"), Some("Test Skill"))
  assert_eq(result.metadata.get("description"), Some("does something"))
  assert_eq(result.body, "body content\nline 2")
}

test "parse_frontmatter handles missing frontmatter" {
  let text = "plain content"
  let result = parse_frontmatter(text)
  assert_eq(result.metadata.size(), 0)
  assert_eq(result.body, "plain content")
}

test "parse_frontmatter strips quoted values" {
  let text = "---\nname: \"quoted\"\nother: 'single'\n---\n"
  let result = parse_frontmatter(text)
  assert_eq(result.metadata.get("name"), Some("quoted"))
  assert_eq(result.metadata.get("other"), Some("single"))
}
