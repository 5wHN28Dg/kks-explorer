# Windows platform layer (decision 0033): always cross-built with mingw-w64 from ~/.local/kksdev
import std/os
switch("path", thisDir() & "/src")
switch("path", thisDir() & "/../linux/src")
switch("path", thisDir() & "/../../core/src")
switch("hints", "off")
switch("warning", "UnusedImport:off")
when defined(mingw):
  let kdev = getEnv("KKS_DEV", getEnv("HOME") & "/.local/kksdev")
  switch("amd64.windows.gcc.path", getEnv("KKS_MINGW_BIN", kdev & "/mingw/usr/bin"))
  let w64 = getEnv("KKS_WIN64", kdev & "/win64")
  switch("passC", "-I" & w64 & "/include")
  switch("passL", "-L" & w64 & "/lib -static")
  switch("define", "kksBundledSqlite")
  switch("define", "sqliteDir=" & kdev & "/src/sqlite-amalgamation-3530400")
