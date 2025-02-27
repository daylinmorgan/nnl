import std/[json, os, unittest, strformat]
import nnl


const
  pkg = "moe-67324a"
  fixtures = currentSourcePath().parentDir / "fixtures"
  nimbleLockFilePath =  fixtures / &"{pkg}-nimble.lock"
  nixLockFilePath = fixtures / &"{pkg}-lock.json"
  nixLockFileGitPath = fixtures / &"{pkg}-prefetch-git-all-lock.json"
  nixLockFileGitJsonyParsetomlPath = fixtures / &"{pkg}-prefetch-git-jsony_parsetoml.json"

suite "integration":
  test "moe":
    let c = NnlContext(lockFile: nimbleLockFilePath)
    let lockFileResult = parseFile(nixLockFilePath)
    check lockFileResult == generateLockFile c
  test "moe-git":
    let c = NnlContext(lockFile: nimbleLockFilePath, gitAll: true)
    let lockFileResult = parseFile(nixLockFileGitPath)
    check lockFileResult == generateLockFile c
  test "moe-git-jsony-parsetoml":
    let c = NnlContext(lockFile: nimbleLockFilePath, gitDeps: @["jsony", "parsetoml"])
    let lockFileResult = parseFile(nixLockFileGitJsonyParsetomlPath)
    check lockFileResult == generateLockFile c
