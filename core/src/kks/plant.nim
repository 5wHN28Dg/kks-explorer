## Building plant entries (PROTOCOL-v2 §8–9): root statements, genesis, people, devices. Used to create a plant, by the
## manager's and admins' actions, and by tests.

import json, crypto, util, proto, replay

proc newPersonId*(p: Provider): string = hex(p.randomBytes(16))

proc statement*(p: Provider, rootKey: PrivateKey, stmt: JNode): (JNode, string) =
  (stmt, p.signStatement(rootKey, stmt))

proc genesisBody*(p: Provider, rootKey: PrivateKey, plant, device, person, username, fullName: string,
                  position: JNode = newNull(), imp: JNode = newNull()): JNode =
  ## The first entry of a plant, written by the manager's first device (`device`).
  let sm = newObj(@[("kind", newStr("manager")), ("person", newStr(person))])
  let sd = newObj(@[("kind", newStr("device")), ("device", newStr(device)), ("person", newStr(person))])
  newObj(@[("plant", newStr(plant)), ("root", newStr(keyString(rootKey.pub))),
           ("manager", newObj(@[("person", newStr(person)), ("username", newStr(username)),
                                ("full_name", newStr(fullName)), ("position", position)])),
           ("stmt_manager", sm), ("stmt_device", sd),
           ("sig_manager", newStr(p.signStatement(rootKey, sm))), ("sig_device", newStr(p.signStatement(rootKey, sd))),
           ("import", imp)])

proc personBody*(person, username, fullName, role: string, position: JNode = newNull()): JNode =
  newObj(@[("person", newStr(person)), ("username", newStr(username)), ("full_name", newStr(fullName)),
           ("position", position), ("role", newStr(role))])

proc deviceCertBody*(device, person, label: string): JNode =
  newObj(@[("device", newStr(device)), ("person", newStr(person)), ("label", newStr(label))])

proc revokeBody*(device: string, lastSeq: int64): JNode =
  newObj(@[("device", newStr(device)), ("last_seq", newInt(lastSeq))])

proc rootBody*(p: Provider, rootKey: PrivateKey, stmt: JNode): JNode =
  newObj(@[("stmt", stmt), ("root_sig", newStr(p.signStatement(rootKey, stmt)))])
