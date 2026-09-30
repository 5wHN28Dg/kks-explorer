# M6 requirements (approved 2026-09-30, answers included)

What KKS Explorer must do, stated without choosing any technology. Taken from what the product does today (CLAUDE.md,
docs/ARCHITECTURE.md) plus the user's decisions. IDs are used by the
capability matrix and the decision records.

## Context

- **People:**
  - one manager (the plant's I&C maintenance engineer who runs the tool);
  - a few admins;
  - members (technicians, engineers);
  - trainees.
  - Size: 8–9 people today; expected to grow to 20–50 or more once the company adopts it. Design for 100 people
    and about 200 devices.
- **Devices:**
  - Android phones in the field;
  - Windows laptops (HQ);
  - Linux laptops (GNOME);
  - iPhones through the browser only.
- **Networks:**
  - The plant Wi-Fi allows device-to-device traffic (answered 2026-09-26).
  - Internet access at the plant is intermittent.
  - Anything reaching the internet or the IT network needs written IT/security approval, and must never touch the OT
    network.
- **Data today:**
  - 11 P&ID sheets as vector PDFs (40k–140k paths each), about 1.4k tag occurrences;
  - 360 location rows, 77 procedures, 3 courses;
  - photos at about 0.7 MB each, growing;
  - about 100 log entries.
  - Design for at least: 100 sheets, 20k tags, 5k photos, 50k log entries.
- **Constraints:**
  - one developer;
  - no Mac, no paid Apple account;
  - the source is public (AGPL-3.0), plant data never in it;
  - long lifespan (years), so maintainability outweighs novelty.

## Functional requirements

### Drawings and equipment
- **R1 Drawing viewer.**
  - Open any P&ID sheet and pan and zoom smoothly, up to at least 16×.
  - Lines and text stay sharp at every zoom.
  - Works on a phone (touch, one hand) and a desktop (mouse, keyboard).
- **R2 Tags on drawings.**
  - Every tag occurrence is selectable on the sheet.
  - Search by KKS code (full, partial, with or without the unit prefix, with suffixes), and by description.
  - Jump between all occurrences across sheets.
- **R3 KKS decoding.** Any code is decoded into system, component, ISA function letters and unit, from decode tables
  that ship with the program.
- **R4 Equipment record.** Per KKS code (shared across sheets):
  - the decoded meaning;
  - the physical location, from the plant's location list as a fallback: level/elevation, cabinet, direction;
  - user data: floor, notes, custom fields;
  - photos;
  - linked procedure steps;
  - review status.
- **R5 Review and quality.**
  - A queue of uncertain tag readings for people to confirm or correct.
  - Floor filter.
  - Notes on whole sheets.
- **R6 Missed and wrong tags.** Anyone can mark a missed tag (a box on the sheet, plus the code if known) or propose
  removing a wrong one. Approval is required. Marks survive re-imports of the sheet.

### Procedures and learning
- **R7 Procedures.**
  - Browse the operation-manual procedures (steps, sections, page references).
  - Link steps to equipment in both directions: from a step to its equipment, from equipment to the steps that use it.
- **R8 Courses.**
  - Run the three interactive courses: text, animated figures, quizzes, photos, links between courses.
  - The course content exists as HTML/JavaScript and is treated as given content.
  - Progress is private to the person, follows them across their own devices, and is unreadable by anyone else,
    including a server.

### Photos
- **R9 Photos.**
  - Take or pick a photo, annotate it (arrow, box, circle, colours, undo), and attach it to equipment.
  - Stored compressed as JPEG XL (decided 2026-09-27 and 2026-09-30).
  - View with pinch or scroll zoom.
  - Each device chooses to hold all photos or fetch them on demand.

### People, trust and history
- **R10 Accounts and roles.**
  - People with a full name and an optional position.
  - Roles: exactly one manager, admins, members.
  - The manager manages admins; admins manage members.
  - The manager role can be handed over.
- **R11 Accountability.**
  - Every change is attributable to a person and a device, and cannot be altered or forged afterwards without
    detection.
  - Full history, with revert of one change and restore of an earlier state.
- **R12 Proposals and approvals.**
  - Members propose; admins and the manager approve, reject, or pick among conflicting proposals.
  - Members can vote and withdraw.
  - A proposal can carry a note to the approver.
  - A value set by the manager cannot be overwritten by an admin.
- **R13 Devices.**
  - One person may use several devices.
  - Add a device by scanning a QR code, by asking an admin nearby (with a matching confirmation code), or by a file.
  - Remove a lost device: it stops receiving data, and wipes itself if it ever reconnects.
- **R14 Recovery.**
  - The plant can be recovered from backups.
  - The authority behind the plant (today the root key) has an offline backup held by the manager.
  - Losing any single device loses no data.

### Sync and connectivity
- **R15 Offline first.**
  - Every device works fully without any network.
  - When devices meet, their changes merge the same way on every device, with no central server required.
- **R16 Same Wi-Fi.** Devices of the same plant find each other automatically and sync within seconds; also by address.
- **R17 Internet.** Devices sync across the internet through a rendezvous/relay service when the plant permits it:
  direct when possible, relayed otherwise.
- **R18 Background.**
  - Phones sync periodically without being opened.
  - Only on unmetered networks unless the person allows metered.
- **R19 Browser access.**
  - People without the app (iPhones, borrowed computers) can sign in with a password to an always-on node, and work
    offline for a limited time.
  - Remote access goes only through a company-approved route.
- **R20 Status.**
  - Each device shows reachable devices, the last successful sync and connectivity.
  - Open screens update when data changes underneath them.

### Plant data
- **R21 Importing drawings.**
  - The manager imports new P&ID PDFs, with automatic tag reading (container detection plus a glyph classifier), a
    preview, re-import with rotation, and removal.
  - This runs on one machine.
  - Reading accuracy must not regress: the LP reference and a regression check across all sheets.
- **R22 Publishing plant data.**
  - Drawings, tags, locations and procedures form a versioned plant-data set.
  - Only the manager publishes it, and it reaches every device by sync.
  - It is never part of the public program.

### Distribution and updates
- **R23 Install.**
  - Desktop: one download, no administrator rights, no separate runtime to install.
  - Android: an installable package outside the Play Store. Play Store distribution may come later: don't block it,
    don't design for it now.
- **R24 Updates.**
  - Each device checks daily, verifies an update against the maintainer's signature, and installs only when the
    person agrees.
  - The plant data is unaffected.

## Non-functional requirements

- **N1 Security.**
  - Data in transit is authenticated and encrypted end to end between devices.
  - Device keys live in the platform's secure storage where one exists.
  - A stolen device can be revoked.
  - Platform security mechanisms are never bypassed.
- **N1a Encryption at rest (decided 2026-09-30).**
  - Plant data stored on a device (log, drawings, photos, backups) is encrypted.
  - Only the app, on a device the plant has accepted (manager or admin approval), can decrypt it, and only while the
    app runs.
  - The key reaches a device when it is accepted, and is kept in the platform's secure key storage where one exists.
  - A removed device gets no keys for new data.
  - The limits must be stated honestly in the design:
    - anyone using the unlocked device through the app sees the data;
    - on desktops, other programs running as the same user may reach the stored key;
    - data a device already had cannot be taken back.
  - Browser access (R19): what a browser keeps offline is protected only as far as the browser allows. State this
    too.
- **N2 Accessibility.**
  - Usable with keyboard only, screen readers, 200 % zoom and high contrast, with reduced motion respected.
  - Readable in bright outdoor light on a phone.
- **N3 Performance.**
  - Opening the app and a sheet feels immediate.
  - Panning holds the display's frame rate on a mid-range phone.
  - Sync of a normal day's changes takes seconds.
  - Numbers and regression rules are set in the matrix step, after measuring today's app as the baseline.
- **N4 Footprint.**
  - Installed size, memory and battery are measured on each target.
  - Growth needs a written reason.
- **N5 Reliability.**
  - No data loss on crash or power cut (journaled writes).
  - Snapshots and backups.
  - Updates never lose data.
- **N6 Maintainability.**
  - One developer can maintain it for years.
  - Few languages and toolchains.
  - Business logic separated from platform code, with shared test vectors across implementations.
  - Every dependency passes the policy's maintenance test or is justified.
- **N7 Language.**
  - English UI only (Arabic UI not needed, 2026-09-30).
  - User content in any language must display and edit correctly, including Arabic and mixed right-to-left and
    left-to-right text in notes and fields.
- **N8 Minimum platform versions.**
  - Android 10 (decided 2026-09-26; open to change).
  - Windows 10.
  - A current GNOME LTS distribution.
  - Safari 17+.

## Explicit non-goals (unless the user adds them)

- a native iOS app;
- macOS;
- a public cloud service holding plant data.

The relay only passes encrypted traffic.
