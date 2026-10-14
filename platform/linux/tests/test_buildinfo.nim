## buildinfo: what a build says about itself (kks-server --version, /api/about). Also built by hand with
## -d:kksCommit=<40 hex> -d:kksDirty=true|false, as deploy/install-server-user.sh builds the server.
import std/strutils
import kks/json
import kksl/buildinfo

const kksCommit {.strdefine.} = ""
const kksDirty {.strdefine.} = ""

const versionFile = staticRead("../../../VERSION")
doAssert Version == versionFile.strip
doAssert Commit.len == 0 or (Commit.len == 40 and Commit.allCharsInSet({'0'..'9', 'a'..'f'}))
when kksCommit.len > 0:
  doAssert Commit == kksCommit
  doAssert Modified == (kksDirty == "true")
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
