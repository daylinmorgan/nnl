import std/[json, os, unittest, strformat]
import nnl


const
  pkg = "moe-67324a"
  fixtures = currentSourcePath().parentDir / "fixtures"
  nimbleLockFilePath =  fixtures / &"{pkg}-nimble.lock"
  nixLockFilePath = fixtures / &"{pkg}-lock.json"
  nixLockFileGitPath = fixtures / &"{pkg}-force-git-lock.json"


suite "integration":
  test "moe":
    let c = NnlContext(lockFile: nimbleLockFilePath)
    let lockFileResult = parseFile(nixLockFilePath)
    check lockFileResult == generateLockFile c
  test "moe-git":
    let c = NnlContext(lockFile: nimbleLockFilePath, forceGit: true)
    let lockFileResult = parseFile(nixLockFileGitPath)
    check lockFileResult == generateLockFile c

