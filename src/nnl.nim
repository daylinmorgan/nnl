import std/[strutils, json, logging, os]

var consoleLog = newConsoleLogger()
addHandler(consoleLog)

type
  NnlContext* = object
    lockFile*: string
  Checksums = object
    sha1: string
  Dependency = object
    version, vcsRevision, url, downloadMethod: string
    dependencies: seq[string]
    checksums: Checksums

proc errQuit(args: varargs[string, `$`]) =
  error args.join(" ")
  quit 1

proc parseDepsFromLockFile*(lockFile: string): seq[Dependency] =
  let lockData = parseFile(lockFile)
  if "packages" in lockData:
    for name, data in lockData["packages"]:
      result.add data.to(Dependency)

proc generateLockFile*(c: NnlContext) =
  info "parsing: ", c.lockFile

  if not fileExists c.lockFile:
    errQuit c.lockFile, "does not exist"

  let dependencies = parseDepsFromLockFile c.lockFile
  echo dependencies

when isMainModule:
  import std/parseopt
  const usage = """
nim nix lock
------------
generate a lock file for
packaging nim modules with nix

usage:
  nnl <path/to/nimble.lock> [opts]

options:
  -h, --help show this help
"""
  var c = NnlContext()
  var posArgs: seq[string]
  for kind, key, val in getopt(shortNoVal = {'h'}, longNoVal = @["help"]):
    case kind
    of cmdArgument:
      posArgs.add key
    of cmdShortOption, cmdLongOption:
      case key
      of "h", "help":
        echo usage; quit 0
    of cmdEnd: discard

  case posArgs.len
  of 0:
    error "expected path to nimble.lock"
    quit 1
  of 1:
    c.lockFile = posArgs[0]
  else:
    error "expected one positional argument, but got `" & posArgs.join(" ") & "`"
    quit 1

  generateLockFile c
