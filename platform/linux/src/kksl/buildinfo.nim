## What a build knows about itself: the version (VERSION), the commit it was built from, and whether the checkout had
## changes the commit doesn't hold; plus the shared About content (data/about.json, made by tools/about.py), compiled
## in so a program always describes the code it was built from.
## The commit comes from the build: `-d:kksCommit=<40 hex>` and `-d:kksDirty=true|false`
## (deploy/install-server-user.sh passes both); without them, from git at compile time when the source is a git
## checkout, else unknown (""). The source of a build is on GitHub at `SourceUrl` (the AGPL's offer of the
## Corresponding Source, §13): exact for a clean build of a pushed commit.

import std/[os, strutils]

const
  kksCommit {.strdefine.} = ""
  kksDirty {.strdefine.} = ""
  repoDir = currentSourcePath().parentDir / ".." / ".." / ".." / ".."
  Repository* = "https://github.com/5wHN28Dg/kks-explorer"
  Version* = staticRead(repoDir / "VERSION").strip
  AboutJson* = staticRead(repoDir / "data" / "about.json")   ## the shared About content, as text

proc isCommit(s: string): bool =
  s.len == 40 and s.allCharsInSet(HexDigits) and s.toLowerAscii == s

const
  git = "git -C " & quoteShell(repoDir) & " "
  # the source must be this repository's own checkout, not a folder inside some other one
  gitTop = when kksCommit.len > 0: "" else: staticExec(git & "rev-parse --show-toplevel 2>/dev/null").strip
  inGit = gitTop.len > 0 and staticExec(git & "rev-parse --show-prefix 2>/dev/null").strip.len == 0   # (repoDir is the top)
  gitCommit = when kksCommit.len > 0: kksCommit
              elif inGit: staticExec(git & "rev-parse HEAD 2>/dev/null").strip
              else: ""
  Commit* = when isCommit(gitCommit): gitCommit else: ""   ## "" when not known
  Modified* = when kksDirty.len > 0: kksDirty == "true"     ## the build had changes the commit doesn't hold
              elif Commit.len == 0: false                  ## (changed or new files, as `git status` shows them)
              else: staticExec(git & "status --porcelain -- . 2>/dev/null").strip.len > 0
  SourceUrl* = if Commit.len > 0: Repository & "/tree/" & Commit else: Repository   ## where this build's source is
                                                                                    ## (without its local changes when Modified)

static:
  doAssert kksDirty in ["", "true", "false"], "-d:kksDirty must be true or false"
  doAssert kksCommit.len == 0 or isCommit(kksCommit), "-d:kksCommit must be a full commit hash (40 lowercase hex digits)"

proc sourceLine*(): string =
  ## where the source is, said honestly for a build with local changes
  (if Modified: "Source (the commit this build started from; its local changes are not published): " else: "Source: ") & SourceUrl

proc versionLine*(program: string): string =
  ## "<program> 0.10.3 (commit 0123456789ab, with local changes)"
  result = program & " " & Version
  if Commit.len > 0: result.add " (commit " & Commit[0 ..< 12] & (if Modified: ", with local changes" else: "") & ")"
  else: result.add " (commit unknown)"
