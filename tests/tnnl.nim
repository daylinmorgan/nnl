import std/[json, os, unittest]
import nnl

const nimbleLockFilePath = currentSourcePath().parentDir /
    "ttop-v1.2.8-nimble.lock"
const nixLockFilePath = currentSourcePath().parentDir / "ttop-v1.2.8-lock.json"
const nixLockFileGitPath = currentSourcePath().parentDir / "ttop-v1.2.8-force-git-lock.json"


suite "integration":
  test "ttop":
    let c = NnlContext(lockFile: nimbleLockFilePath)
    let lockFileResult = parseFile(nixLockFilePath)
    check lockFileResult == generateLockFile c
  test "ttop-git":
    let c = NnlContext(lockFile: nimbleLockFilePath, forceGit: true)
    let lockFileResult = parseFile(nixLockFileGitPath)
    check lockFileResult == generateLockFile c

