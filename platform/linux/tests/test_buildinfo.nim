## buildinfo: what a build says about itself (kks-server --version, /api/about). Also built by hand with
## -d:kksCommit=<40 hex> -d:kksDirty=true|false, as deploy/install-server-user.sh builds the server.
import std/[os, strutils]
import kks/json
import kksl/buildinfo

const kksCommit {.strdefine.} = ""
const kksDirty {.strdefine.} = ""
const top = currentSourcePath().parentDir & "/../../.."
const headCommit = staticExec("git -C " & top & " rev-parse HEAD 2>/dev/null").strip
# the repository's own checkout (not a copy inside another repository, not a tree without git)
const inCheckout = headCommit.len == 40 and staticExec("git -C " & top & " rev-parse --show-prefix 2>&1").strip.len == 0

const versionFile = staticRead("../../../VERSION")
doAssert Version == versionFile.strip
doAssert Commit.len == 0 or (Commit.len == 40 and Commit.allCharsInSet({'0'..'9', 'a'..'f'}))
when kksCommit.len > 0:
  doAssert Commit == kksCommit
  doAssert Modified == (kksDirty == "true")
elif inCheckout:   # built from a git checkout without the defines: git says the commit
  doAssert Commit.len == 40, "the commit was not found in this checkout"
  doAssert Commit == headCommit
else:              # no git, or a copy inside another repository: unknown (never that repository's commit)
  doAssert Commit.len == 0
doAssert sourceLine() == (if Modified: "Source (the commit this build started from; its local changes are not published): "
                          else: "Source: ") & SourceUrl
if Commit.len > 0:
  doAssert SourceUrl == "https://github.com/5wHN28Dg/kks-explorer/tree/" & Commit
  doAssert versionLine("X") == "X " & Version & " (commit " & Commit[0 ..< 12] &
                               (if Modified: ", with local changes" else: "") & ")"
else:
  doAssert SourceUrl == "https://github.com/5wHN28Dg/kks-explorer"
  doAssert versionLine("X") == "X " & Version & " (commit unknown)"
  doAssert not Modified
let about = parseStrict(AboutJson)   # the strict reader takes it (the server parses it at start)
doAssert about["format"].s == "walkdown-about"
doAssert about["license"]["id"].s == "AGPL-3.0-or-later"
echo "test_buildinfo: ok (", versionLine("Walkdown"), ")"
