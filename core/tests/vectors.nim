## Loads the shared vector files (ref/vectors) with the core's own strict reader.
import std/os
import kks/json

const VectorDir* = currentSourcePath.parentDir.parentDir.parentDir / "ref" / "vectors"

proc loadVectors*(name: string): JNode =
  ## KKS_VECTORS overrides the folder (a test binary copied to another machine, e.g. a Windows VM)
  parseStrict(readFile(getEnv("KKS_VECTORS", VectorDir) / name), maxDepth = 4096)
