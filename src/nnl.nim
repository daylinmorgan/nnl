import std/[strutils, json, logging,options, os, osproc, tables, uri, httpclient]

var consoleLog = newConsoleLogger(useStdErr = true)
addHandler(consoleLog)

type
  NnlContext* = object
    lockFile*: string
    forceGit: bool

  Checksums = object
    sha1: string
  Dependency = object
    version, vcsRevision, url, downloadMethod: string
    dependencies: seq[string]
    checksums: Checksums

  Dependencies = Table[string,Dependency]

  Fod = object
    `method`, path, rev, sha256, srcDir, url, subDir: string
    packages: seq[string]

  PrefetchData = object
    `method`: Option[string]
    url, rev, date, path, sha256: string
    fetchLFS, fetchSubmodules, deepClone, leaveDotGit: bool


proc errLogQuit(args: varargs[string, `$`]) =
  error args.join(" ")
  quit 1

proc dumpQuit(args: varargs[string, `$`]) =
  stderr.writeLine args.join(" ")
  quit 1

proc `<-`(f: var Fod, d: Dependency) =
  f.url = d.url
  f.rev = d.vcsRevision

proc `<-`(f: var Fod, p: PrefetchData) =
  f.`method` = get(p.`method`)
  f.path = p.path
  f.sha256 = p.sha256

proc parseDepsFromLockFile*(lockFile: string): Dependencies =
  let lockData = parseFile(lockFile)
  if "packages" in lockData:
    result = lockData["packages"].to(Dependencies)

proc parsePrefetch(prefetchJsonStr: string): PrefetchData =
  try:
    result = parseJson(prefetchJsonStr).to(PrefetchData)
  except JsonParsingError:
    error "faild to parse nix-prefetch-git json"
    dumpQuit prefetchJsonStr

proc getArchiveUri(gitUrl, rev: string): Uri =
  result = parseUri(gitUrl)
  result.scheme = "https"
  result.path.removeSuffix ".git"
  result.path = result.path / "archive" / rev & ".tar.gz"

proc testUri(uri: Uri): HttpCode =
  info "TESTING!"
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
      "--type sha256 --print-path --unpack"].join(" ")
    let (output, code) = execCmdEx(cmd)
    let lines = output.strip().splitLines()
    if code != 0:
      error "failed to prefetch: ", url
    if lines.len != 2:
      error "expected 2 lines from nix-prefetch-url output, got ", lines.len
    if code != 0 or lines.len != 2:
      dumpQuit output

    result.`method` = some("fetchzip")
    result.sha256 = lines[0]
    result.path = lines[1]

proc nixPrefetchGit(url: string, rev: string): PrefetchData =
  debug "prefetching repo: ", url
  let cmd = [
    "nix-prefetch-git",
    "--url", url, "--rev", rev, "--fetch-submodules --quiet"
  ].join(" ")
  let (output, code) = execCmdEx(cmd)
  if code != 0:
    error "failed to prefetch: ", url
    stderr.writeLine output
    quit 1

  result = parsePrefetch output
  result.`method` = some("git")


proc fetch(c: NnlContext, f: var Fod) =
  var uri = parseUri(f.url)
  uri.scheme.removePrefix("git+")
  if uri.query != "":
    if uri.query.startsWith("subdir="):
      f.subDir = uri.query[7 .. ^1]
    uri.query = ""
  let cloneUrl = $uri
  let archiveUrl = $getArchiveUri(f.url, f.rev)
  if not c.forceGit and testUri(uri) in {Http200, Http302}:
    let prefetchData = nixPrefetchUrl archiveUrl
    # f.method = "fetchzip"
    f <- prefetchData
    f.url = archiveUrl
  else:
    let prefetchData = nixPrefetchGit(cloneUrl, f.rev)
    f <- prefetchData
    f.url = cloneUrl

proc genFod(c: NnlContext, package: string, d: Dependency): Fod =
  result = Fod()
  result.packages = @[package]
  result <- d
  fetch c, result

proc generateLockFile*(c: NnlContext) =
  info "parsing: ", c.lockFile
  if not fileExists c.lockFile:
    errLogQuit c.lockFile, "does not exist"
  var fods: seq[Fod]
  let dependencies = parseDepsFromLockFile c.lockFile
  for name, dep in dependencies:
    if name.toLowerAscii() notin ["nim","compiler"]:
      fods.add genFod(c, name, dep)
  stdout.write (%* {"depends": fods })

proc checkDeps() = 
  if (findExe "nix-prefetch-url") == "":
    errLogQuit "nix-prefetch-url not found"
  if (findExe "nix-prefetch-git") == "":
    errLogQuit "nix-prefetch-git not found"

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
  -h, --help show this help
  --force-git  force use of nix-prefetch-git
"""
  var c = NnlContext()
  var posArgs: seq[string]
  for kind, key, val in getopt(shortNoVal = {'h'}, longNoVal = @["help","force-git"]):
    case kind
    of cmdArgument:
      posArgs.add key
    of cmdShortOption, cmdLongOption:
      case key
      of "h", "help":
        echo usage; quit 0
      of "force-git":
        c.forceGit = true
    of cmdEnd: discard

  checkDeps()
  case posArgs.len
  of 1:
    c.lockFile = posArgs[0]
  of 0:
    errLogQuit "expected path to nimble.lock"
  else:
    errLogQuit "expected one positional argument, but got `" & posArgs.join(" ") & "`"
  generateLockFile c
