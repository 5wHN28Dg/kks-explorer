# 0052 Accepted risks: the server holds the root key online (#70); a stranger on the LAN learns who is there (#68)

Date 2026-10-08 · Scope: the server's store, `reset-manager`; §15 hello, §16 mDNS TXT · Status: **accepted by the
user** (2026-10-08: "#70 and #68: accept and document")

## #70: the root key and every custodial key are online on the server

- **What:** the server keeps the plant root key and each web account's custodial device key in its store, sealed
  with the systemd-creds storage key (0020). That is by design: decision 0026 makes the server the plant's always-on
  node, and it signs for web accounts.
- **The risk:** whoever runs code as the server's user can sign any entry, role changes included. That is a
  compromise of the whole plant's trust. No direct path to it is known.
- **What limits it:** the store is sealed; the HTTP listener takes only this machine's addresses; the importer runs
  with limits and a deadline (#34, PR #95); the unit has `NoNewPrivileges`, `PrivateTmp`, `UMask=0077` and
  `MemoryMax`. The root key also has an offline backup with a generated passphrase (#29).
- **The alternative, not taken now:** move the root key to an offline manager device and keep on the server only
  what web accounts need. Root statements (rotation, root revokes) would then need that device.
- **Revisit:** at each audit, if the server ever faces the internet directly, or if a path to code execution as the
  server's user is found.

## #68: the sync hello and the mDNS TXT tell a stranger about the plant

- **What:**
  - Any TLS client that reaches a sync port gets the responder's `hello`: the root key, and every device ID with its
    last seq.
  - mDNS answers carry the plant's name, the device's label and whether it is an admin's device (`adm`).
- **The risk:** someone on the plant network learns:
  - which plant this is;
  - how many devices it has, and which is an admin's;
  - when each device last wrote.

  No entry content leaks: a stranger gets `denied` (§15).
- **Why not now:**
  - An empty `vv` for strangers was tried (PR #92 review). A device the responder doesn't know yet then sends its
    whole log, and the 4 MB stranger frame limit (#67) refuses it.
  - Trimming the TXT record breaks joining through an admin nearby (§16 "Without an invite"), which needs `adm`,
    `plant` and `label`.
- **What limits it:** the sync port and mDNS are on the plant LAN only. The relay, which can be reached from the
  internet, now admits only holders of the plant's room key (0050).
- **Revisit:** if the sync port is ever reachable from outside the plant LAN, or with the next change to §15 (send
  the hello's `vv` only to a side that proved it is certified, with a larger first-frame limit for it).
