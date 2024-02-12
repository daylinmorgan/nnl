import std/[json, os, unittest]
import nnl

const nimbleLockFilePath = currentSourcePath().parentDir /
    "ttop-v1.2.8-nimble.lock"
const nixLockFilePath = currentSourcePath().parentDir / "ttop-v1.2.8-lock.json"

let c = NnlContext(lockFile: nimbleLockFilePath)
let data = parseFile(nixLockFilePath)

suite "integration":
  test "ttop":
    check data == generateLockFile(c)

