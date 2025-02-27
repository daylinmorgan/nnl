import std/[
  httpclient, json, logging, os, osproc,
  options, parsecfg, strformat, sets, strutils,
  tables, uri, sequtils,
]
import hwylterm, hwylterm/logging

let logger = newHwylConsoleLogger(
  fmtPrefix = $bb"[b magenta]nnl[/]",
  levelThreshold = lvlInfo
)
addHandler logger

const
  nimblePath {.strdefine.} = "nimble"
  nixPrefetchGitPath {.strdefine.} = "nix-prefetch-git"
  nixPrefetchUrlPath {.strdefine.} = "nix-prefetch-url"

type
  NimbleMetadata = object
    srcDir: string

  NnlContext* = object
    lockFile*: string
    prefetchGit*: seq[string]
    prefetchGitAll*: bool
    output: string

  Checksums = object
    sha1: string

  Dependency = object
    version, vcsRevision, url, downloadMethod: string
    dependencies: seq[string]
    checksums: Checksums

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

proc fatalQuit(args: varargs[string, `$`]) =
  fatal args.join(" ")
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
    case kind
    of pcFile, pcLinkToFile:
      if path.endsWith(".nimble"):
        candidates.add path
    else:
      discard
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
  if p.fetchSubmodules.isSome:
    f.fetchSubmodules = p.fetchSubmodules
  if p.leaveDotGit.isSome:
    f.leaveDotGit = p.leaveDotGit

proc `<-`(f: var Fod, m: NimbleMetadata) =
  f.srcDir = m.srcDir

import sugar

proc parseDepsFromLockFile*(lockFile: string): OrderedTable[string, Dependency] =
  info "parsing nimble lock file: ", lockFile
  let lockData = parseFile(lockFile)
  if "packages" in lockData:
    result = lockData["packages"].to(typeof(result))
    # unclear how stable the nimble.lock ordering is
    # https://github.com/nim-lang/nimble/issues/1184
    result.sort((x, y) => cmp(x[0], y[0]))

proc parsePrefetchGit(prefetchJsonStr: string): PrefetchData =
  var prefetchData: PrefetchDataGit
  try:
    prefetchData = parseJson(prefetchJsonStr).to(PrefetchDataGit)
  except JsonParsingError:
    error "failed to parse nix-prefetch-git json"
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
  let cmd =
    fmt"{nixPrefetchUrlPath} {url} --type sha256 --print-path --unpack --name source"
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
  let cmd = fmt"{nixPrefetchGitPath} --url {url} --rev {rev} --fetch-submodules --quiet"
  let (output, code) = execCmdEx(cmd, options = {poUsePath})
  if code != 0:
    error "failed to prefetch: ", url
    dumpQuit output
  result = parsePrefetchGit output
  result.`method` = "git"
  result.url = url

proc fetch(c: NnlContext, f: var Fod) =
  var
    prefetchData: PrefetchData
    uri = parseUri(f.url)
  if c.prefetchGitAll or (f.packages[0] in c.prefetchGit):
    uri.scheme.removePrefix("git+")
    if uri.query != "":
      if uri.query.startsWith("subdir="):
        f.subDir = uri.query[7 .. ^1]
      uri.query = ""
    let cloneUrl = $uri
    prefetchData = nixPrefetchGit(cloneUrl, f.rev)
  elif testUri(uri) in {Http200, Http302}:
    let archiveUrl = $getArchiveUri(f.url, f.rev)
    prefetchData = nixPrefetchUrl(archiveUrl)
  else:
    fatalQuit "archive url: " & $uri & " is unreachable"
  f <- prefetchData
  f <- getNimbleMetadata(f.path)

proc genFod(c: NnlContext, package: string, d: Dependency): Fod =
  result = Fod()
  result.packages = @[package]
  result <- d
  fetch c, result

proc checkGit(c: NnlContext, deps: OrderedTable[string, Dependency]) =
  let missing = (c.prefetchGit.toHashSet() - deps.keys().toSeq().toHashSet())
  if missing.len > 0:
    fatalQuit "unknown dependencies: " & missing.toSeq().join(", ")

import std/tempfiles


template withDir(p: string, body: untyped) =
  let old = getCurrentDir()
  # TODO: ensure this is a directory?
  setCurrentDir p
  body
  setCurrentDir old

proc hasNimbleFile(dir: string): bool =
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble"):
      return true

proc parseDepsFromNimblePackage(path: string): OrderedTable[string, Dependency] = 
  # TODO: force it to regenerate?
  if fileExists(path / "nimble.lock"):
    info "using existing nimble.lock"
    return parseDepsFromLockFile(path / "nimble.lock")

  info "generating nimble.lock"
  if not hasNimbleFile path:
    fatalQuit "no .nimble file found, is this a nim package directory"

  # TODO: make user flag for tempDir?
  let dir = createTempDir("nnl-", "")
  withDir path:
    let cmd = fmt"nimble lock --nimbleDir:{dir}/nimble --lockFile:{dir}/nimble.lock --verbose --debug"
    let (output, code) = execCmdEx(cmd, options = {poUsePath})
    if code != 0:
      fatalQuit "nimble lock failed" & "\n" & output

    result = parseDepsFromLockFile(dir/"nimble.lock")
  removeDir dir

proc generateLockFile*(c: NnlContext): JsonNode =
  var
    fods: seq[Fod]
    deps: OrderedTable[string, Dependency]

  if fileExists c.lockFile:
    deps = parseDepsFromLockFile(c.lockFile)
  elif dirExists c.lockFile:
    deps = parseDepsFromNimblePackage(c.lockFile)
  else:
    fatalQuit c.lockFile, "path is not a directory or a file"
 
  checkGit(c, deps)

  for name, dep in deps:
    if name.toLowerAscii() notin ["nim", "compiler"]:
      fods.add genFod(c, name, dep)
  return (%*{"depends": fods})

proc checkDeps() =
  debug "nimble: " & nimblePath
  debug "nix-prefetch-url: " & nixPrefetchUrlPath
  debug "nix-prefetch-git: " & nixPrefetchGitPath
  if findExe(nixPrefetchUrlPath) == "":
    fatalQuit "nix-prefetch-url not found"
  if findExe(nixPrefetchGitPath) == "":
    fatalQuit "nix-prefetch-git not found"

proc nnl(c: NnlContext) =
  checkDeps()
  let data = pretty(generateLockFile c)
  if c.output == "stdout":
    stdout.writeLine(data)
  elif c.output != "":
    writeFile(c.output, data & "\n")

proc version(): string {.compileTime.} =
  ## overengineered version embedding
  const nnlVersion {.strdefine.} = ""
  result = nnlVersion
  when nnlVersion == "":
    const (gitVersion, code) = gorgeEx("git describe --always --tags")
    when code != 0:
      {.fatal: "failed to get nnl version: " & gitVersion & "\nuse -d:nnlVersion:v* to override auto detection"}
    result = gitVersion

when isMainModule:
  import hwylterm/hwylcli
  hwylCli:
    name "nnl"
    settings ShowHelp, InferShort
    version version()
    help:
      header """
      [b cyan][yellow]n[/]im [yellow]n[/]ix [yellow]l[/]ock[/]
      ------------
      nimble.lock -> lock.json
      generate a lock file for
      packaging nim modules with nix
      """
    positionals:
      path string
    flags:
      output("stdout", string, "path/to/lock.json")
      `git`(seq[string], "use nix-prefetch-git")
      `git - all` "use nix-prefetch-git for all dependencies"
      verbose "increase verbosity"
    run:
      if verbose: logger.levelThreshold = lvlAll
      let c = NnlContext(
        lockFile: path, output: output, prefetchGit: `git`, prefetchGitAll: `git - all`
      )
      nnl c
