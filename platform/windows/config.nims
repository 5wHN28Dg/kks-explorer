# Windows platform layer (decisions 0033, 0053): always cross-built with llvm-mingw from ~/.local/kksdev
import std/os
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../linux/src")
switch("path", thisDir() & "/../../core/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")
include "toolchain.nims"
when defined(mingw):
  switch("define", "kksBundledSqlite")
  switch("define", "sqliteDir=" & winDev & "/src/sqlite-amalgamation-3530400")
