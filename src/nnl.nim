import std/[
  httpclient, json, logging, os, osproc,
  options, parsecfg, strutils, tables, uri
]

var consoleLog = newConsoleLogger(useStdErr = true)
addHandler(consoleLog)

type
  NimbleMetadata = object
    srcDir: string

  NnlContext* = object
    lockFile*: string
    forceGit*: bool
    output: string

  Checksums = object
    sha1: string

  Dependency = object
    version, vcsRevision, url, downloadMethod: string
    dependencies: seq[string]
    checksums: Checksums

  Dependencies = Table[string, Dependency]

  Fod = object
    `method`, path, rev, sha256, srcDir, url, subDir: string
    fetchSubmodules, leaveDotGit: Option[bool]
    packages: seq[string]

  PrefetchData = object
    `method`, sha256, path, url: string
    fetchSubmodules, leaveDotGit: Option[bool]

  PrefetchDataGit = object
    url, rev, date, path, sha256: string
    fetchLFS, fetchSubmodules, deepClone, leaveDotGit: bool

proc errLogQuit(args: varargs[string, `$`]) =
  error args.join(" ")
  quit 1

proc dumpQuit(args: varargs[string, `$`]) =
  stderr.writeLine args.join(" ")
  quit 1


proc `%`*(o: Fod): JsonNode =
  ## Construct JsonNode from Fod.
  result = newJObject()
  for k, v in o.fieldPairs:
    when compiles(v.isSome):
      if v.isSome:
        result[k] = %(get v)
    else:
      result[k] = %v

proc findNimbleFile(p: string): string =
  var candidates: seq[string]
  for kind, path in walkDir(p):
    case kind:
      of pcFile, pcLinkToFile:
        if path.endsWith(".nimble"):
          candidates.add path
      else: discard
  # nimble will probably prevent this,
  # but not sure about atlas or bespoke builds
  if candidates.len == 1:
    return candidates[0]
  elif candidates.len > 1:
    error "found multiple nimble files: " & candidates.join(", ")
  else:
    error "failed to find a nimble file"

proc getNimbleMetadata(nimbleFilePath: string): NimbleMetadata =
  let nimbleFile = findNimbleFile(nimbleFilePath)
  let nimbleCfg = loadConfig(nimbleFile)
  result.srcDir = nimbleCfg.getSectionValue("", "srcDir", "")

proc `<-`(p1: var PrefetchData, p2: PrefetchDataGit) =
  p1.sha256 = p2.sha256
  p1.path = p2.path
  p1.fetchSubmodules = some p2.fetchSubmodules
  p1.leaveDotGit = some p2.leaveDotGit

proc `<-`(f: var Fod, d: Dependency) =
  f.url = d.url
  f.rev = d.vcsRevision

proc `<-`(f: var Fod, p: PrefetchData) =
  f.`method` = p.`method`
  f.path = p.path
  f.sha256 = p.sha256
  f.url = p.url
  if p.fetchSubmodules.isSome():
    f.fetchSubmodules = p.fetchSubmodules
  if p.leaveDotGit.isSome:
    f.leaveDotGit = p.leaveDotGit

proc `<-`(f: var Fod, m: NimbleMetadata) =
  f.srcDir = m.srcDir

proc parseDepsFromLockFile*(lockFile: string): Dependencies =
  let lockData = parseFile(lockFile)
  if "packages" in lockData:
    result = lockData["packages"].to(Dependencies)

proc parsePrefetchGit(prefetchJsonStr: string): PrefetchData =
  var prefetchData: PrefetchDataGit
  try:
    prefetchData = parseJson(prefetchJsonStr).to(PrefetchDataGit)
  except JsonParsingError:
    error "faild to parse nix-prefetch-git json"
    dumpQuit prefetchJsonStr
  result <- prefetchData

proc getArchiveUri(gitUrl, rev: string): Uri =
  result = parseUri(gitUrl)
  result.scheme = "https"
  result.path.removeSuffix ".git"
  result.path = result.path / "archive" / rev & ".tar.gz"

proc testUri(uri: Uri): HttpCode =
  var resp: Response
  let client = newHttpClient()
  try:
    resp = head(client, $uri)
  finally:
    client.close()
  result = resp.code


proc nixPrefetchUrl(url: string): PrefetchData =
  debug "prefetching archive: ", url
  let cmd = [
    "nix-prefetch-url",
    url,
    "--type sha256 --print-path --unpack --name source"].join(" ")
  let (output, code) = execCmdEx(cmd, options = {poUsePath})
  let lines = output.strip().splitLines()
  if code != 0:
    error "failed to prefetch: ", url
  if lines.len != 2:
    error "expected 2 lines from nix-prefetch-url output, got ", lines.len
  if code != 0 or lines.len != 2:
    dumpQuit output

  result.`method` = "fetchzip"
  result.sha256 = lines[0]
  result.path = lines[1]
  result.url = url

proc nixPrefetchGit(url: string, rev: string): PrefetchData =
  debug "prefetching repo: ", url
  let cmd = [
    "nix-prefetch-git",
    "--url", url, "--rev", rev, "--fetch-submodules --quiet"
  ].join(" ")
  let (output, code) = execCmdEx(cmd, options = {poUsePath})
  if code != 0:
    error "failed to prefetch: ", url
    dumpQuit output
  result = parsePrefetchGit output
  result.`method` = "git"
  result.url = url


proc fetch(c: NnlContext, f: var Fod) =
  var uri = parseUri(f.url)
  uri.scheme.removePrefix("git+")
  if uri.query != "":
    if uri.query.startsWith("subdir="):
      f.subDir = uri.query[7 .. ^1]
    uri.query = ""
  let cloneUrl = $uri
  let archiveUrl = $getArchiveUri(f.url, f.rev)
  let prefetchData =
    if not c.forceGit and testUri(uri) in {Http200, Http302}:
      nixPrefetchUrl archiveUrl
    else:
      nixPrefetchGit cloneUrl, f.rev
  f <- prefetchData
  f <- getNimbleMetadata(f.path)

proc genFod(c: NnlContext, package: string, d: Dependency): Fod =
  result = Fod()
  result.packages = @[package]
  result <- d
  fetch c, result

proc generateLockFile*(c: NnlContext): JsonNode =
  info "parsing: ", c.lockFile
  if not fileExists c.lockFile:
    errLogQuit c.lockFile, "does not exist"
  var fods: seq[Fod]
  let dependencies = parseDepsFromLockFile c.lockFile
  for name, dep in dependencies:
    if name.toLowerAscii() notin ["nim", "compiler"]:
      fods.add genFod(c, name, dep)
  return ( %* {"depends": fods})

proc checkDeps() =
  if (findExe "nix-prefetch-url") == "":
    errLogQuit "nix-prefetch-url not found"
  if (findExe "nix-prefetch-git") == "":
    errLogQuit "nix-prefetch-git not found"

proc nnl(c: NnlContext) =
  checkDeps()
  let data = pretty(generateLockFile c)
  if c.output != "":
    writeFile(c.output, data)
  else:
    stdout.writeLine(data)


when isMainModule:
  import std/parseopt
  const usage = """
nim nix lock
------------
nimble.lock -> lock.json
generate a lock file for
packaging nim modules with nix

usage:
  nnl <path/to/nimble.lock> [opts]

options:
  -h, --help   show this help
  -o, --output path/to/lock.json (default stdout)
  --force-git  force use of nix-prefetch-git
"""
  var c = NnlContext()
  var posArgs: seq[string]
  for kind, key, val in getopt(
    shortNoVal = {'h'}, longNoVal = @["help", "force-git"]
  ):
    case kind
    of cmdArgument:
      posArgs.add key
    of cmdShortOption, cmdLongOption:
      case key
      of "h", "help":
        echo usage; quit 0
      of "force-git":
        c.forceGit = true
      of "o", "output":
        c.output = val
    of cmdEnd: discard

  case posArgs.len
  of 1:
    c.lockFile = posArgs[0]
  of 0:
    errLogQuit "expected path to nimble.lock"
  else:
    errLogQuit "expected one positional argument, but got `" &
      posArgs.join(" ") & "`"
  nnl c
