test "diff returns full patch for first frame" {
  let patch = diff_lines([], ["a", "b"])
  match patch {
    Full(lines) => {
      assert_eq(lines.length(), 2)
      assert_eq(lines[0], "a")
      assert_eq(lines[1], "b")
    }
    _ => fail("expected full patch")
  }
}

test "diff returns noop when frames are identical" {
  let patch = diff_lines(["same"], ["same"])
  match patch {
    Noop => ()
    _ => fail("expected noop patch")
  }
}

test "diff rewrites from first changed line" {
  let patch = diff_lines(["a", "b", "c"], ["a", "x", "c", "d"])
  match patch {
    Update(line_patch) => {
      assert_eq(line_patch.start_line, 1)
      assert_eq(line_patch.lines.length(), 3)
      assert_eq(line_patch.lines[0], "x")
      assert_eq(line_patch.lines[1], "c")
      assert_eq(line_patch.lines[2], "d")
      assert_eq(line_patch.cleared_line_count, 0)
    }
    _ => fail("expected update patch")
  }
}

test "diff clears tail when new frame is shorter" {
  let patch = diff_lines(["a", "b", "c"], ["a"])
  match patch {
    Update(line_patch) => {
      assert_eq(line_patch.start_line, 1)
      assert_eq(line_patch.lines.length(), 0)
      assert_eq(line_patch.cleared_line_count, 2)
    }
    _ => fail("expected update patch")
  }
}
