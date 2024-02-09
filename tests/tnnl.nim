import std/[unittest, os]
import nnl

const lockFilePath = currentSourcePath().parentDir / "nimlangserver-nimble.lock"
let c = NnlContext(lockFile: lockFilePath)

suite "basic":
  test "parsing":
    discard parseDepsFromLockFile(c.lockFile)

