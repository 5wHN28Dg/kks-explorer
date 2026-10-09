# The server only (config.nims is read too). glibc's malloc instead of Nim's own allocator: Nim's keeps every block
# it ever took from the system for reuse and returns none of it, so one burst (a device fetching a plant's drawings,
# a bundle export) stayed in the server's memory for good; malloc gives large blocks back when they are freed, and
# server.nim trims the rest every minute (2026-10-09: the deployed server held 7.4 GB).
switch("define", "useMalloc")
