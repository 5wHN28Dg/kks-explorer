# UI and UX policy

My standing policy for the interfaces of everything I build: what each interface must do, how a change to it is checked, and how each product keeps getting better instead of only not getting worse. It applies to me and to any coding agent working on my projects, alongside my [AGENTS.md](AGENTS.md).

Version 4.13 (2026-11-18). Changes: Appendix E.

## Quick start

- **Agent making a change:** read section 0, the project's profile, then the rule digest the review script makes (8.4), or until it exists, only the rules the change-kind map (Appendix C) lists for your kind of change, plus your platform's module (section 7) and product kind (7.9). For a tier-0 or tier-1 change that is about a third of this document, with sections 8 and 9. Section 8 says how to check; 9 what blocks.
- **Reviewer subagent:** read 0, 8.2 to 8.4, 8.8, 9, the rules the map lists for the change (Appendix H finds any rule by ID), and Appendix B; for a profile edit, also section 1.
- **Me:** 0, 1, 2, 8.5, 9, 10.

**Adopting it in a project that predates it**, in phases:

1. **First session:** first, make sure Appendix G's lines are in AGENTS.md or in the project's CLAUDE.md (adding them to either is mine, or an agent's with my approval quoted in the PR); until they are, agents start no tier-2 or tier-3 change on that product, so AGENTS.md's deploy step can't ship one unchecked. Then write the profile (section 1). Check the product by hand against the rules that can never be waived (the **never-waivable set**: S1 to S3, S8, A10, T1, T9, Z1, and the law's duties, T0) and against U1, A1 and A5. File what fails; everything found while adopting counts as pre-existing once tracked (9.2). Write the review brief (1.6); until the prompt script of 8.4 exists, the brief is pasted word for word into each reviewer's prompt, with its version recorded in the PR.
2. **Within a month:** the automated evidence (8.3) for each platform the project has; tier every UI change (8.2).
3. **Within a quarter:** the first full audit (8.9) and the first round with real users (8.6). From then on, the whole policy applies. Until then, Advice fails are backlog items only. A missed phase is a severity-2 item. If the missed part is agent work (the profile, evidence, an audit), it stops new tier-2 work on that product until it's done; if it's one of my duties (the list in 9.8), 9.8 applies instead.

## 0. How to use this policy

### 0.1 What it covers

Everything a person sees, hears, feels or does when using one of my products:

| Kind                                                                                                            | Examples now                                                                         | Module    |
| --------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ | --------- |
| Web apps and PWAs, including ones served from a router                                                          | Walkdown's web client and admin pages; the safe-otaku reader                         | 7.1 WEB   |
| GNOME apps (GTK4, libadwaita)                                                                                   | Direct-Share for Linux; Walkdown for GNOME                                           | 7.2 GNOME |
| Android apps (Kotlin, Jetpack Compose)                                                                          | Direct-Share for Android; Walkdown for Android                                       | 7.3 AND   |
| Windows desktop apps                                                                                            | Walkdown for Windows                                                                 | 7.4 WIN   |
| Godot games and simulators (desktop and Android; keyboard and mouse, gamepad, touch)                            | Walkdown Plant                                                                       | 7.5 GM    |
| Terminal UIs (Textual)                                                                                          | tele-notify's terminal screen                                                        | 7.6 TUI   |
| Command-line tools and setup scripts (Nim, Python, shell, PowerShell, on desktops, servers and OpenWrt routers) | openwrt-oneclick's `setup.sh`, `tgproxy`, `telenotify`, the Autodesk clean-up script | 7.7 CLI   |
| Messages a product sends (Telegram posts and forwards, notifications, emails)                                   | tele-notify's forwarded posts and alerts                                             | 7.8 MSG   |

Section 7.9 adds what the best products of each **kind** I build do: local file sharing, alerts, training, field tools, family filters, and setup that hands something to another device.

It covers screens, menus, dialogs, HUDs, notifications, sounds, haptics, controls, wording, onboarding, settings, errors, command output, install and update flows, and the README sections that tell people how to use the product. In a game it covers the world where a rule says so (readability, comfort, controls, feedback, access). It doesn't judge art direction, story or level design, except where they decide whether a player can perceive, understand, control or enjoy what is going on.

Not covered (none of my products has them; if one ever does, I'll extend the policy first): consoles and TV, VR and AR, voice assistants, watches, cars, kiosks, regulated safety-critical devices, ads, in-app purchases or loot boxes, multiplayer with strangers, and team processes beyond one owner and agents. Multiplayer among people who know each other (Plant's shared sessions) is covered (GM10).

It also covers effects a product has on people who never run it: a site the family filter blocks, the internet going off at night, a router setting a phone suddenly depends on (FILTER rules in 7.9), and people who receive what it sends without running it (the readers of a channel tele-notify posts to; MSG6).

README, wiki and docs text is prose under AGENTS.md: it gets no review passes per change. Its W, T11 and T12 rules are checked at each release and full audit.

A product that is only a library, kernel work or infrastructure with no human-facing output (note9-mainline) has no UI to audit. Its error messages and command output still follow W3 and 7.7 when people read them.

### 0.2 How this fits with AGENTS.md and the project kinds

- **Every other project (do the work):** agents run this policy as part of the workflow in AGENTS.md: the evidence (8.3) is part of "build, lint and test"; the two review passes there are the audit passes here (8.4), for every UI change of any tier, because UI text and layout are code; "merge when CI is green" also needs section 9's blockers to pass. My hands-on check (8.5) gates the next **release**, not the merge.
- **Passion projects:** I do the work and learn. The policy is my reference, and agents tutoring me point to the rule a choice touches instead of fixing it. Agents run audits only when I ask; a delegation written in the project's CLAUDE.md (as tele-notify's Nim rewrite has) counts as asking, for the work it delegates, and inside that delegation the agent decides UI choices as in every other project, unless the delegation says otherwise. Whether a part is inside a delegation (tele-notify's Python TUI, next to its delegated Nim rewrite) is read from the delegation's words; when they don't say, the agent asks me once and records the answer in that CLAUDE.md. Outside it, UI decisions are mine.
- **A project without a "Project kind" line** gets one first, as AGENTS.md says, before this policy is applied.
- **What an agent may decide alone.** An agent settles a UI choice itself when the profile settles it, directly or through its tie-breakers (1.3: the design system, then the named platform guidelines, then the named reference products), and records which one did; so these are choices the project's docs settle, as AGENTS.md's stop rule requires. It stops for me only when a choice changes a core object or verb (C5), the experience intent, or a screen's intent order, or when AGENTS.md's stop rules apply. For a tier-2 or tier-3 change it builds its best option and puts two alternatives in the owner-check item (8.5): each one is how a named reference product or the platform's own pattern does it (a made-up weak option is gaming, 0.7), as mock-up screenshots, or for a core interaction as builds I can try behind the switch (8.5). My pick there counts as the try-out of 8.1.
- **Only I write my verdicts.** "Owner: OK", an acceptance of a Not-checked item, a waiver, and a pick between alternatives are written by me, or recorded by an agent only by quoting my own words with their date and place.
- **Projects' own testing rules** (a CLAUDE.md or AGENT.md saying what counts as verification, such as safe-otaku's "only a router counts") win over 8.3 where they're stricter: checks they reserve for real hardware are owner-check items, and the VM run is still made as evidence.
- **Existing project policies** (Walkdown's and tele-notify's UI policies) keep their own rule IDs, with a project prefix in results tables (WD-T1, TN-R3); this policy's IDs are used bare. Where a project policy is stricter, it wins. Where it is looser, it stays until that project's next full audit or until 2027-05-18, whichever comes first; then each difference becomes either a waiver (11.2) or a change to the project policy. Where it's unclear which of two differently shaped rules is stricter, both apply, and the reviewer records the mapping in the profile. A project policy that exists only on an unmerged branch (Walkdown's, at the time of writing) isn't in force; adopting this policy there (phase 1) merges or replaces it.
- **Hook-up.** A policy file can't change AGENTS.md's steps; only AGENTS.md or a project's CLAUDE.md can. So this policy takes effect through two lines in AGENTS.md (Appendix G), which point agents here and add its blockers and deploy hold to the workflow steps. Until those lines exist, AGENTS.md wins every conflict.
- **Projects others push to** (forks, upstream): their own UI guidelines win; this policy guides only my own contributions, and my notes go in `CLAUDE.local.md`.
- **The Stop and Safeguard rules in AGENTS.md always win** over anything here. In particular, never weaken a check to make a UI change pass.

### 0.3 Terms

- **User:** anyone who uses the product: me, my household, plant engineers, players.
- **Screen:** any distinct view: a page, a tab, a dialog, a panel, a HUD state, a scene with its own controls, a terminal screen, a command's output.
- **Task:** something a user comes to the product to get done or to experience (find a KKS code, send a file, block a site, review a post, finish a training scenario). **Main tasks** are listed in the profile (1.4).
- **Action:** one discrete input: a press, tap, click, key or chord, typed word, gesture. Choosing a command from a command palette or a search counts as one action plus the characters typed.
- **Change:** anything that alters what users see, hear, feel or do: code, assets, content, wording, config, a translation, a profile edit.
- **Touched:** a screen, rule or platform is touched by a change if the change alters code, assets, tokens, wording, config or a dependency that it renders or relies on. It's worked out from the files changed and the automated visual diff against the stored baseline (8.3), not from the author's claim; when unsure, it's touched.
- **Core interaction:** the action a main task is built around and repeated most (Plant: walking, looking, operating a valve; Walkdown: finding a tag on a drawing; Direct-Share: picking a device and sending), as the profile lists.
- **Released version:** what users have now: the last tagged release (APK, AppImage, Godot export, package), or for a product deployed on every merge, what's deployed.
- **Release:** a version that reaches users. For a product that deploys on merge, each deploy is a release.
- **Owner:** me. **Author:** whoever made the change (me or an agent). **Reviewer:** a fresh subagent, or a person, who didn't make the change.
- **Tracked item:** a GitHub issue in the project's repository (or, for a project with no remote, a dated entry in `docs/ux-backlog.md`), with severity, the rules it relates to, and evidence.
- **Cycle:** a month, or the project's milestone if it has one.
- **Outside reviewer:** a person other than me, or a fresh subagent whose prompt is generated by the project's review script (8.4) from the versioned brief, given my reason quoted word for word, and told to argue against it. Its **agreement** means it found no objection that holds; any objection that holds is a refusal.
- **Major release:** one the profile marks as major, or one containing a tier-3 change; a live product has at least one every 12 months, whatever its version numbers say. **Stable release:** the first release the README offers to people other than testers (often 1.0).
- **Must** is a requirement. **Should** is a strong default; skipping it needs a reason written in the change.

### 0.4 How rules are written

Every rule is a check with a pass or a fail. Each has an **ID**, a **level** and, where it isn't obvious, a **check**:

- **Block:** a fail the change causes can stop it from shipping (section 9).
- **Advice:** a fail is recorded and goes on the UX backlog. It blocks only when it's rated severity 1, or when it's on a main task's path in a tier-2 or tier-3 change and the change doesn't record a reason and a release by which it will be fixed (9.1).

IDs stay the same across versions, so gaps in the numbering are rules that were removed.

Where no check is given, the check is: inspect the evidence (8.3) for every touched screen and state, and look for a counter-example. Where a rule is stricter than the standard it cites, it says so.

A rule that can't apply to a product (no sound, no text input) is **N/A**. N/A is decided once, per rule and platform, in the profile's applicability list (1.6), not argued afresh in each change. "We didn't get to it" is never N/A; it's **Not checked** (9.3).

### 0.5 When rules conflict

1. The law, store rules (Google Play, F-Droid, Flathub), the terms of any platform or API the product depends on (Telegram's API terms for an automated account, MangaDex's API terms), and any standard a client or my employer names for a product.
2. Safety: no harm to the user, and no loss of their data, access, privacy or trust (S, T, Z).
3. Access: the product works for the profile's users, including disabled users (A, L).
4. The main tasks succeed. For a game or simulator, a main task includes the intended experience (feeling, pacing, challenge, realism for training). Efficiency rules apply to its menus, not to designed pacing.
5. Efficiency and speed for frequent users.
6. Look, feel and delight beyond the main tasks.
7. My own convenience as the developer.

Lower levels may shape anything that doesn't cost users at a higher level. When two rules at one level conflict, the one that serves more of the profile's users wins. Record the decision in the change; a conflict that keeps coming back becomes a pattern in the design system or a policy change (section 11).

### 0.6 What rules can't do alone

Rules keep a product from breaking and from getting worse. They don't make it great. Great comes from a clear idea of what the product is for, a few concepts done well, craft in how each interaction feels, and watching people use it. So the policy also requires:

- a purpose, a conceptual model and an experience intent with reference products (1.3);
- a design intent and a feel spec for each main screen and core interaction (V1, V14);
- trying ideas before building them, and watching real users after (8.1, 8.6);
- my hands-on check against a written rubric (8.5);
- targets that rise, comparison with the best products of each kind, and a backlog that gets worked down (section 10);
- removing things, not only adding them (C5, C6).

### 0.7 Gaming the policy is a fail

Following the letter while defeating the purpose is itself a severity-2 fail of the change that did it. Examples: defining main tasks so narrowly they test nothing; marking hard rules Not checked; splitting a change to lower its tier; rating your own fails low; calling routine work an emergency; grouping unlike screens; hiding features behind a command palette to pass a depth rule; shrinking the profile to drop a rule. Reviewers are told to look for it. I'm not exempt: 9.6 says how my own exceptions are kept honest.

### 0.8 Stages

The project's profile names its stage, but the stage follows the facts: any build others can get (a tag, a published APK or release, a deploy others can reach, or a README with install or usage instructions addressed to others) makes a product at least pre-release, and lowering the stage is a narrowing (1.7).

| Stage                                                                                                                             | What applies                                                                                                                                                                                                                                                                                                                            |
| --------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Prototype** (a spike, a jam; no build anyone else can get)                                                                      | A short profile (purpose, users, main tasks, experience intent); the never-waivable set plus A1, A5 and W3, and T4 to T6 if it sends data to other devices; trying ideas (8.1) is the main activity. No full audits (8.9); both review passes per AGENTS.md, limited to these rules.                                                    |
| **Public tool** (a script or CLI with no UI beyond its output, whose README invites others, such as the Autodesk clean-up script) | The Tool stage's rules plus T11, T12, the CLI evidence (7.7) and a full audit before its first stable release; no 8.6, and of section 10 only 10.5, met by a scripted run on the test VM (on fixtures that mimic the target's files, registry keys and services where the                                                               |
| real target needs a licence) plus barrier reports.                                                                                |                                                                                                                                                                                                                                                                                                                                         |
| **Tool** (a command-line tool or script whose only user is me and whose README doesn't invite others, such as `tgproxy`)          | Purpose and main tasks only for a profile; the never-waivable set; module 7.7 (and 7.6 if it has a TUI); the product-kind rules (7.9) that apply; W3, S4 to S7, T5, A5, L2. Both review passes per AGENTS.md, limited to these rules. No 8.5, 8.6 or section 10. If anyone else starts using it, it becomes live.                       |
| **Pre-release** (pre-alpha, alpha, beta, early testers; Direct-Share now)                                                         | Everything, but Advice fails may all wait as backlog; the automated evidence (8.3) may wait until the first beta, with screenshots, by script or by hand, of every touched screen the screen table lists until then; and a full audit is needed only before the first stable release. Testers are told what isn't accessible yet (T11). |
| **Live** (released and still changing)                                                                                            | Everything.                                                                                                                                                                                                                                                                                                                             |
| **Maintenance** (fixes only)                                                                                                      | Tiers and blockers for each change; a full audit once a year; users watched once a year; 10.1 and 10.4 are paused.                                                                                                                                                                                                                      |
| **Retired**                                                                                                                       | Users are told in the product and the README, at least 90 days ahead where the product holds their data, what stops and when; they can export their data (D4).                                                                                                                                                                          |

## 1. The project profile

Each project with a UI has a profile, in its repository (`docs/ux-profile.md`, or the profile section of the project's own UI policy, as Walkdown and tele-notify have). An audit without a profile is not valid. A project's own UI policy may add rules and make these stricter; it loosens them only through 1.5 or a waiver (11.2). Appendix A is a template.

### 1.1 Users and contexts

- **Who:** each kind of user: what they know (the domain, computers, the product), how often they use it, why, and what they fear (losing work, breaking the router, sending a file to the wrong phone, looking stupid in front of a colleague). Many of my products have one user, me; say so, and still write down what I know and fear. Include **recipients** who never run the product but get what it sends or decides (a channel's readers, the household behind a filter).
- **Evidence:** where each fact comes from (watching people, their messages, my own use, assumption). Assumptions are marked; the next round with users (8.6) checks them first.
- **Where and how:** desk, plant floor (gloves, sun, noise, one hand, interruptions, no network), couch, a shared family device, a child at the controls, a terminal beside a running service; and session length.
- **Abilities (floor):** the product serves users with low vision, blindness, colour vision deficiency, deafness, limited motor control, tremor, one hand, cognitive and learning disabilities, photosensitivity and motion sensitivity. A rule is N/A for a group only with a reason the reviewer accepts (a CLI has no colour-only signals if it never uses colour). "My users aren't disabled" is never a reason. A product used only by me records my own needs and still meets A1 to A5, A10 and A18 to A23, because my needs change (injury, a bad screen, sun, age).
- **Age:** whether children use it (T9 applies; safe-otaku's household includes them).
- **Languages:** UI languages (English; Arabic where the product offers it), and the languages of user content: Arabic, English and mixed text are the norm across my products (posts, names, notes, file names, titles).

### 1.2 Platforms and inputs

- Every platform and version range, with the **oldest and smallest supported device** (screen, density, memory, CPU, GPU) and the **typical device** (the one most use: often my own laptop or phone). For router-served products, the router's CPU, memory and storage, which are also budgets (P5).
- Window sizes, smallest and largest; orientations; 80 × 24 for terminals.
- Input methods, each **first-class** (every task works with it alone) or **secondary**. **Floor:** the platform's primary inputs are first-class: keyboard and pointer on desktops and the web at desktop size; touch on Android and the web at phone size; keyboard and mouse, gamepad and touch in Godot games where the game runs on those devices (Plant: all three); keyboard (and mouse where the toolkit supports it) in a TUI.
- Assistive technology. **Floor:** Orca and GNOME's Large Text, High Contrast, Reduced Motion and animations off on GNOME; TalkBack, font scale and Remove animations on Android; Narrator, contrast themes and text size on Windows; the browser's zoom, `forced-colors` and screen readers on the web (and VoiceOver on iOS Safari where iPhones use the web app); Godot's AccessKit support on desktops (as of Godot 4.7; recheck at each engine upgrade), plus the game's own text size, contrast and motion settings where the engine can't follow the system.
- Network: always online, often offline (Walkdown on the plant floor), local only (Direct-Share over Wi-Fi Direct), behind a router filter (safe-otaku).

### 1.3 Purpose, concepts and feel

- **Purpose:** one or two sentences: what it's for, for whom, and what it must never do (Plant: never teach a wrong procedure; openwrt-oneclick: never leave the router unreachable).
- **Product kinds** from 7.9 that apply.
- **Content policy,** where the product filters or rates content (safe-otaku's allowed ratings): my decision, written here; T9 and FILTER check that the product enforces it, not what it is.
- **Core objects and verbs:** the few things users work with and what they do to them (Walkdown: sheet, tag, photo, note; find, open, mark, sync). Every screen and feature maps onto them (C5).
- **Experience intent:** the feeling and pacing each part aims for ("finding a tag: instant, certain"; "a Plant scenario: calm, realistic, learnable"; "setup: guided, nothing scary") and the **reference products** it should feel at least as good as (for example GNOME Files, Organic Maps, Signal, Things, Linear, a well-regarded game of the same genre).
- **Core interactions:** each with its feel spec (V14).
- **Tie-breakers:** for a UI choice the profile doesn't settle, the order of sources an agent follows: the design system, then the named platform guidelines (the GNOME HIG, Material 3), then the reference product the profile names for that part of the experience (0.2). Only that one counts; if two named sources disagree, the choice is unsettled: build the best option and offer the alternatives (tier 2), or stop.

### 1.4 Main tasks and screens

- **Main tasks**, one row each: the task in users' words; who; how often; what "done" means; the targets (time, number of actions; for a game, how the part should feel and what share of players should finish it). **Floor:** the main tasks include the top reasons people use the product (for a product only I use, my top reasons), first run, every flow that deletes data, changes privacy, shares or sends something to others, changes a live system (the router, the running bot, the server), recovering access, changing the accessibility settings, and **installing, first setup and updating**: from the download page to the first main task, through every OS security warning (an unknown-sources prompt, SmartScreen, a self-signed certificate), each warning explained beforehand in plain words.
- **Screen table**, one row per screen, or per group of screens with one layout template (the reviewer may sample any member; the evidence includes the group's most complex member): its job (which tasks); what must be visible at the smallest supported size without scrolling or moving focus; its primary action (none or one); the input that does it on each first-class method; and its **intent order** for V1 (what should stand out first, second, third; content may come before controls). The evidence scripts list their screens from this table, and a test fails when a row has no fixture or the app has a screen (route, destination, Textual screen, or in Godot a node or scene added to the `screens` group, including panels built in code) the table lacks.

### 1.5 Numbers, budgets and declarations

- **Targets** are written down before the round or benchmark that measures them. Defaults are floors: going below one needs evidence that the best products of the kind don't do better (10.4), recorded in the profile.
- **Budgets:** start-up, interaction latency, frame rate and pacing, memory, download and install size, web bundle size, router CPU and storage, battery or energy, network use (P, GM6), each with a regression tolerance (default 5 %, or the measurement's own noise if wider; performance values are the median of at least 10 runs).
- **The benchmark walk:** a scripted route through the main tasks that includes the heaviest screens, scenes and data sizes (Walkdown's biggest sheet; Plant's heaviest scene on the oldest phone; a state file 10 times the real one).
- **Real-data evaluations** (Z1): the private, local checks on real data that the product's quality depends on (Walkdown: the reader's accuracy per sheet and the find-a-tag benchmark on the real largest sheet; tele-notify: precision and recall from `telenotify eval`). Each is measured on a fixed, versioned snapshot of the real data, and ratchets (10.1, 10.3) on one combined score the profile names (for tele-notify, an F-score with the weight between precision and recall set in the profile, weighted for what a wrong result costs every recipient). A change that trades one component for another needs my OK in the PR. Only I cut a new snapshot; for one release after a new snapshot, a change's score is reported on both the old and the new, and neither may fall. Each snapshot has a held-out part whose per-item results the author never sees: it's stored encrypted outside every repository, on my machine only, is never given to CI, and its key is given only when I run the evaluation; an agent reports the visible part's score, and I run the held-out part at release; only the held-out score ratchets, so tuning can't overfit. Where a project keeps evaluation numbers out of tracked files (Walkdown's `CLAUDE.local.md`), the baseline lives there and the PR states only pass or fail against it. The held-out run is due at each release, or at the end of each cycle for a product that deploys on merge; a fall counts only beyond the profile's held-out tolerance (at least one item, or the bootstrap 90 % interval). Then the agent lists every change to the evaluated feature merged since the last held-out pass, with its effect on the visible part, and builds each candidate (main with that one change reverted); I run the held-out part on them as one owner-check item with an estimate. If that isn't done within one cycle, the whole set is reverted. Security, crash and data-loss fixes are never reverted for score, and their cost becomes a tracked item; until the score recovers, no change to the evaluated feature merges except the recovery.
- **Owner budget:** the minutes per month I give this product. Every owner-check item carries an estimate; when the queued estimates for the next release exceed the budget, the agent proposes a batch for the release check, highest risk first, and the rest wait. Rounds with users (8.6) default to twice a year for pre-release products. A check I skip is recorded as skipped, never as OK.
- **First run:** the most screens allowed before the first main task (default 3, not counting legally required consent and GM8.2's settings).
- **Declarations:** a named design choice that relaxes listed rules and replaces them with a fallback. Only these exist; a new one is a policy change (11.1).

| Declaration                                                                | Relaxes                                                                                            | Fallback that must exist                                                                                                                            |
| -------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Designed obscurity** (a game's puzzles and secrets)                      | U1's "only what the product shows", GM4.3, GM3.2's "what to try"                                   | An optional hint or objective system, off by default, that can lead any player through the main content; secrets may stay hidden, main tasks never. |
| **Designed save tension** (permadeath, limited saves)                      | GM5.2's limit on progress lost; S1 for runs                                                        | A suspend save on quit and a crash-recovery save that can't be reloaded at will; the player is told before starting.                                |
| **Designed challenge** (the challenge is the point)                        | GM2.1's mid-game changes where the design forbids them, and skips, which a hint system may replace | An assist for every kind of failure still exists (GM2.1), offered without judgement.                                                                |
| **Realistic training** (a simulator teaching a real procedure, like Plant) | GM2.1's skips and invincibility inside assessed scenarios                                          | Practice modes with hints and assists exist for every scenario; the assessed mode says what it doesn't allow and why.                               |
| **Expert tool** (users trained in the domain, like Walkdown's engineers)   | U1's "no outside documentation" (the named training may be used); H1's time                        | The training is named and available; domain words (KKS, P&ID) are in the glossary (W1).                                                             |

### 1.6 Evidence and design system

- The **design system:** where tokens (colour, type, spacing, radius, motion), components, patterns, the glossary and the voice live (C1). On GNOME and Android this is mostly the platform's own (libadwaita, Material 3) plus the product's additions.
- The **evidence tools** per platform (8.3), the **synthetic data** set (Z1), and the **evidence store**: where baselines and audits live (the repository, the wiki, or a release asset, wherever the project's CLAUDE.md puts reports). Each release's baseline is kept with that release while it's supported.
- The **applicability list:** every N/A rule, per platform, with its reason. N/A for a whole user group of 1.1 needs an outside reviewer's agreement (9.6).
- **Accepted Not-checked reasons** (9.3), each with an expiry, and the release they're due by. A reason that is "needs hardware I don't own" (an iPhone for VoiceOver) may be renewed without a removal plan and doesn't count toward 9.6's cap; it's listed in the README's accessibility statement (T11). It never covers the profile's oldest supported or typical device, or a first-class input: owning, borrowing or renting time on those is part of supporting them, and if none is reachable, the profile drops that device (a narrowing).
- **Third-party surfaces** shown in the product but made by others (Telegram's own UI around the bot, MangaDex covers and titles, a system file picker, a web view), and how a change on their side would be noticed.
- The **review brief:** the instructions given to reviewer subagents, versioned here, not edited per change.

### 1.7 Reviewing the profile

The first profile, and every edit that narrows it (removes a user group, input, platform, assistive technology or main task; loosens a number; lowers the stage; or adds an N/A or an accepted Not-checked reason), gets both review passes (8.4). The reviewers check the floors in 1.1, 1.2 and 1.4, the screen groups and the applicability list. A narrowing never excuses fails already found. Widening needs only me. Rows and main tasks for what a change itself adds are part of that change and get its passes, and the coverage test reads the profile from the PR.

## 2. Principles

They explain the rules. When a case isn't covered, decide by them, in this order, and record the decision.

1. **Do no harm.** Never lose the user's work, data, access or trust; never cause an effect they didn't ask for (especially on a live system: a router, a server, a running bot).
2. **Everyone in the profile can use it,** including in sun, with gloves, with one hand, without sight, in Arabic.
3. **The task and the experience, not the interface.** Every element earns its place by helping a task or the intended experience.
4. **Few concepts, well made.** Removing is as valuable as adding.
5. **Show the state.** Where am I, what's happening, what just happened, what can I do next; in a CLI too.
6. **Recognition over recall.** Options, keys and next steps are visible or one obvious step away.
7. **Forgive.** Undo, back, cancel, drafts, autosave, checkpoints, dry runs.
8. **Platform first.** Use what GNOME, Android, the browser, Godot and Textual already provide before building your own; it brings accessibility, consistency and less code (my evidence-first engineering policies say the same).
9. **Fast, and feels fast.** Respond at once, finish quickly, never freeze, stay small.
10. **Feel matters.** Every core interaction is crafted: timing, motion, sound and touch confirm it.
11. **Calm by default.** Interrupt only for what matters to the user now.
12. **Honest.** No dark patterns, ever, even in a tool only I use.

## 3. Core rules: tasks, structure and look

### 3.1 Tasks and efficiency (U)

- **U1 (Block) Every main task can be done.** Each main task can be completed on every first-class input method and platform, from a fresh install and from a returning user's state, by following only what the product shows (no hidden gesture, no outside documentation), except as a declaration allows.
  - Check: a scripted run of each touched main task per first-class input method (Playwright, Compose UI tests, AT-SPI or UIA scripts, Godot input scripts, Textual pilot), recorded (8.3).
- **U1a (Block) Every offered task can be done.** Every task the interface offers, main or not (exporting, editing a saved device, changing a setting), can be completed on every first-class input method.
- **U2 (Block) Main tasks meet their targets** in the latest round with users (8.6): no participant in the profile's main group failed a touched main task without help, and the time and action targets are met. For a game, each touched part feels as intended and the share of players finishing is near the target. A round that misses blocks further changes to that task, except a change aimed at the cause of the miss, which ships and is checked in the next round.
- **U3 (Advice) Task cost doesn't creep.** For each main task, the action count and the expert time are recorded by the scripted runs. A change that raises either gives a reason in its results table; a rise without one fails. Deliberate waits (a confirmation delay, designed pacing) don't count.
- **U4 (Advice) Frequent things are fast.** A task done daily takes at most 3 actions from where the user usually is, or has a shortcut with a visible alternative. A command palette or search counts only as N4 allows.
- **U5 (Block) No dead ends.** Every screen has a visible way forward or back. No state can only be left by quitting, restarting, killing the process or waiting for a timeout. Where users can install mods, themes or plugins that change the UI, a reset to the default UI is reachable even when the changed UI is broken.
- **U6 (Advice) Sensible defaults.** Each setting starts with the value most users want. Where safe or private differs from popular, safe and private win. Nothing spends the user's metered data or battery heavily by default without saying so. Quality settings (graphics, image size) default to what the device can sustain.
- **U7 (Advice) Context is kept.** Returning to a screen restores its scroll position, filters, selection, tab and draft within a session, and across restarts where the profile says so.

### 3.2 Structure and navigation (N)

- **N1 (Block) Users know where they are.** Every screen has a title, a selected navigation item (a view switcher, tab, sidebar row) or another persistent marker, unless the product has one screen or the screen is a game scene (GM4.3 applies there).
- **N2 (Block) Back and close behave.** The platform's back (Android Back and predictive back, browser Back and Alt+Left, the gamepad's cancel button, `esc` in a TUI) closes the top layer first (dialog, sheet, popover, menu), then returns to the previous screen. Escape closes the top layer (dialog, popover, menu, search) first. On the web and Windows it never navigates back; on GNOME it follows libadwaita, where in a navigation view it pops a subpage (`pop-on-escape`), except where the page holds typed input that would be lost, which asks first (S3). It never leaves the product or drops typed input without asking (S3). Every overlay has a visible close control too, unless it closes itself and holds nothing the user must read.
  - Check: press back on every layer of every touched screen; record what comes next.
- **N3 (Block) Close and back never scroll away.** A panel, dialog, sheet or full-screen view with a Close, Back, Cancel or Done control keeps it visible however far its content scrolls, at every supported size.
- **N4 (Advice) Shallow, in users' words.** Main tasks are at most 2 levels deep from the main screen. A command palette or search reaching a task counts as level 1 only if the task can also be reached through visible navigation, or the palette's entry point is visible on every screen. Labels use users' words, not my code's names.
- **N5 (Block) Addresses work and last.** In web apps, each screen in the screen table and each item (a sheet, a tag, a manga, a chapter) has its own URL that opens it after a reload or sign-in; old URLs keep working or redirect. Android and GNOME apps that receive links or files open them at the right item. A link, file or intent from outside (a `walkdown-plant://join/…` link in a chat) opens and shows what it will do; anything that joins, sends, deletes, changes a setting or starts a live action waits for the user's confirmation (S6).
- **N6 (Advice) Search where things are many.** A list that can hold over 50 items, or a product with over 20 screens or settings, has search or a filter that matches users' words, ignores case and accents (and Arabic letter forms and diacritics), tolerates small typos, and says when nothing is found and what to try.
- **N7 (Block) Modals are rare.** A modal interrupts only for a decision the user must make now, something they can't miss (safety, data loss), or a flow they started. Also allowed, once each and dismissable in one action: first-run onboarding (H1), an explainer just before a system permission prompt (O1), and "what's new" after an update moved a main task's control (D3). Modals never stack more than two deep.

### 3.3 Visual design (V)

How it looks is part of how it works. These rules make the checkable parts checkable; my rubric (8.5) and users (8.6) judge the rest. On GNOME and Android, the platform's design (libadwaita, Material 3) is the starting point and V3 to V6 are mostly met by using it as intended.

- **V1 (Block) Every screen in the screen table has an intent, and the look follows it.** The things its intent order names stand out in that order.
  - Check: the blur test. Blur the screenshot (Gaussian, radius about 1/80 of its width) and list the first three things that stand out; they match the intent order. The blurred image goes in the evidence.
- **V2 (Block) At most one primary action per view.** At most one control per screen, dialog or panel is styled as primary (`suggested-action`, a filled Material button, the page's primary style). A destructive action is styled as destructive, never as primary, except in a dialog whose only purpose is that destruction, which the user started; even then, the default and the initial focus are the safe choice (S2).
- **V3 (Block) Tokens, not literals.** Colours, type sizes, spacing, radii and durations come from the platform's or the design system's named values (libadwaita's named colours and style classes, the Material theme, CSS custom properties, Textual's theme variables, a Godot theme resource), not literal values in components. Exceptions are listed in the design system with reasons.
  - Check: scan UI code, CSS and `.tscn`/`.tres` files for colour literals and raw sizes outside the token files.
- **V4 (Block) A spacing scale and alignment.** Spacing uses only the scale's steps (for example 6, 12, 18, 24 px on GNOME, as libadwaita does; 4, 8, 12, 16, 24, 32 dp on Android and the web; 0, 1, 2 cells in a terminal), and edges meant to line up do (within 1 px or 0 cells).
- **V5 (Block) A type scale.** UI text uses the platform's type scale (libadwaita's style classes, Material's type roles; the platform's full scale is allowed) or the design system's own scale, which has at most 6 sizes, and per script at most 3 families (a display, a text and a monospace; fallback fonts for other scripts don't count). Long reading text (paragraphs of three or more lines, such as manuals and course pages) has lines of at most 80 characters (40 for CJK) and a line height of at least 1.5 (stricter than WCAG AA: these are 1.4.8's numbers, AAA). Text stays readable when users widen spacing as WCAG 1.4.12 describes.
- **V6 (Block) Colour with a job.** Each colour role (background, surface, text, muted text, accent, success, warning, error, focus, selection) has one meaning and is used for nothing else, and a state has the same colour on every screen and platform of the product. Colours users pick themselves are exempt, A5 still applying.
- **V7 (Advice) Density fits the users.** Dense where people work daily (Walkdown's admin, a TUI), airy where they visit rarely (setup, settings). Space groups related things.
- **V8 (Block) Space is used.** At the largest supported size, the main content uses at least 60 % of the window in its main direction, or is capped for reading (V5) with the rest left empty by design; at the smallest, nothing the screen table says must be visible is cut off, overlapped or pushed off screen. Adaptive layouts change at the platform's breakpoints (libadwaita breakpoints, Compose window size classes, CSS media queries).
- **V9 (Advice) Icons are clear.** One icon set and style (the platform's symbolic icons on GNOME, Material Symbols on Android); one meaning per icon; an icon without a label only for actions everyone recognises (close, back, search, menu, settings, play), always with a tooltip and an accessible name.
- **V10 (Advice) Images are sharp.** Served at the screen's density; never stretched, blurry or cropped through the important part; with a same-size placeholder while loading (P4).
- **V11 (Block) Motion has a purpose.** Animation shows a change of state, where something came from or went, or feedback. UI transitions take 100 to 500 ms (the platform's own animations count; game feel and cinematics may differ), use easing, can be interrupted, never delay a task, and respect reduced motion (A11).
- **V12 (Advice) Polish.** In the evidence, no misaligned element, inconsistent corner, orphaned word in a heading, stretched image, off-palette colour, unstyled state (hover, pressed, focused, disabled, selected, loading, error, empty) or placeholder text. Each one found is a fail.
- **V13 (Block) Before and after are compared.** A change that alters a screen's layout or style has before-and-after shots side by side (the hero set, 8.3). In tiers 2 and 3 I judge them before the release (8.5), so V13 gates the release, not the merge; in tier 1 the reviewer judges them before the merge and passes anything judged worse to me. A change I judge worse fails, whatever else passes.
- **V14 (Block) Core interactions have a feel spec.** Each core interaction (1.3) has a short written spec: response time, motion, sound, haptics, and what success and failure feel like, naming the reference product's equivalent interaction. A change touching it is checked against the spec, on a real device, side by side with the reference (8.5).
- **V15 (Block) Charts tell the truth.** Charts and gauges label axes and units, start bars at zero, avoid 3D and area distortion, tell series apart without colour (A5), and offer the numbers as text.

## 4. Core rules: access

Numbers come from WCAG 2.2 (https://www.w3.org/TR/WCAG22/), the platforms' guidelines, the Game Accessibility Guidelines (https://gameaccessibilityguidelines.com/) and the Xbox Accessibility Guidelines (XAG, https://learn.microsoft.com/en-us/gaming/accessibility/guidelines), which are the most precise public numbers for games on any platform.

- **A0 (Block) The baseline.** The product meets WCAG 2.2 level AA as applied to its platform (for apps and games that aren't web content, as W3C's WCAG2ICT guidance applies it), plus anything stricter that a law, client or employer names for it. The A-rules below are the parts with extra numbers or checks; A0 covers the rest (for example headings and labels, language of parts, images of text, input purpose, error suggestion).
  - Check: the WCAG 2.2 AA checklist in each full audit; the touched criteria in each change.

### 4.1 Seeing

- **A1 (Block) Text contrast.** At least 4.5:1 against what's behind it, 3:1 for large text (at least 24 px, or 18.66 px bold, at 100 % scale), in every supported theme and in high-contrast mode (WCAG 1.4.3). Disabled controls, decoration, logos and text inside a photo or drawing are exempt. Where users read in sun or on the plant floor, the profile raises codes, values and body text to 7:1 (WCAG 1.4.6).
  - Check: compute the ratio from the colours the code sets; for text over photos, video or a 3D scene, sample the glyphs' core pixels against the brightest and darkest background that can appear behind them.
- **A2 (Block) Non-text contrast.** Borders of unfilled controls, icons that are a control's only label, focus indicators, selection highlights, chart lines and state indicators reach 3:1 against their neighbours (WCAG 1.4.11).
- **A3 (Block) Minimum text sizes.** The profile may raise these:
  - web: body at least 16 CSS px, nothing under 12 px;
  - GNOME and Windows: body at the system's interface font size, nothing under 11 px (GNOME; this policy's own number) or 8 pt Segoe UI (Windows) at 100 % scaling;
  - Android: body at least 14 sp, nothing under 12 sp (stricter than Material 3, whose smallest label is 11 sp; where a Material component's default text role is under 12 sp, such as a badge, the theme overrides it);
  - Godot games, measured as text height from the lowest descender to the highest ascender (XAG 101): at least 18 px at 1080p on desktop (36 px at 4K); on phones, at the phone's default UI size, body text at least the size Android's 14 sp gives on that screen (nothing under 12 sp), and at the largest UI-size step, at least XAG 101's mobile number (a body height of 18 px per 100 DPI, from the screen's physical density, `xdpi` in `adb shell dumpsys display`, not `wm density`, which changes with the Display size setting), all converted through the game's canvas stretch to the real screen (looser than XAG 101, which asks for its mobile number by default: on a 400 DPI phone that would crowd the screen, so the default follows Android instead);
  - Arabic: body text in Arabic is at least 1.15 times the Latin minimum on each platform (this policy's own number, for Arabic's smaller x-height and vowel marks), with a line height of at least 1.5 where vowel marks appear. It's met by the font, never by resizing single mixed strings: an Arabic font with a matched design size, or a per-font adjustment (`size-adjust` on the web; a matched Arabic UI font in the GTK, Android or Godot font fallbacks); where none exists, it's Not checked with an accepted reason, tracked like a hardware reason (9.3: severity 3, renewable, listed in T11's statement);
  - terminals: the user's font; the app never needs a smaller one.
- **A4 (Block) Text scales.** The product follows the system's text size (GNOME Large Text, Android font scale, browser zoom, Windows text size), or offers its own text-size setting where it can't (Godot) with at least three steps up to 200 %. At 200 % browser zoom (WCAG 1.4.4), Android font scale 2.0, GNOME text scaling 2.0 (Large Text, 1.25, is the first check), Windows text size 200 %, or the game's 200 %, all text and controls are present, nothing is clipped or overlaps, and scrolling is needed in one direction only (WCAG 1.4.10, at 320 CSS px on the web), except for drawings, maps and wide tables.
- **A5 (Block) Colour is never the only signal.** Every state shown by colour (error, selected, verdict, online, correct answer, an alarm's priority, a chart series) also has a word, icon, shape, pattern or position.
  - Check: every touched screen in greyscale and in deuteranopia, protanopia and tritanopia simulations; every state is still told apart.
- **A6 (Block) Text over pictures has a backing.** Text over photos, drawings, video or a game scene sits on a panel, scrim, outline or shadow that gives A1 against the brightest and darkest content behind it (Plant: the sky at noon and at night).
- **A7 (Block) Dark and light.** The product follows the system's dark setting (libadwaita's style manager, Android's dark theme, `prefers-color-scheme`, Textual's dark and light themes) or offers its own; each theme meets A1, A2 and A5; no white flash when a screen opens in dark mode. A product that is dark by design (a game) meets them as it is.
- **A8 (Block) Screen readers.** For the screen readers in the profile (Orca, TalkBack, Narrator, NVDA on the web where the profile names it): every control has a name, role, state and value; the visible label is part of the accessible name (WCAG 2.5.3); meaningful images have a text alternative; decoration is hidden; reading and focus order follow the visual order; headings mark structure; status messages are announced without moving focus (WCAG 4.1.2, 4.1.3). Godot UI names its controls (`accessibility_name` where the text isn't enough) for AccessKit on desktops; on Android, until the engine version in use supports AccessKit there (Godot 4.8 announces it), the profile records that gap (T11); it's rechecked at each engine upgrade and closes when support exists.
  - Check: the accessibility tree (Playwright `ariaSnapshot()`, an AT-SPI dump, the UIA tree, `uiautomator dump`, Compose semantics in tests) of each touched screen has no unnamed control; each touched main task is run with the screen reader where a device or headless session allows.
- **A9 (Block) Magnification.** With the platform's magnifier (or 400 % web zoom at 1280 px), focus and the caret are followed, and content shown on hover or focus can be reached, stays while hovered, and can be dismissed (WCAG 1.4.13).
- **A10 (Block) No seizures.** Nothing flashes more than 3 times in any second above the general and red flash thresholds (WCAG 2.3.1). Game scenes and videos with flashing, strobing or fast full-screen changes also pass a photosensitive-epilepsy analysis (a Harding-style tool, such as the free PEAT on Windows or EA's open-source IRIS, which runs on Linux, run on a video capture of the scene).
- **A11 (Block) Reduced motion.** With the system's reduced-motion setting on (GNOME `gtk-enable-animations` off, or `gtk-interface-reduced-motion` set to reduce in GTK 4.22 and later, which GTK CSS sees as `prefers-reduced-motion`; Android Remove animations, `prefers-reduced-motion`, Windows animation effects off, or the game's own setting; the platform widgets' own reduced-motion behaviour counts as compliant, and a gap in it is an upstream tracked item, not an app override), nothing slides, zooms, parallaxes or sways that isn't needed to understand the change. Moving or scrolling content that starts by itself and lasts over 5 s, and any auto-updating content that starts by itself, can be paused, stopped or hidden (WCAG 2.2.2).
- **A12 (Block) Sight isn't required.** Unless the applicability list (1.6) records it as N/A with an outside reviewer's agreement: Every main task has a non-visual path (screen reader, text alternative such as a drawing's tag list, audio cues, haptics). In a game, a reason GM9 accepts also covers A12 for the parts of play it names.

### 4.2 Hearing

- **A13 (Block) Sound is never the only signal.** Every sound that carries information (an alert, an alarm in Plant, a transfer finished, a teammate's call) also has a visual or haptic cue.
- **A14 (Block) Captions.** All speech in videos, voice lines and course media is captioned, with speakers named and important sounds described ("[pump starts]"). Captions are on by default or can be set before any speech plays; they scale to 200 % (XAG 104) in at least three steps (Game Accessibility Guidelines); their background's opacity is adjustable from 0 to 100 % (XAG 104); at most 2 lines of about 40 characters (XAG 104; the BBC's broadcast guidance is about 37); at most 160 to 180 words per minute for adults (BBC), slower for children.
- **A15 (Block) Audio description.** Prerecorded video that shows information only visually (a tutorial, a training video) has audio description (WCAG 1.2.5, AA). A text transcript alone meets only Level A (1.2.3).
- **A16 (Block) Volumes.** A product with more than one kind of sound sets each kind's volume and mutes each (at least master, music, effects, voice in a game); mono audio is offered where stereo position carries meaning; no loudness jumps the content didn't intend (games: about -24 LUFS on desktop and -18 LUFS on mobile, per the Audio Standards Working Group's ASWG-R001); sound never starts on launch unless expected (a game) and never plays over the user's own media without asking.

### 4.3 Moving and touching

- **A18 (Block) Every first-class input method does every task** alone (WCAG 2.1.1 for the keyboard). Typing text is exempt for methods that can't type if the platform's text input (on-screen keyboard) works.
- **A19 (Block) Target sizes.** Touch targets at least 48 × 48 dp on Android, 44 × 44 CSS px on the web at phone width (Apple's 44 pt, for iPhones using the web app), or the profile's larger number (gloves); pointer targets at least 24 × 24 px with WCAG 2.5.8's exceptions; hit areas never overlap, except in dense content the user can zoom (a drawing, a map, a timeline) or where an ambiguous tap opens a picker; a destructive target is at least 8 dp or px from any other.
  - Check: every interactive element's bounds from the layout or accessibility tree, in the platform's unit.
- **A20 (Block) Simple alternatives to gestures and motion.** Anything done by dragging, pinching, multi-finger gestures, long-pressing or a path-based gesture can also be done with single taps, clicks or presses (WCAG 2.5.1, 2.5.7); anything done by moving the device can also be done with a control, and the motion can be turned off (WCAG 2.5.4). Exempt where the gesture is the point (freehand drawing; a game's stick or aim), where GM1.4's assists apply.
- **A21 (Block) Time limits the user can change.** Any time limit the user didn't choose (a session timeout, an auto-advancing screen, a timed message with an action, a timed step in a scenario that isn't the point of the exercise) can be turned off, extended to at least 10 times the default, or extended with a simple action after at least 20 s warning (WCAG 2.2.1). A timeout a security standard requires is met by the warning and extension. A game's core real-time challenge is exempt; GM2 applies.
- **A22 (Block) No hold, mash or chord required.** Every action that needs holding, rapid presses or several inputs at once has a toggle or single-press alternative, at least in settings (games: GM1.4).
- **A23 (Block) Focus is visible and never hidden.** Keyboard and gamepad focus is always visible (at least 2 px thick or the platform's own focus ring; the indicator changes its pixels by at least 3:1 between focused and unfocused, as WCAG 2.4.13 (AAA) measures it, and meets A2 against its neighbours), never covered by a header, toast, bar or overlay (stricter than WCAG 2.4.11 AA; matches 2.4.12 AAA), never trapped (WCAG 2.1.2), and moves in reading order. Opening a dialog moves focus into it; closing it returns focus to where it was.

### 4.4 Understanding

- **A24 (Block) Plain language.** Text is written for the least expert main user group, at about CEFR B1 (US grade 8) unless the profile says otherwise: short sentences, common words, one idea per sentence, no unexplained jargon or abbreviations. Domain words the users know (KKS, P&ID, VPN) are allowed; they're in the glossary and explained on first use where a novice may meet them. Where pre-readers use it, instructions are also shown as pictures.
- **A25 (Block) Predictable.** Focusing or changing a field never triggers a big change by itself (navigation, submitting, a new window) (WCAG 3.2.1, 3.2.2); a component behaves the same everywhere; help is in the same place on every screen (WCAG 3.2.6; this policy also requires help to exist, H2).
- **A26 (Block) Nothing to remember or re-enter.** Information already given in a process is filled in or offered (WCAG 3.3.7); signing in, pairing or joining never needs a memory or transcription test without paste, a QR code, a password manager or another method (WCAG 3.3.8).
- **A27 (Advice) One thing at a time.** Complex tasks (setup, pairing, a long form) are split into steps with progress shown; each step has one question or decision.
- **A28 (Block) Usable with cognitive disabilities.** Main tasks pass a cognitive walkthrough by the reviewer, using the least experienced user and someone with memory or attention difficulties as personas. Where people struggle in a round (8.6), a simpler path or an assist is added.

### 4.5 Documents and haptics

- **A29 (Block) Generated documents are accessible.** Documents a product generates (PDF exports and reports, audit files, receipts) have real text, a logical reading order, headings, alternative text for meaningful images, and the language set (tagged PDF).
- **A30 (Block) Haptics are optional.** Haptics follow the system's vibration settings, can be turned off or weakened in the product, and never carry information alone.

## 5. Core rules: behaviour

### 5.1 Input and interaction (I)

- **I1 (Block) Controls look like what they do.** Interactive things look interactive and nothing else does. Each control shows each of its states: normal, hover (pointer platforms), focused, pressed, selected, disabled, loading.
- **I2 (Block) Platform controls first.** The platform's widgets do the standard jobs (libadwaita rows, toasts, dialogs; Material 3 components; native HTML elements; Godot's Control nodes; Textual widgets; Win32 standard controls). A custom one needs a recorded reason and matches the standard's keyboard, focus, accessibility and state behaviour.
- **I3 (Block) Shortcuts are discoverable and safe.** Every shortcut appears in a tooltip, menu, key bar or the shortcuts window (on GNOME, `AdwShortcutsDialog` from libadwaita 1.8, or `GtkShortcutsWindow` on older runtimes), never only in the README. Shortcuts never fire while the user types in a text field. Single-key shortcuts can be turned off or remapped (WCAG 2.1.4). The platform's reserved shortcuts and gestures keep their meaning (`ctrl+c`, `ctrl+q`, Android's back gesture).
- **I4 (Block) Disabled things say why.** A control that can't act now is hidden or disabled; one the user expects to use says why and how to make it work (a tooltip, a note, an explanation on press).
- **I5 (Block) Values can be copied.** Values users reuse (KKS codes, IDs, device names and fingerprints, addresses, links, error references, version numbers, commands to run) can be selected and copied by the platform's normal means or a Copy button; exactly the value is copied (no label, no spaces, no direction marks); the product confirms the copy unless the platform does (Android 13 and later show their own).
- **I6 (Advice) Direct manipulation where it helps.** Where users arrange, resize or reorder, they can drag (with A20's alternative), see where it will land, and cancel with Escape or by dropping outside.
- **I7 (Block) Inputs mix freely.** Hover-only content is reachable by touch and keyboard; switching input mid-session (mouse to gamepad, touch to keyboard) updates the prompts and hints at once.
- **I8 (Block) Tables work.** Where a main task uses a table of records (Walkdown's admin, a list of devices or keywords): columns can be sorted and filtered, headers stay visible while scrolling, a wide table scrolls sideways inside its own area with the first column pinned, the keyboard can move through it, and the current view can be copied or exported.
- **I9 (Block) History is visible.** Where several people, devices or automations change shared data (Walkdown's synced log, the bot's decisions), users can see who or what changed what and when, and revert a change where it can be reversed.

### 5.2 Feedback and performance (F, P)

- **F1 (Block) Every action gets a response.** Every action changes something perceivable within 100 ms (a pressed state, a cursor, a sound or vibration with A13, the result). Work over 1 s shows that it's going on and on what ("Importing sheet 3 of 7"); over 10 s, it shows progress where it can be known and lets the user cancel or carry on with other things.
- **F2 (Block) Results the user can't see are confirmed in words.** An action whose result isn't visible where the user is looking (sending a file, syncing, saving to the router, a background job) says what happened ("Sent to Pixel 8", "3 notes synced") where the user is looking. Direct manipulation whose result shows in place needs no message. A message with an action (Undo) stays while it has focus or hover and follows A21; one without lasts at least 4 s, plus 1 s per 10 words over 20.
- **F3 (Block) Optimistic updates are honest.** A result shown before it's confirmed (by the server, the other device, the router), if it then fails, is marked failed on the item with a retry; it never silently reverts.
- **F4 (Block) Status is visible.** States that change what the user can do (offline, syncing, items waiting to sync, saving, a transfer running, connected or not, dry-run or test mode, the real bot or the dry run, unsaved changes, someone else editing) are visible while true.
- **P1 (Block) No freezes.** No interaction blocks the UI thread or event loop for over 1 s on the oldest supported device during the benchmark walk; long work runs off it (coroutines on IO, worker threads, web workers, Godot threads, asyncio tasks).
  - Check: a long-task or slow-callback monitor during the benchmark walk (`PerformanceObserver` long tasks, Android `gfxinfo`, asyncio debug mode's `slow_callback_duration`, the Godot profiler, a GLib main-loop watchdog).
- **P2 (Advice) No hitches.** No main-thread task over 100 ms while typing, scrolling, dragging or animating; scrolling and animation hold the display's frame rate (games: GM6).
- **P3 (Block) Start-up.** The first useful screen appears within the profile's budget (default: 2 s warm and 5 s cold on the oldest supported device; a game shows an interactive screen or a skippable splash within 5 s). A splash never hides a start the user could already use.
- **P4 (Block) Nothing jumps.** Content doesn't move under the user's finger or pointer once shown: no layout shift from late images or fonts (web: CLS at most 0.1); a list never inserts above what the user is looking at without keeping their place.
- **P5 (Block) Budgets don't regress.** Every budget in the profile (1.5) is measured on each change that could affect it; a regression beyond its tolerance needs a reason I approve and a tracked item. Web: LCP at most 2.5 s, CLS at most 0.1, and INP at most 200 ms, measured in the lab on the benchmark walk (median of 10 Playwright runs in Chromium with CPU throttling at the profile's slowest device, since my products collect no field data; where the profile lists iPhones, each release also times the walk on a real iPhone, an owner-check item): INP as the longest event duration over the walk's scripted interactions (the Event Timing API, or the `web-vitals` library's `onINP`), at most 200 ms, with Total Blocking Time also recorded for loading, at most 200 ms; and the profile's bundle budget (safe-otaku: the 30 KB gzipped of its AGENT.md). On a router, the product's CPU, memory and storage use stay within the profile's budget, because the router's job comes first.
- **P6 (Advice) Feels fast.** Waits over 1 s show skeletons or the previous content, not blank screens; likely next steps are prefetched where it's cheap. On router-served products, prefetch only what the browser will cache, with at most one prefetch request in flight at a time, started only when no request of the user's is waiting (the router's few request slots are shared with its admin page).
- **P7 (Block) Local is instant on main tasks.** Interactions that need no network or heavy work (switching tabs or pages already loaded, toggles, typing, opening menus) complete within 100 ms on the typical device and 200 ms on the oldest one. (Advice elsewhere.)

### 5.3 Writing (W)

- **W1 (Block) Users' words, one word per thing.** Labels, messages and help use users' words, the same word for the same thing everywhere and on every platform of the product (the glossary in the design system), and the platform's standard words for standard actions (GNOME and Android both say Cancel, not Abort).
- **W2 (Block) Buttons say what they do.** Buttons and menu items name the result ("Send 3 files", "Remove device", "Start scenario"), never "OK", "Yes", "Submit" or "Click here" where a precise word fits.
- **W3 (Block) Errors in plain words.** An error says what happened, what it means for the user's work and what to do next, without blame ("Couldn't reach the server. Your note is saved on this phone and will be sent when you're back online."). Never a raw exception, stack trace, errno, HTTP status or protocol name as the message; technical detail may follow behind "Details" or in a log, and a reference can be copied (I5).
- **W4 (Advice) Short and scannable.** Labels put the important word first; sentence case (GNOME's and Material's convention); numbers as digits; no more words than needed.
- **W5 (Block) Counts, units, dates.** Counts are grammatical in every UI language ("1 file", "2 files"; Arabic has six plural forms); every physical value has its unit on the same line (bar, °C, MB/s); dates and times are unambiguous (2026-11-18 14:05, or the locale's long form), 24-hour unless the locale says otherwise, with the time zone where it could be misread.
- **W6 (Advice) One voice.** A short voice note in the design system; tone fits the moment (no jokes about lost work; no exclamation marks for routine confirmations).
- **W7 (Block) Never cut what matters.** Codes, identifiers, device names in a confirmation, amounts and anything needed to decide are never truncated; they wrap or scroll. Other text may be truncated if marked (an ellipsis) and the full text is one action away.

### 5.4 Forms and data entry (E)

- **E1 (Block) Visible labels.** Every field has a label that stays visible while typing (a placeholder isn't one); required or optional is marked, whichever is rarer.
- **E2 (Block) The right keyboard and help.** Fields use the right input type, keyboard and autofill hints (passwords, one-time codes, email); accept common formats (spaces or dashes in numbers, any case in codes, pasted values with spaces trimmed); and turn off autocorrect and auto-capitalisation for codes, names, URLs and commands (and turn on capitals for codes typed in capitals, such as KKS codes).
- **E3 (Block) Validation helps.** Errors appear at the field, name it and the fix, keep what was typed, and on submit move focus to the first field in error. Validation runs on leaving a field or on submit, not on each keystroke, except to show a requirement being met.
- **E4 (Block) Ask only what's needed.** Every field has a reason users would accept; nothing the product already knows is asked again; names of people and of things users name for themselves accept any script, characters and length, with one full-name field unless split names are needed. Identifiers that go into a system (hostnames, UCI section names, KKS codes, file names on a router) state their allowed characters before typing (E6) and suggest a valid form from what was typed.
- **E5 (Block) Never lose input.** Typed input survives a validation error, a network error, Back, rotation, the app going to the background, and Android killing it (saved state); long forms autosave drafts.
- **E6 (Advice) Constraints up front.** Limits, formats and allowed characters show before typing (a counter near a limit); controls prevent impossible values rather than rejecting them after.

### 5.5 Safety and recovery (S)

- **S1 (Block) Losing data is undoable or confirmed.** Deleting, discarding or overwriting what the user made or owns (a note, a photo, a device's trust, a keyword list, a saved answer) is undoable (an undo that covers it, a trash, or an Undo under F2 and A21), or asks first in a dialog that names the thing and the consequence. Actions that can't be undone at all (removing a device that then wipes its data, factory-resetting, sending to others, signing out with unsent changes) always ask first. In a command-line tool, `--yes` (or PowerShell's `-Confirm:$false`) given in that command is the confirmation (CLI3).
- **S2 (Block) Confirmations are safe.** The confirming button names its action ("Remove device", not "OK") and is styled destructive (libadwaita `destructive-action`, Material's error colour); the dialog names the object and the consequence; the default and initial focus are on the safe choice; the confirmation can't be triggered by a double press, a held key from the step before, or a tap where the opening button was. High-risk actions (removing a device, deleting a lot of data, wiping a router's config) need a deliberate act: typing the name, a second step, or a 1 to 2 s hold with visible progress that also offers a second step instead (A22).
- **S3 (Block) Work and progress are never lost silently.** Leaving a form, closing a window, quitting, signing out or the OS stopping the app keeps the work (a draft, autosave, a checkpoint) or asks first, saying what would be lost ("2 unsaved changes", "3 notes not yet synced").
- **S4 (Block) Errors recover.** After an error the user can retry, go back or carry on, with input and state kept; after a crash or update, the product restores the last state on restart where the platform allows.
- **S5 (Block) Bulk decisions.** A list that asks the same decision of many items (accept tags, approve sign-ups, remove photos) lets the user select several, or all that match a filter, and decide once, with the count on the button ("Accept 12 tags") and one undo or one confirmation for the batch, unless the profile records why each must be decided alone (tele-notify's review queue labels a corpus one post at a time).
- **S6 (Block) No hidden side effects.** No action does anything its label didn't say (sending, sharing, changing a setting elsewhere, restarting a service).
- **S7 (Block) Test and real are never confused.** Dry-run, preview, demo, staging and test modes are always visible as such; every action that would affect the real world (a router, a server, a running bot, another person's device) says whether it will.
- **S8 (Block) Live systems stay reachable.** A product that changes a live system (a router's network, a server's firewall, a running service) checks before applying that the change won't cut off the user's way back, applies it in a way that can be rolled back (a timed automatic rollback unless confirmed, a saved previous config), and reports PASS or FAIL for each part afterwards.
- **S9 (Block) Access can be recovered.** A user who loses a password, a paired device or a key can get back in, or start again without losing what is theirs, by a documented path shown in the product.

### 5.6 States (ST)

- **ST1 (Block) Every state is designed.** For each touched screen, the evidence shows it empty (first use, no results, cleared), loading, partial (some data failed), in error, offline (where the profile has offline use), with too much (the longest names in Arabic and English, 10 times the usual item count) and without permission (where one is needed). None is blank, an endless spinner, a raw error or a broken layout.
- **ST2 (Advice) Empty states teach.** An empty screen says why it's empty and what to do, with the action to do it ("No photos yet. Take one with the camera button.").
- **ST3 (Block) Offline is a state.** Where the profile has offline or local-only use, the product says it's offline, keeps working what can, shows how many changes wait to sync, syncs by itself when back, and reports conflicts in plain words, keeping both versions.
- **ST4 (Block) Failures are contained.** A failing service or peer, a missing or locked file, a corrupt save, a full disk, a denied permission, a missing command (`systemctl`, `adb`), or an old server shows a plain-words state on the affected part; the rest keeps working.
- **ST5 (Block) Others are visible.** Where several people or devices edit the same thing, the product shows who else is there or what changed, and never discards anyone's change silently.

## 6. Core rules: coherence, learning, attention, trust, change

### 6.1 Consistency and coherence (C)

- **C1 (Block) One design system per product.** Its tokens, components, patterns, glossary and voice are written down (often as "the platform's, plus these additions"); new components and patterns enter it before use.
- **C2 (Block) Same thing, same name, same look, same place** across a product's screens and platforms; each platform's conventions decide placement and look (header bar, top app bar, menu bar), never the words.
- **C3 (Block) Platform conventions are kept.** the GNOME HIG on GNOME, Material 3 and Android's system back on Android, Windows' conventions on Windows, the browser's on the web, the genre's and the controller's (confirm and cancel buttons) in games. Breaking one needs a reason in the design system and a check with users (8.1).
- **C4 (Block) Parity or a record.** A feature added on one platform of a product is on its others, or each gap is recorded as a tracked item or as a deliberate platform-only feature in the product's feature list.
- **C5 (Block) New concepts earn their place.** A change that adds a core object or verb (1.3), a top-level screen or a setting records why an existing one can't do the job, and updates the conceptual model.
- **C6 (Advice) Remove what doesn't earn its place.** Each full audit lists features, settings and screens that nobody uses, that confuse, or that duplicate others, as removal or merge candidates on the backlog.

### 6.2 Learning and help (H)

- **H1 (Block) First run.** A first-time user succeeds at the first main task within the profile's time (default 60 s; a game: playing within 60 s of the first input) and the first-run screen budget (1.5), without reading anything long. The 60 s clock excludes legally required consent, GM8.2's settings, one-time preparation (downloads, shader compilation, pairing a device), which shows progress, and waiting for someone else's approval (Walkdown's sign-up), which is a designed waiting state saying what happens next, about how long, and that the user will be told; installing and setup have their own targets as main tasks (1.4). Onboarding teaches by doing, can be skipped, and asks for nothing (an account, a permission) before the user has seen why, unless the task can't start without it.
- **H2 (Block) Help is findable.** Help (a help or about screen, the keys panel, a manual, the README's usage section) is reachable from every screen in the same place.
- **H3 (Advice) Teach in context.** Tips appear where and when useful, once, and can be turned off.
- **H4 (Block) What was taught can be looked up.** Anything onboarding or a tutorial taught can be found again without replaying it.
- **H5 (Advice) Grow with the user.** Experts get accelerators (shortcuts, search, a command palette, bulk actions) that beginners don't have to see.

### 6.3 Attention and notifications (O)

- **O1 (Block) Notifications are opt-in and earned.** Permission is asked in context, after a one-line explanation in the product; each kind can be turned off in the product.
- **O2 (Block) Each notification stands alone.** It says what happened and what to do, opens the exact related screen or item, isn't repeated, and many at once are grouped.
- **O3 (Block) Respect the moment.** Nothing interrupts a task in progress (typing, a transfer, a scenario, a confirmation) except a threat to the user's safety or data that gets worse with delay, or something the user asked for (an alert they set up, an incoming transfer they must accept); do-not-disturb is respected.
- **O4 (Advice) Badges mean something.** A badge shows a real, actionable count and clears when the user has seen what it points to.

### 6.4 Trust, privacy and ethics (T)

- **T0 (Block) The law's interface duties** (privacy notices, consent, children's protections, store rules, platform and API terms) are met for each place the product is offered. Check: against the profile's checklist of duties per place, which I keep; a question the checklist doesn't answer is an owner-check item, never a reviewer's Pass, and the change doesn't merge until I answer (T0 is never Not checked).
- **T1 (Block) No dark patterns.** None of: guilt-tripping "No" buttons, hidden costs, pre-ticked consent, fake urgency, nagging that can't be turned off, cancelling harder than starting, trick questions, a de-emphasised "No", sharing by default, or anything else from https://www.deceptive.design/types.
- **T2 (Block) Leaving is as easy as joining.** Removing an account, a device's pairing or a household member, opting out and exporting data take no more steps than setting them up, plus S2's confirmation, and are in the product.
- **T4 (Block) Permissions and data.** Each OS permission (nearby devices, location for Wi-Fi Direct, camera, storage, notifications) is asked when its feature needs it, after a plain-words reason; the product keeps working without it; what is collected, where it goes and who sees it is stated plainly. Nothing leaves the device or network without the user knowing.
- **T5 (Block) Privacy in the UI.** Secrets (passwords, keys, tokens, invite codes) are hidden by default with a way to show them, never logged, never echoed by a CLI except as a hand-over the user explicitly asks for (HAND1: shown once, to the terminal, or to a pipe or file the user named in that command, never to logs); private data is hidden in the app switcher where the platform allows (on Android 13 and later with `setRecentsScreenshotEnabled(false)`; `FLAG_SECURE`, which also blocks screenshots, only on screens that show secrets); before sharing or sending, the user sees who will receive it.
- **T6 (Block) Usable security.** Signing in and pairing support paste, password managers, QR codes and the platform's sign-in where they exist (A26); a fingerprint or code to compare is shown in a form people can compare (grouped, large, read aloud by screen readers in groups); security warnings are specific, rare and actionable. Install steps never ask users to trust a root certificate, turn off SmartScreen or Play Protect, or lower security machine-wide; a certificate goes to the narrowest store (Walkdown's MSIX: `LocalMachine\TrustedPeople`), and the uninstall steps say how to remove it.
- **T7 (Block) Untrusted content stays content.** Text, names, titles and files from outside (Telegram posts, MangaDex titles, file names from another device, chat titles, command output) can't change the UI around them: no markup, scripts, escape sequences, bidi overrides, or oversized content breaking layout outside its own area; links from others show their real destination before opening.
- **T8 (Block) Wellbeing.** No mechanic meant to keep users against their interest: no feed without an end, no streak without a recovery, no notification sent only to pull the user back, no reward that decays when they stop (except designed save tension, 1.5).
- **T9 (Block) Children.** Where children use the product (safe-otaku's household): no tracking or advertising; no contact with strangers; the strictest settings the profile's content policy (1.3) defines, by default, changed only behind a parent's control; data kept to what the feature needs (data minimisation, as in GDPR Article 5(1)(c)), with the consent rules for children (GDPR Article 8, or the local law) where they apply; anything a child sees explained at their level.
- **T11 (Block) Accessibility statement and barrier reports.** The README (and an about screen where there is one) says which accessibility features exist and which gaps are known, and how to report a barrier; a report starts as a severity-2 tracked item and is then rated by 9.5.
- **T12 (Block) Download pages are true.** README screenshots and store or release pages show the real product as of the latest release (refreshed at release when a main screen's shots in the hero set changed); download size, permissions and supported devices are stated before install; release notes say what changed for users.
- **T13 (Block) Republishing keeps its audience.** A product never republishes content to a wider audience than its source had (a private or members-only group to a public channel) unless the source is public or its admins allow it; the product shows me each source's audience when I add it, and re-checks it before each post (a channel can turn private); personal details beyond what the poster published to be found (phone numbers, names in private groups) are never carried along.

### 6.5 Settings, continuity and change (D)

- **D1 (Block) Settings stick.** Settings persist across restarts and updates (GSettings, DataStore, local storage, a Godot config file), and can be reset to default one at a time or all at once (S1).
- **D2 (Block) Settings are findable.** Grouped by the user's goals, searchable when there are over 20, each says what it does, and visual or audio ones preview their effect.
- **D3 (Block) Updates don't ambush.** An update that moves, renames or removes a main task's control says so in the product and the release notes, and where it went; a redesign of a core workflow offers a short "what's new" and, where practical, a way back for a release or two.
- **D4 (Block) Data is the user's.** Users can export what the product holds about them and their work in an open format (JSON, CSV, a standard archive) and import it again; saves, notes, settings and configs migrate across versions without loss.
- **D5 (Block) Interruptions lose nothing.** A call, a notification, switching apps, rotating, locking the screen, a controller disconnecting, a lost connection, or the OS killing the app brings the user back to the same place, state and input (games pause, GM5.1).
- **D6 (Block) Learned and scripted surfaces are contracts.** CLI flags, output formats, exit codes, config files, keybindings, gestures, save formats, URLs, and bot commands are versioned; a breaking change gets a deprecation warning for at least one release and a migration path; changed default keys keep the old ones as an option.
- **D7 (Block) Updates are offered, not forced.** A product's own updater shows what changed, can be postponed, never interrupts a task (O3), and a failed update leaves the previous version working. An update may be required only when the old version can no longer work safely or at all (a security fix; a protocol the server dropped after D6's deprecation); then the product says why and what still works offline, the update is one action away, and it's never required in the middle of a task.
- **D8 (Block) Uninstalling leaves nothing behind.** Uninstalling removes what the product added (services, polkit rules, certificates, autostart entries, file-manager extensions, router packages and cron entries), restores what it replaced (openwrt-oneclick: `dnsmasq-full` back to `dnsmasq`, and the previous configs), and says what user data it keeps and where; on a live system it follows S8 (checked before, rollback ready, PASS or FAIL after). Where the README's documented way back is the platform's own reset (OpenWrt's `firstboot` on a router the product set up from fresh), that counts, and the README names everything the reset also erases. On Android and Flatpak, the system's uninstall plus the README's note on kept data counts. The uninstall steps are tested on the VM.

### 6.6 AI and automation (AI)

Applies where a product generates, classifies, recognises, recommends or acts on its own (tele-notify's post filtering, Walkdown's reading of tags off drawings, any LLM-backed feature). Recognition results that users rely on are marked where their confidence is low, on every platform that shows them.

- **AI1 (Block) Labelled.** Users can tell what was generated or decided automatically, and know when they're dealing with an AI rather than a person.
- **AI2 (Block) Explained.** Each automatic decision has its reason one action away ("Matched: control engineer, Springfield").
- **AI3 (Block) The user stays in control.** An automated action that sends or changes something is previewed, confirmed or undoable (S1); automation can be paused or turned off; it never acts beyond what the user set up.
- **AI4 (Block) Honest about limits.** Output that may be wrong says so where the user will rely on it, and a failure says what to do instead. Users are told what of their data goes to which model or service.
- **AI5 (Advice) Correctable.** Users can correct a decision (mark a post as a miss), and corrections are used as promised.

### 6.7 Languages and scripts (L)

Arabic and English, separately and mixed, are normal in my users' content, so these rules matter in every product.

- **L1 (Block) Whole strings.** UI strings are whole translatable sentences with placeholders, kept outside the code (gettext, Android string resources, Godot translation files); plurals use each language's rules (Arabic's six forms); no text is baked into images unless they're translated too.
- **L2 (Block) Mixed and right-to-left text reads correctly.** User content gets automatic direction from its first strong character (`dir="auto"` or `<bdi>` on the web; Pango and Compose do it by default; Win32 sets reading order explicitly; terminals as the TUI module says) and is isolated from the UI around it, including where it's placed inside a sentence ("Sent to %s": wrapped in Unicode isolates U+2068 and U+2069, Android's `BidiFormatter.unicodeWrap`; in Godot too, whose text server honours the isolates), so an Arabic title can't reorder the label beside it; a code or number inside Arabic text keeps its characters in order. Where the UI itself is offered in Arabic, the layout mirrors (navigation, directional icons, progress), except what doesn't (media controls, numbers, code, clocks, maps).
  - Check: the synthetic fixtures `مضخة التغذية 11LAB70AA501 تعمل` and a mixed Arabic, English, number, link, emoji and bracket line, in every place user content shows.
- **L3 (Block) Layouts survive other text.** Every screen works with text 40 % longer than its English (up to 200 % for labels under 10 characters), with Arabic's taller marks and longer words, and with the longest real translation; nothing is clipped or overlaps (W7).
  - Check: automated clip and overlap detection on pseudo-localised and Arabic screenshots of the touched screens (text bounds against their containers, from the layout or accessibility tree).
- **L4 (Block) Local formats.** Dates, times, numbers and units follow the user's locale where the UI offers it (Arabic may use Arabic-Indic or Western digits; the user chooses where it matters); sorting and search follow the language (Arabic letter forms, alef variants and diacritics match their base forms).
- **L5 (Advice) Fonts cover the content.** Every script that can appear (Arabic, Latin, emoji, CJK names in manga titles) renders with a font that has its glyphs, with fallbacks set (a Godot theme's fallback fonts; the web's font stack).
- **L6 (Block) Translations are checked on screen.** Each UI language's main tasks are read on screen by a fluent speaker (me, for Arabic) before release.

## 7. Platform modules

Each project applies the modules for its platforms. Module rules weigh the same as core rules.

### 7.1 Web apps and PWAs (WEB)

- **WEB1 (Block) Full WCAG AA.** WCAG 2.2 AA in full (A0), including page titles, page language, bypassing repeated blocks (landmarks, headings or a skip link), link purpose, and autocomplete attributes on personal fields.
- **WEB2 (Block) Browser features work.** Browser features keep working: back and forward, reload keeps state where expected, open in new tab, bookmarks, zoom and text-only zoom, find in page, translation, printing for pages people print, and `prefers-color-scheme`, `prefers-reduced-motion` and `forced-colors`.
- **WEB3 (Block) Native elements first.** Native elements before custom ones (`<button>`, `<a>`, `<dialog>`, `<details>`, form controls), as my evidence-first web policy says; text fields at least 16 px (or iOS Safari zooms on focus); safe areas handled where `viewport-fit=cover` is used.
- **WEB4 (Block) Browsers and widths.** Works in the profile's browsers (Chromium, Firefox and WebKit by default) at phone width (412 × 915) and desktop width (1280 × 800). Opened from an iPhone's home screen, the web app has no browser Back button, so every panel has its own Back or Close (N2).
- **WEB5 (Block) Offline and updates.** A PWA works offline as its profile says (ST3), shows when a new version is ready and lets the user reload into it without losing input, and never serves a mix of old and new files.
- **WEB6 (Block) Small servers.** A web UI served by a router or another small device (safe-otaku) keeps within its device budget (P5) and the bundle budget; it works without any third-party script or CDN; and when the device's backend is busy or the upstream site fails, it says so in plain words (ST4).

### 7.2 GNOME apps (GNOME)

Source: the GNOME Human Interface Guidelines (https://developer.gnome.org/hig/).

- **GNOME1 (Block) libadwaita patterns.** libadwaita patterns first: a header bar with the window's main actions and a primary menu (with Keyboard Shortcuts, Preferences, About); `AdwToast` for confirmations (F2), where a toast that carries Undo keeps the default timeout (toasts queue, so one that never times out would hide the next) and the undo stays reachable by `Ctrl+Z` and the primary menu until the next action, which meets A21; `AdwAlertDialog` with `destructive` or `suggested` response appearance for decisions (S2); `AdwPreferencesDialog` for settings; boxed lists and action rows for lists; `AdwStatusPage` for empty and error states (ST1); `AdwViewStack` with an adaptive switcher for views.
- **GNOME2 (Block) Adaptive.** Adaptive from 360 × 294 logical px (the GNOME HIG's small size for phones) to 1024 × 600 and larger, using breakpoints; nothing is clipped at any size.
- **GNOME3 (Block) System style.** Follows the system's style (`AdwStyleManager`: light, dark, high contrast, accent colour), Large Text, animations off, and the interface font; the app sets no fixed colours outside libadwaita's named colours, except exceptions recorded under V3 (such as Direct-Share's black theme for OLED screens).
- **GNOME4 (Block) Accessible and keyboard.** Every control is reachable and named in AT-SPI (A8); a keyboard shortcuts dialog lists all shortcuts (I3); `Ctrl+Q` and `Ctrl+W` behave as GNOME expects; mnemonics on dialog buttons.
- **GNOME5 (Block) Text direction.** Text direction: `Gtk.Widget.set_default_direction` follows the UI language, and user content gets its direction from its own text (L2).
- **GNOME6 (Block) Privileges.** Privileged work goes through polkit with a message that names the action in plain words; the app never asks for a root password itself.
- Evidence: a headless GNOME session (never my desktop) for screenshots and AT-SPI dumps, one run at a time on my machine.

### 7.3 Android apps (AND)

Sources: Material 3 (https://m3.material.io/) and Android's accessibility guidance (https://developer.android.com/guide/topics/ui/accessibility).

- **AND1 (Block) Material and insets.** Material 3 components and theming, with dynamic colour where it doesn't break V6 or A1; edge-to-edge with insets handled (nothing under the status bar, navigation bar, cut-out or keyboard; the typed-in field stays visible).
- **AND2 (Block) Back.** System back and predictive back close the top layer first (N2); on the first screen, back leaves as the system does, asking only if input would be lost.
- **AND3 (Block) State survives.** Survives configuration changes and process death with state and input kept (E5, D5): checked by rotating, by switching dark mode, and by `adb shell am kill` on the backgrounded app.
- **AND4 (Block) Scale and size.** Font scale up to 2.0 (A4), both orientations unless one is essential (WCAG 1.3.4), and phone, foldable and tablet layouts by window size class, not a stretched phone.
- **AND5 (Block) Semantics and targets.** Compose semantics: every interactive element has a role and a label (`contentDescription` or merged text), touch targets are at least 48 dp (`minimumInteractiveComponentSize`), and status messages use live regions.
- **AND6 (Block) Permissions and background work.** Permissions per T4, using the system's dialogs; Wi-Fi Direct and local discovery use `NEARBY_WIFI_DEVICES` with `neverForLocation` on Android 13 and later, and ask for location only up to API 32, saying why; background work uses WorkManager or a foreground service with a visible notification that says what it's doing.
- **AND7 (Advice) Thumb reach.** Frequent actions are within thumb reach (the lower two thirds or a bottom bar) on phones.
- Evidence: the emulator (one at a time on my machine, never alongside a VM): screenshots in demo mode for the status bar, `uiautomator dump`, Compose UI tests; the oldest supported real phone for performance.

### 7.4 Windows apps (WIN)

- **WIN1 (Block) Controls, keys, themes.** Standard controls; keyboard access with Alt accelerators on menus and buttons; standard shortcuts; the system's colours in contrast themes, fully; text size up to 200 % without clipping (A4); per-monitor DPI awareness. Dark mode (A7): the title bar follows it (`DWMWA_USE_IMMERSIVE_DARK_MODE`) and areas the app draws itself (a drawing, course figures) follow the app's theme; dark common controls, which Win32 doesn't support, are Advice.
- **WIN2 (Block) UI Automation.** Every control is named in UI Automation (A8); Narrator reads the main tasks.
- **WIN3 (Block) Reading order.** Right-to-left and mixed text set their reading order explicitly (`WS_EX_RTLREADING`, `DWRITE_READING_DIRECTION_RIGHT_TO_LEFT`) from the text's first strong character (L2).
- Evidence: the test VMs, one at a time, with the UIA tree and screenshots.

### 7.5 Godot games and simulators (GM)

Sources: Game Accessibility Guidelines, XAG, AbleGamers' Accessible Player Experiences (https://accessible.games/accessible-player-experiences/), Godot's accessibility documentation.

**GM1 Controls**

- **GM1.1 (Block) Remapping.** Every gameplay action can be remapped on keyboard and mouse and on gamepad, including to a single button, with conflicts shown; menus stay usable with the default keys whatever the remap.
- **GM1.2 (Block) Prompts match the device** in use and the player's bindings, switching at once when the device changes (keyboard, gamepad, touch).
- **GM1.3 (Block) Sensitivity and inversion.** Look sensitivity (X and Y separately), axis inversion and dead zones are adjustable; vibration can be turned off and weakened (A30).
- **GM1.4 (Block) Alternatives to hard inputs.** Every hold has a toggle; every mash a hold or single press; every quick-time event can be slowed or made automatic; every simultaneous press has a sequential option.
- **GM1.5 (Block) Touch controls.** On touch screens, the sticks and buttons can be moved, resized and made more or less opaque, meet A19 in dp, and never cover a control or text the player needs.
- **GM1.6 (Advice) Conventions.** Default bindings follow the genre's conventions on each device; the controls list is always available from the pause menu.

**GM2 Challenge and assists**

- **GM2.1 (Block) Difficulty is a choice, not a judgement.** For each kind of failure that can block progress (execution, timing, reaction, knowledge of a procedure, finding the way, puzzle logic, endurance), at least one assist removes it (slower time, wider timing windows, hints, a route guide, a step checklist, a skip). Declarations (1.5) may limit skips. Assists can be changed mid-game, and they're described by what they change, without mocking.
- **GM2.2 (Block) Assists don't punish.** An assist never locks content; it may only mark a scored or assessed result as assisted, and says so before it's chosen.
- **GM2.3 (Advice) A curve.** Each mechanic or procedure step is introduced alone, then combined; spikes in difficulty are deliberate and come after a checkpoint. Check: where testers retried and quit (8.6).

**GM3 Readability and feel**

- **GM3.1 (Block) Threats and targets are readable.** Every hazard, interactable object and important part is told apart from the background and from harmless things by more than colour (A5), at the usual camera distance, in every lighting state the game ships (day, night, alarm lighting), each part of the benchmark walk.
- **GM3.2 (Block) Failure is explained.** After a failure the player can tell what caused it (a message, a replay, a highlighted step) and what to try, except as designed obscurity allows.
- **GM3.3 (Block) The core loop feels right.** The core interactions meet their feel spec (V14): a successful input is told apart from a missed one within 100 ms by sight and by sound or vibration, and feedback is proportionate to how much the action matters.
- **GM3.4 (Block) Picking things in the world.** A tap or click within 24 dp of an interactable picks it when nothing else is nearer; when the two nearest are within 4 dp of the same distance, the game asks or zooms instead of guessing.

**GM4 HUD, panels and menus**

- **GM4.1 (Block) Readable HUD.** HUD and panel text meets A1 or A6 over the brightest and darkest scenes and A3's game sizes on the real screen, and stays inside the safe area (notches, rounded corners, touch controls).
- **GM4.2 (Block) Adjustable UI.** UI scale (at least 100 % to 200 %, as XAG 101 asks of text, with each phone starting at the scale that gives its buttons 48 dp and its text A3's size), HUD opacity, and each HUD element's visibility can be set; essential information that's hidden stays available on demand.
- **GM4.3 (Block) Objectives can be recalled** at any time (a button, the pause menu, a journal), with a recap after a break (under designed obscurity: the optional hint system instead).
- **GM4.4 (Advice) Diegetic UI has a fallback.** Information shown in the world (a gauge on a panel, a label on a valve) can also be read in a plain panel on request.
- **GM4.5 (Block) Close and back.** Every panel has a Close or Back that stays in place (N3), and the gamepad's cancel button, Escape and Android's back close the top panel first (N2).

**GM5 Pause, save and sessions**

- **GM5.1 (Block) Pause anywhere.** Play pauses at any time, cutscenes and tutorials included; losing focus, a controller disconnecting or the app going to the background pauses by itself.
- **GM5.2 (Block) Progress is safe.** A crash or quit loses at most the profile's limit (default 5 minutes of play or one step of a scenario, whichever is less); the save state is shown; overwriting a save asks first; corrupt saves are detected and a backup offered.
- **GM5.3 (Block) Cutscenes and dialogue** can be paused and skipped (the profile lists any that can't, with a reason, such as hiding a load); dialogue advances at the player's pace, and the last lines can be read again.
- **GM5.4 (Advice) Sessions fit the device.** On phones, natural stopping points come within the profile's usual session length.

**GM6 Performance**

- **GM6.1 (Block) Frame rate.** The profile's target frame rate holds for its share of frames (for example 99.9 % at 30 fps on the oldest phone) during the benchmark walk on the oldest supported hardware, measured from the platform's present times; no frame exceeds the profile's hitch limit (default 100 ms) in normal play; frame pacing is even.
- **GM6.2 (Block) Input latency.** Game latency (from the input being read to the frame showing its effect) is at most the profile's target (default 3 frames at the target rate), measured with Godot's or the platform's tools, and doesn't worsen beyond the tolerance.
- **GM6.3 (Block) Loading.** Loads over 5 s show progress and something useful (the controls, a tip); no load blocks the pause menu or quitting.

**GM7 Sound and text**

- **GM7.1 (Block) Subtitles and captions** follow A14, are on by default or offered at first launch before any speech, and have a live preview in settings.
- **GM7.2 (Block) Important sounds can be seen.** Directional or warning sounds that matter (an alarm, a leak, a machine starting) have an optional visual indicator (A13).
- **GM7.3 (Block) Menus can be read aloud.** Menus and panels work with the screen reader through Godot's AccessKit support on desktops (A8), or the game's own text-to-speech where the platform has no support.

**GM8 Comfort and first launch**

- **GM8.1 (Block) Motion comfort.** Camera shake, head bob, motion blur, depth of field, film grain and screen flashes can each be turned off; field of view can be adjusted in first-person views; a centre dot can be shown.
- **GM8.2 (Block) First launch.** Before play or the first cutscene, the player can set the language, subtitles, text size (UI scale), colour-blind options and reduced motion, with a preset per need (seeing, hearing, moving, thinking) and every detail adjustable later.
- **GM8.3 (Block) Warnings.** A photosensitivity warning shows before play if the game has any flashing content A10 allows, and content warnings are available before play for distressing themes.

**GM9 Play without sight or hearing**

Block for the groups the profile serves (by 1.1, all of them, unless the reviewer accepts a reason that the genre makes it impossible; a training simulator teaching visual inspection may record that).

- **GM9.1 (Block) High-contrast world.** A high-contrast mode for the world (interactables, hazards and the player's target in distinct, adjustable colours).
- **GM9.2 (Block) Navigation help.** Navigation help (a guide to the objective, audio pings for interactables and hazards, auto-walk to a chosen target) for low-vision players.
- **GM9.3 (Block) Sound cues shown.** Every gameplay sound cue that matters has a visual or vibration version.

**GM10 Shared sessions** (players who know each other, such as Plant's multiplayer)

- **GM10.1 (Block) Pause in company.** In a shared session, pausing opens a personal menu over the running simulation, or a host pause everyone sees with who paused; one player losing focus or switching apps never freezes the others (GM5.1 applies to solo play).
- **GM10.2 (Block) Voice has alternatives.** Voice chat or radio has text quick messages or text chat, and speech-to-text captions where the platform offers them; who is talking is shown; each player can be muted and has their own volume; push-to-talk has a toggle (A22).
- **GM10.3 (Block) The connection is a visible state.** Joining, lag, resyncing, a player dropping and the host leaving are shown in plain words (F4), with what happens to progress; a dropped player can rejoin where they were.
- **GM10.4 (Block) Roles are clear.** Where sessions have roles (an instructor and trainees), each player sees their role and what it lets them do, and the instructor sees each trainee's state.
- **GM10.5 (Block) Who's in the session.** The host sees everyone in the session, can remove a player and make a new join code; codes expire when the session ends; joining over the internet shows the host's name before joining, and joining by link follows N5's confirmation.

### 7.6 Terminal UIs (TUI)

- **TUI1 (Block) 80 × 24 and resizing.** Works at 80 × 24: all main content and every button visible (lists may scroll); uses the extra space at larger sizes (V8); re-lays out on resize without losing selection, scroll position or edits.
- **TUI2 (Block) Keys.** Every key is shown in the footer key bar or in a keys panel that a key in the footer opens; a key that can't act now is dimmed or hidden; the mouse works wherever the toolkit supports it; `esc` (once or more) always gets back to the main view; no reliance on a key the profile's terminals (Kitty, VTE, Zed's terminal) don't send.
- **TUI3 (Block) Theme colours.** Colours come from the toolkit's theme variables (Textual's `$primary`, `$error` and so on, V3); A1 and A5 hold in each supported theme; the app works with `NO_COLOR` and in monochrome.
- **TUI4 (Block) No injected markup.** Untrusted text is never read as Textual or Rich markup and never reaches the terminal as escape sequences (colours, cursor moves, OSC 8 links, OSC 52 clipboard writes, title changes) (T7).
- **TUI5 (Block) Arabic in the terminal.** Arabic and mixed text read in the right order and wrap without losing, repeating or swapping characters, in the mode chosen for the terminal (Kitty shapes Arabic itself; on VTE the app reorders and switches VTE to explicit mode, `CSI 8 l`, restoring it on exit, while VTE keeps shaping); one post's bidi controls or long words can't change the layout outside its own area; the app's own selection copies the text as stored (logical order).
- **TUI6 (Block) Beside a running service.** A terminal UI beside a running service never blocks it, never corrupts its state or config, and never makes it act unless the user asked (S6, S7).
- Evidence: Textual's pilot (`app.save_screenshot()` at 80 × 24, 120 × 40 and 200 × 50, each theme; the footer and `app.active_bindings` per focused widget; keyboard-only and mouse-only scripts); asyncio's slow-callback log for P1; a temporary `HOME` with fakes for outside commands.

### 7.7 Command-line tools and setup scripts (CLI)

Sources: the Command Line Interface Guidelines (https://clig.dev/) and the platform's conventions.

- **CLI1 (Block) Help and discoverability.** `-h` and `--help` (and `help` for subcommands) list every command and flag with an example; `--version` prints the version; running with no arguments either does the obvious safe thing or shows short help; a mistyped command suggests the nearest real one. PowerShell scripts use comment-based help (`Get-Help`).
- **CLI2 (Block) Errors in plain words** on stderr (W3): what went wrong, why, and the exact command or step that fixes it; exit codes are non-zero on failure and documented where scripts may rely on them.
- **CLI3 (Block) Safe by default.** Destructive or system-changing commands have `--dry-run`; questions (S1, S2) are asked only when input is a terminal; without one, such a command fails with an explanation unless `--yes` (or `--force`) is given, and `--no-input` turns all questions off; changes to a live system follow S8 (checked before, rollback ready, PASS or FAIL after). PowerShell scripts that change the system support `-WhatIf` and `-Confirm` (`SupportsShouldProcess`) and say before raising an administrator (UAC) prompt why it's needed.
- **CLI4 (Block) Re-running is safe.** Running a setup script again gives the same result without asking the same questions again (saved answers stay in a git-ignored folder) and without duplicating anything; an interrupted run can be run again to finish.
- **CLI5 (Block) Progress and results.** Steps over 1 s say what they're doing; long ones show progress; the run ends with a clear summary (PASS or FAIL per part, what to do about each FAIL) that fits on one screen. Animated progress (spinners, redrawn bars) only on a terminal and never with `NO_COLOR` or `TERM=dumb`; otherwise one line per step.
- **CLI6 (Block) Output for people and for scripts.** Results go to stdout and messages to stderr; human output is readable at 80 columns; colour is used only on a terminal, never alone (A5), and off with `NO_COLOR`; machine-readable output (`--json`) on request where other tools use the results; secrets are never printed, except as T5 allows for a requested hand-over (HAND1).
- **CLI7 (Block) Asking questions.** Interactive questions say what the answer is for, show the default, accept the common forms (y/yes/Y), validate at once with a plain-words reason (E3), and hide passwords as they're typed.
- **CLI8 (Block) Constrained shells.** Scripts that run on OpenWrt keep to BusyBox `ash` and the tools present there, and say plainly which package is missing if one is.
- Evidence: golden-output tests of each command's help, normal output, errors and summary; runs against a test VM or a temporary `HOME`, never a live router or server (the project's CLAUDE.md rules for VMs and emulators apply).

### 7.8 Messages a product sends (MSG)

- **MSG1 (Block) Why and what next.** Each message (an alert, an email) says in its first line why the user is getting it, carries one clear action or link, and is useful on a phone's lock screen. Where the platform forwards an original post unchanged (tele-notify's forwards), the reason and the action go in a short message right after it, or one tap away.
- **MSG2 (Block) Outside text.** Text from outside sources keeps its own direction (Arabic posts stay right to left; L2) and is clearly separated from the product's own words (a header, a quote).
- **MSG3 (Block) Pace and reliability.** Messages are never sent faster or more often than the user asked; failures to send are retried and reported, not dropped; a burst is grouped.
- **MSG4 (Block) Commands and limits.** A bot's commands are listed in its menu and `/help`; every command answers, even if only to say it failed and why; messages respect the platform's limits by splitting cleanly (Telegram bots: 4096 characters for text, 1024 for a caption; a user account through TDLib: the limits the client reports, `message_text_length_max` and `message_caption_length_max`, which depend on Premium). A product that acts as a user account rather than a bot has no command menu; its controls live in its own UI (tele-notify's TUI) and MSG5 applies there.
- **MSG5 (Block) Control.** Turning messages off or changing what triggers them is possible from the message itself or one step away.
- **MSG6 (Block) Shared audiences.** Posts to an audience that didn't set the product up (a public channel) carry no per-post meta messages: MSG1's reason and MSG5's controls don't apply to them. Instead, the channel's description says posts are picked automatically and how to report a wrong one (changing the live channel's description is an owner-check item; the agent drafts the text); a wrong post can be deleted in one action plus S1's confirmation (or with an Undo before the delete is sent) from the product's review screen; and alerts to me about it are sent silently (`disable_notification`) when a first alert already went out.

### 7.9 Product kinds: what the best do

Each profile names the kinds that apply (1.3). These rules come from what the best products of each kind do; they're Block wherever the kind applies, and the reference products in the profile are checked against them in 10.4.

**Readers** (safe-otaku's manga reader; references: Mihon, MangaDex's own reader)

- **READER1 (Block) Reading direction.** Page direction is per title (right to left for manga, top to bottom for webtoons), defaulting from the source's metadata and changeable by the reader, independent of the UI language (L2's mirroring doesn't apply to pages).
- **READER2 (Block) Pick up where you left off.** Reopening a title resumes at the exact page; the next chapter follows on without a trip back to the list; read and unread are visible.
- **READER3 (Block) Fit and zoom.** Fit to width, fit to height and zoom are offered, remembered per title, and work by touch, keyboard and pointer (A20's alternatives); a page turn on the typical device feels instant (the next page is prefetched within P6's limits).

**Drawing viewers** (Walkdown's P&ID viewer; references: good map apps)

- **VIEW1 (Block) From search to the tag.** Choosing a search result moves to the tag and highlights it within the core feel spec (V14), with a highlight that A5 and A2 accept.
- **VIEW2 (Block) Smooth at scale.** Panning and zooming hold the display's frame rate on the benchmark sheet (the real largest sheet, measured as a real-data evaluation, 1.5) on the oldest supported phone.
- **VIEW3 (Block) Usable at every zoom.** Tags stay hittable at every zoom level (GM3.4's nearest-wins and A19's sizes for their hit areas), and rotating or resizing keeps the same place and zoom.

**Local file sharing** (Direct-Share; references: Quick Share, AirDrop, LocalSend)

- **SHARE1 (Block) Accept before receiving.** An incoming transfer from a device that isn't trusted waits for an accept that shows the sender's name and device, the file names, count and total size; nothing, including image previews, is shown or saved before the accept.
- **SHARE2 (Block) Visibility modes.** Being visible to others has modes (off, my devices, everyone for 10 minutes) and returns to the safer mode by itself; the current mode is always shown (F4).
- **SHARE3 (Block) Start where people are.** Sending starts where people already are: the Android share sheet, the file manager's "Send to" or context menu on GNOME, and drag and drop onto the window.
- **SHARE4 (Block) Speed and finishing.** Time to find a nearby device and transfer speed are budgets (1.5); an interrupted transfer resumes or says plainly what was saved; after receiving, "Open" and "Show in folder" are one action away; receiving works with the app closed where the platform allows (an Android foreground service, a GNOME background portal), within O3.
- **SHARE5 (Block) Capability check.** Before the user tries, the product checks the device can do it (Wi-Fi Direct support in the Wi-Fi card and driver, the needed permissions and radios) and says plainly what it can't do and what to use instead.

**Alerts and monitoring** (tele-notify; references: good RSS readers, job-alert services)

- **ALERT1 (Block) Latency.** Time from a source post to the alert on the phone is a budget (for example 95 % under 60 s), measured on the benchmark walk and in real use.
- **ALERT2 (Block) Filter quality.** The filter's quality is a UX target: the combined score of its real-data evaluation (1.5) rises and can't fall back (10.1, 10.3).
- **ALERT3 (Block) See what was missed.** The user can see what was filtered out (a "missed" view or a searchable log with the reason), so a miss can be found and corrected (AI5).

**Training and courses** (Walkdown Plant, Walkdown's courses; references: well-regarded simulators and course apps)

- **TRAIN1 (Block) Content checked.** Every procedure, scenario and course step is checked against the real procedure by a qualified person (me, or someone I name) before release, and the check is recorded; a step that can't be checked is marked as such where the trainee sees it.
- **TRAIN2 (Block) Debrief.** After a scenario, a debrief shows the trainee's steps beside the correct ones, with what each mistake would have caused.
- **TRAIN3 (Block) Progress and records.** Progress persists across sessions and devices where the product syncs; assessed results can be exported for the trainee's records (D4).
- **TRAIN4 (Block) Content is traceable and current.** Each procedure, scenario and course step's source document and revision is recorded where the content's format can carry it: in the authoring sources and a manifest the build makes, until the format's next version (frozen formats such as Walkdown's course format v1 aren't changed for this). For an invented plant (Plant's), the source is the standard or textbook it follows. The course says it doesn't replace the plant's controlled procedure. Checking revisions is my duty (9.8), gating each release: the agent lists the sources, I mark which were revised, and the affected courses or procedures are marked "may be out of date" where trainees see them until they're rechecked (TRAIN1).

**Field tools** (Walkdown; references: Organic Maps, good field-service apps)

- **FIELD1 (Block) Report a problem.** Every product with users besides me (not only field tools) has this. Public open-source tools that hold no personal, household or plant data may instead open a prefilled issue on their public tracker, after showing the user the redacted diagnostics; the rest report privately, as follows. A "report a problem" action in the product attaches diagnostics (no personal or plant data unless the user reviews and allows it) and sends the report to a private channel I control (the product's own server or admin page, or a message to me), never straight to a public tracker; I reproduce it on synthetic data before filing (Z1). Between rounds with users it's the only signal from the field.
- **FIELD2 (Block) Real field conditions.** The main tasks work one-handed, with gloves, in sun, and offline (1.1, A19, A1's 7:1, ST3), checked on a real phone at least once per release that touches them.

**Family filters and household networks** (safe-otaku, openwrt-oneclick's parental parts)

**Parent's control** means something a child on the household network can't operate: the router's admin login, SSH, or a secret held only on the parent's device; never a MAC address, a hidden URL or obscurity. FILTER4's bypass check includes the product's own controls, tried from a child's device on the VM.

- **FILTER1 (Block) Explain the block.** A blocked site shows a local page that says it was blocked by the household filter, where the method allows it; where it can't (DNS blocking of HTTPS sites), the README and the household's note explain what the resulting error means.
- **FILTER2 (Block) Mistakes reach the parent.** A "blocked by mistake" path reaches the parent, and the parent can see what is blocked and why: the rules and lists, not a history of the child's requests. Any request history is opt-in, kept in RAM only, and mentioned in the household's note (a short page or printout for the household, saying what is filtered, when the cut-off runs, what errors mean and who to ask).
- **FILTER3 (Block) Warn before cut-off.** A scheduled cut-off (internet off at night) warns the household before it starts where the router can; where it can't, the household's note states the times. The parent can extend or end it in one step from a phone (a local page on the router or a saved shortcut), not only by re-running a script on the laptop.
- **FILTER4 (Block) Enforce and admit gaps.** The product enforces the profile's content policy (1.3) against every bypass the profile lists (another browser or app, changed DNS, known VPN and DNS-over-HTTPS endpoints, a changed or randomised MAC address, forgetting and rejoining the network, a guest network, another household device; rules keyed to MAC addresses say which of these they can't close) and against exits the product itself offers (links out, which are hidden by default behind the parent's control or go only to destinations the household filter covers); every bypass it can't close (mobile data, a site it doesn't cover) is listed in the README and the household's note. A bypass a child can do from their own device's settings (turning on a private MAC address, forgetting and rejoining) isn't closed by listing it: the product offers the closing design by default (during the cut-off, every device not on the parent's allowlist is cut off, and new devices join the restricted group), and the parent may pick the weaker list-the-children's-devices setting at setup, shown what it lets through (the cost of the strict one: guests' phones are off at night too). Where the data source can't express the content policy exactly (MangaDex's `suggestive` rating also holds ecchi titles), the gap is told to the parent in the product and the README, and the parent can block single titles; at setup the parent chooses between the strict and the wider setting, shown what each lets through; that is compliant, and T9 judges how the product enforces what the source can express.

**Setup that hands something to another device** (openwrt-oneclick, tgproxy, Walkdown's sign-up)

- **HAND1 (Block) Hand over by QR or copy.** A main task that ends with something another device must import (a Wi-Fi password, a proxy link, a sign-up code) offers a QR code (in a terminal, for example `qrencode -t ansiutf8`) or a one-time copy, shown once on request and never logged (T5), so the user never has to move a file by hand. Agents exercise hand-overs only with fake secrets; a real one printed in an agent's session would end up in its transcript.

## 8. The process

### 8.1 Before building

- New main tasks, new screens in the screen table, redesigns and new core interactions are first tried as a sketch, a mock-up or a greybox, with at least one person from the profile who isn't the author (for a product only I use: me, a day later, against the experience intent), and the findings are recorded in the change or its issue.
- A short scan comes first: how the reference products (1.3) and the platform's own patterns do it.
- A design note before building checks the plan against the conceptual model (C5), the screen table, the feel spec (V14), and the rules most likely to fail (access, states, Arabic text).

### 8.2 Tiers

Each change gets a tier, proposed by the author and confirmed by the first reviewer. Splitting a change to lower its tier is gaming (0.7).

| Tier              | What                                                                                                                                                                                                                                | Audit                                                                                                                                                                                |
| ----------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| **0 Wording**     | Text only, in screens covered by the stored baseline (a label, an error message, a translation); without a baseline, wording changes are tier 1                                                                                     | Screenshots of the changed screens at the smallest size, the largest text size and each theme, in English and Arabic where offered; both passes, limited to Appendix C's wording row |
| **1 Small**       | A fix or change inside one screen that doesn't change a main task's flow, deletion, privacy, a live system or a core interaction; a new instance of an existing pattern (a new settings row, a new HUD element of an existing kind) | Evidence for the touched rules; both passes, the adversarial one limited to the touched rules                                                                                        |
| **2 Significant** | New or changed screens in the screen table; main-task flows; deletion, privacy, sending or a live system; a core interaction; navigation; the design system; onboarding; a profile narrowing                                        | Full evidence; both passes (8.4); my check before release (8.5); the try-out before building (8.1)                                                                                   |
| **3 Redesign**    | Rework of a whole area, the navigation, or the visual style                                                                                                                                                                         | As tier 2, plus a round with users on the built version (8.6) and 9.4                                                                                                                |

Any change to procedure, scenario, course or reference content (steps, values, tags, safety notes) is tier 2 for 8.5, however small: it merges switched off or waits, and TRAIN1's check is an owner-check item (all such checks in one PR form one item, 9.6). A bug fix that restores the intended behaviour is otherwise tier 1 at most, unless the fix itself changes a flow. Per AGENTS.md, every bug fix gets a test that fails without the fix: for a UI bug, a pilot, Playwright, Compose, Godot, or AT-SPI or UIA end-to-end test that reproduces it.

### 8.3 Evidence

Made from synthetic data (Z1) by scripts kept in the project, so it's repeatable and the author doesn't choose what reviewers see. "Before" is the stored baseline from the last build of main (1.6), not a rebuild. Heavy runs (emulators, VMs, headless sessions, Godot exports) follow my machine's memory rules (the go-wide skill) and the project's rules on running one at a time; CI runs what it can, so local runs are the remainder. Evidence tools are development-only, recorded in the profile, and live outside the product's dependency manifest (a separate `ux-evidence/` package or a tool installed in the development environment); where a project limits its dependencies (safe-otaku allows two in total, `preact` and `esbuild`), evidence tools never enter its manifest. An OpenWrt QEMU VM counts as the router for evidence; checks that need the physical router are owner-check items. Where a project's CLAUDE.md allows it, flows no emulator or headless session can run (Direct-Share's Wi-Fi Direct transfer) may be driven by an agent on a spare phone over `adb` against a second host, with synthetic files; otherwise they're owner-check items.

- **Automated set:** screenshots of every touched screen, covering every pair of these dimensions at least once (all-pairs, not every combination): each state (ST1); the smallest, a typical and the largest size; each theme; the largest text size; English, Arabic (where offered) and pseudo-localisation; the accessibility tree; computed contrast; target sizes; scans for literal colours and off-scale spacing (V3, V4); budgets on the benchmark walk; the hostile-content fixture (T7: markup, escape sequences, bidi controls, very long words, emoji, combining marks, huge numbers, empty strings) everywhere outside content shows.
- **The hero set, for eyes:** for each touched screen, before and after side by side at the smallest size, at the largest text size, in the dark theme and in Arabic; the blurred shots for V1. A pixel-diff tool groups every changed screenshot into contact sheets of at most 40 images per reviewer; above that, the review is split by platform, then by screen group, one reviewer each, run within the go-wide skill's limits on parallel agents. A reviewer marks a rule Pass only for images it was shown, and lists them.
- **Task runs:** a recorded run (script log or video) of each touched main task with each first-class input method, with action counts and times (U1, U3).

**Z1 (Block) Synthetic data for evidence; real data only in private.** Evidence that leaves my machine (screenshots in PRs, issues, wikis, READMEs, CI) uses invented data: invented posts, notes, devices, chats, keywords, drawings and codes; emails at `example.com`; phone numbers from ranges reserved for fiction; no real plant data, no real household or chat data, no real keys, addresses or device names. Every run uses a temporary `HOME` or profile and fake outside commands, and refuses to run against real data folders. The edges of each screenshot (window title, status bar, paths, notifications, user names) are checked before it's published. A problem first seen on real data is reproduced on synthetic data before it's filed. Content already public in the repository by my recorded decision (Walkdown's plant courses) may appear as it is. The profile's **real-data evaluations** (1.5) are allowed, and required where named: they run locally, write only aggregate numbers (counts, rates, timings, pass or fail) into tracked files and PRs, and never write screenshots, records or excerpts. The synthetic data set is generated from recorded statistics of the real data (item counts, longest name per script, the mix of Arabic and Latin, file sizes), re-measured at each full audit, so it's realistic.

What can't be checked with the available tools is recorded as Not checked with the reason (9.3). The usual accepted reasons: how it really looks and feels on a physical phone or in my terminal, real screen-reader speech, sun and gloves, a real controller's feel, a real router.

### 8.4 Review passes

Fresh subagents, one after the other, not told what the author thinks; they are the two passes AGENTS.md already requires, with this policy, the profile, the review brief and the evidence added. Their prompts are generated by a script in the project from the versioned review brief and the PR number; each reviewer fetches the diff and the evidence itself (`gh pr diff`, the CI artifacts or evidence store), and the author adds only the change's purpose. The script also emits a **rule digest** for the change: the Appendix C rows it matched, with each rule's level and short name from Appendix H, so the author and the reviewers read the digest and open only the rules it names. Each run is posted to the PR word for word, numbered; a later run can't clear an earlier fail; only a recheck that names the fail and cites new evidence can. The review machinery (prompt scripts, evidence scripts, fixtures, golden screenshots, the coverage test and the brief) always runs from the base branch; a PR that changes or deletes any of it is a narrowing (1.7): both passes on that diff and my OK quoted in the PR before the new version is used. Additions run from the PR: a fixture, golden screenshot or evidence script for a screen the PR itself adds. Where a project has no remote, "the PR" means the change's entry in `docs/ux-backlog.md` and the local branch.

**Arabic is judged by pixels, not impressions.** For each surface and Arabic fixture, I approve a golden screenshot once; after that, L2 and TUI5 pass only by a pixel diff against it, or by a dump of the rendered visual order (Pango layout runs, Compose text-layout runs, the terminal's cell grid) compared with an expected order I approved. A golden or expected order added by a PR is a candidate: until I approve it on the owner-check list, those rules are Not checked for that surface, with an accepted reason. An AI reviewer's reading of an image alone leaves them Not checked.

**Local evidence.** Evidence made on my machine (emulators, VMs, the headless GNOME session) is recorded in a manifest: the scripts' commit, the fixtures' hashes, the command, and a hash per image. It's pushed to a ref outside the branches (`refs/ux-evidence/pr-<n>`, which clones don't fetch), never to main; removing old evidence refs is a cleanup I approve. The reviewer checks the manifest against the base-branch scripts and reruns one randomly chosen fixture itself; a mismatch is gaming (0.7).

1. **Blind pass:** given the change (its purpose and the diff), the evidence, the profile and this policy. It confirms the tier and records a result for each touched rule on each touched screen and platform.
2. **Adversarial pass** (every tier; for tiers 0 and 1 limited to the touched rules, as 8.2 says): given the same plus the blind table, it tries to break the change: smallest and largest sizes, largest text, each theme, each input method alone, a screen reader, Arabic and hostile content, every state, offline, slow, interrupted, a first-time user, an expert in a hurry, a user who makes every mistake, and gaming of this policy (0.7). It may ask for missing evidence; until it's given, the rule is Not checked. It records at least one concrete thing it tried for each touched rule group.
3. **After fixes:** a fresh subagent rechecks the failed rules and every rule the fix's screens touch, on new evidence. A fail stands until such a check clears it.

The reviewer, not the author, sets each fail's severity (9.5). The author may rebut a finding with evidence: a fresh adjudicator subagent gets only the finding, the rebuttal and the evidence. Its ruling settles severity, Advice findings and **judgement rules** (V1, V7, V13, A24, A28, W2, W4, C5, whose check is a judgement against the profile's intent order and experience intent): for those, the ruling and the images go on the owner-check list and gate the release, not the merge. I'm asked only if it can't decide. A fail of a Block rule with a measurable check is a correctness finding, so like security and data-loss findings it follows AGENTS.md: confirm it with a failing test (a UI test or evidence script that shows it), fix it, or stop and ask; an adjudicator can't clear it. An AI reviewer judges what it can perceive (images, trees, numbers, logs) and marks the rest Not checked; it never replaces my check (8.5) or watching users (8.6).

**Canaries.** Once a quarter per live product, a script picks a past real fail at random (from closed `ux` issues), a subagent that won't review seeds it into a change in a detached worktree (`git worktree add --detach`, so no branch is created), and the normal generated review runs on it, pointed at a local diff and local evidence instead of a PR. Nothing is pushed or committed, and the worktree is removed when the run ends. A pass that misses it means the review brief needs fixing (1.6).

### 8.5 My check before release

For tier-2 and tier-3 changes, and any change to a core interaction:

- the agent merges as AGENTS.md says and adds the change to the project's **owner-check list** (an issue labelled `owner-check`, or a section of `WAITING-FOR-YOU.md` where the project has one), with the hero set, any alternatives (0.2), the Not-checked items that need a real device, and how to run the build on synthetic data;
- before the next release (a tag, an APK, an export, or a deploy for a product that deploys on merge), I use the build on my devices, on synthetic data (and, where the experience intent depends on real data, such as finding a tag on the real largest sheet, also privately on real data, recording only words, never images), and judge each change against a short rubric: the screen's intent (V1), the feel spec beside its reference (V14), the voice (W6), the conceptual model (C5), before and after (V13), the experience intent (1.3). Each item is marked **better**, **same** or **worse**;
- any **worse** is fixed or reverted before the release; I record "Owner: OK" or what's wrong (0.2);
- on a device that holds real data (Walkdown's account on my phone), the check build has its own application ID (an `applicationIdSuffix` such as `.check`) or runs in a work profile or the emulator, recorded as such, and never touches the real install;
- main stays releasable: for every product, a tier-2 or tier-3 change merges behind a switch that is off by default (a build flag, or a setting users can't reach), or stays on its branch, until my check turns it on; a release turns on only checked changes, and changes outside the batch I check (1.5's owner budget) ship switched off and stay queued; for a product that deploys on every merge, where that isn't practical, deploys wait while the list has items, except emergency fixes (8.7) and tier-0 and tier-1 fixes, which are released from a branch cut at the deployed version. An agent never deploys an unchecked tier-2 or tier-3 change to users. Evidence is made with the switch on, and the switch-off path must match the released baseline (visual diff). A switch is removed in the first release after my OK; one still there two releases after my OK is a severity-3 item, and one still waiting for my check counts under 9.8.

Because I'm both owner and often author, at least once per major release someone outside who fits the profile (a colleague for Walkdown, a household member for safe-otaku, a player for Plant) gives a second verdict on the biggest change.

### 8.6 Watching real users

- **Each product with users besides me:** at least once a quarter while it's live and in active development (twice a year in pre-release, yearly in maintenance, or as the owner budget in 1.5 batches them, but never less than once a year for a product with users besides me), watch at least 2 people from the profile do the main tasks without help, thinking aloud, on their own devices or the target ones; record where they hesitated, failed and what they said. For a game or simulator, also where they retried, got stuck and quit, and whether it felt as intended.
- **Products only I use:** a week of real use after each tier-2 or tier-3 release, as the round: the agent opens the week's issue at release, and the round counts only once I've added at least one dated entry, or "none".
- **Accessibility:** once a year per product, someone who uses a screen reader, or another assistive technology the product's main tasks depend on, tries the main tasks (through a community or a colleague: the agent drafts the request, and posting it outside the repository, or paying anyone, is mine, as AGENTS.md says); until then, my own run with the screen reader and the reviewer's walkthrough stand in, recorded as such.
- People who take part agree first, know what is recorded, and can stop at any time; their data stays private (Z1); children take part only with a parent present and agreeing.
- Each finding becomes a tracked item. U2 is judged from these rounds.

### 8.7 Emergency fixes

A fix that stops ongoing harm (data loss, a security hole, a crash, a router or server cut off) may ship after the author checks the Block rules it touches; AGENTS.md's two code review passes still run before merge, and only the UI evidence and my check (8.5) move to the follow-up. Its full audit at its proper tier follows within 5 days; any fail found is at least severity 2 and never pre-existing (9.2). More than two emergency fixes in a cycle is itself a severity-2 item (10.6).

### 8.8 Results

Everything addressed to me (owner-check items, reports, questions) names each rule in words, with its ID in brackets at most, as AGENTS.md asks; PR tables put Appendix H's short name beside each ID.

Each pass posts a table on the pull request: one row per touched rule, one column per touched platform, each cell **Pass** (with the evidence), **Unaffected** (the diff can't reach it: the files are cited and the reviewer confirms), **Fail** (where, what, severity), **Pre-existing fail** (with evidence from the released version and a tracked item), **N/A** (from the applicability list), or **Not checked** (why). The never-waivable set is always listed, usually as Unaffected. Appendix B is a template.

### 8.9 Full audits

A full audit (every rule, every screen in the screen table, every platform, both passes) runs when a project adopts the policy, before its first stable release, before each major release, after a tier-3 change, and at least once a year for a live product. Results go in `docs/ui-audit/YYYY-MM.md` with the hero set beside them, and a tracked item for each group of fails. For a project with many screens, an audit may cover every rule on the main-task screens plus a rotating third of the others, so all are covered every three audits.

## 9. What blocks a change

### 9.1 Blockers

A UI change merges (and, for tiers 2 and 3, is released) only when its tier's audit is done and:

- no Block rule fails because of the change at severity 1 or 2 on any touched platform. A Block fail at severity 3 or 4 doesn't block the merge; it becomes a tracked item due by the next release, and the next change to the same screen is blocked while it's still open after that release (except the change that fixes it, other bug fixes, and emergency fixes, 8.7);
- no fail of any rule, Advice included, is rated severity 1;
- no Advice fail sits on a main task's path in a tier-2 or tier-3 change unless the change records a reason and the release by which it will be fixed;
- every Block rule marked Not checked meets 9.3.

A release ships only when, in addition: my check (8.5) has said OK to every tier-2 and tier-3 change the release turns on, and to every judgement-rule ruling for those changes; the fluent-speaker reading (L6) is done for every language whose on-screen text the release changes; TRAIN4's revision check covers all content the release ships; the held-out run (1.5) is done when 1.5 makes it due (each release, or the end of each cycle for a product that deploys on merge); T11 and T12 pass where the stage applies them; and, where a scripted fresh-install run exists, it passes following the README's own steps.

**Severity floors.** A fail of A0, of any A-rule on a main task, or of S1 to S4, S6 to S9, T0 to T9, T13 or Z1, is at least severity 2; S5, T11 and T12 are rated by 9.5. The reviewer may raise severity, never set it below a floor.

### 9.2 Pre-existing fails

A fail already in the released version doesn't block if it has a tracked item, evidence from the released version, and the change doesn't make it worse. **Worse** means: more screens, items or platforms fail; a measured value moves further from its limit; or the fail gets more severe. A fail that reached users without its audit (a skipped review, an emergency fix) after the project adopted this policy is never pre-existing: it blocks the next change to the same screen until fixed (with the same exceptions as 9.1). Fails present when a project adopts the policy, or when a rule becomes stricter (11.1), count as pre-existing once they're tracked. A component or library the change adds counts as the change's own, even if someone else made it.

### 9.3 Not checked

- **Never accepted** for the never-waivable set (S1 to S3, S8, A10, T0, T1, T9, Z1) or a declaration's fallback.
- **Accepted** for other Block rules only if the reason is on the profile's list (1.6), or I accept it in writing for that change. Either way it becomes a severity-2 tracked item, checked in my check before release (8.5) or due by the next release. An item whose accepted reason is hardware I don't own is instead tracked at severity 3, listed in the README's accessibility statement (T11), and exempt from this due date, 9.6's deferral limit and 10.6's trend.
- Reasons on the profile's list expire after 6 months unless renewed with a plan to remove them (except hardware reasons, 1.6).

### 9.4 Redesigns

A tier-3 change may ship with new Advice fails, and new severity-3 or 4 Block fails, when a full audit of the area shows a net improvement (fewer fails weighted by severity: 1 = 8, 2 = 4, 3 = 2, 4 = 1) and each new fail has a tracked item due by the next release. It never ships with a new severity-1 or 2 fail.

### 9.5 Severity

- **1 Blocker:** a user can't complete a main task; loses data, access or privacy; is harmed or exposed; a live system is left broken; or a disabled user in the profile is shut out of a main task.
- **2 Major:** a main task is much slower, error-prone or confusing for some users; frequent frustration; the intended experience clearly fails; gaming of the policy (0.7).
- **3 Minor:** an annoyance with an easy workaround; a polish defect on a main screen.
- **4 Cosmetic:** a polish defect elsewhere.

### 9.6 Keeping my own exceptions honest

I can accept Not-checked items, settle severity disputes, defer items and grant waivers, so:

- no severity-2 item is deferred more than once;
- no more than 5 accepted Not-checked items are open per product at a time, not counting items waiting only for my scheduled check before release (8.5), which close together at that check; each such item names the exact check, and one that takes over 2 minutes counts toward the 5;
- an owner-check item is one PR or one duty from 9.8 (all candidate goldens and all course-content checks of one PR form that PR's one item); 9.8's scheduled duties don't count toward the 8-item limit below; and the limits count items, not checks; approving a golden isn't a change to the review machinery;
- when a product's owner-check list holds more than 8 items, agents start no new tier-2 or tier-3 work on it and work its `ux` backlog instead;
- N/A for a whole user group, and every waiver, needs an outside reviewer's agreement: a person, or a fresh subagent as 0.3 defines one, with its answer recorded;
- each full audit lists, with their trend, the open waivers, Not-checked items, pre-existing fails, N/A claims, deferrals and emergency fixes (10.6).

### 9.7 The UX backlog

Every Advice fail, deferred Block fail, pre-existing fail, user-round finding, Not-checked item and barrier report is a tracked item with severity, rules and evidence, labelled `ux`. For a product that deploys on every merge, a due date counted in releases is counted in cycles instead ("the next release" means the end of the current cycle); fails tracked at adoption follow a burn-down plan in the profile, highest severity first, at least 10.2's share each cycle, instead of these dates; and an overdue item that isn't one of my duties (9.8) blocks new tier-2 work on its screen. Severity 1 is fixed before the next release; severity 2 within two releases (one deferral at most, 9.6).

### 9.8 Duties only I can do

This is the one list of my duties, each an owner task on the owner-check list: my check before release (8.5), the fluent-speaker reading (L6), TRAIN4's revision check and the held-out runs (1.5), which gate the release as 9.1 says; and the outside verdict, rounds with users (8.6), judging feel in the comparison with the best (10.4; the agent does the measurable part), and keeping the T0 checklist current, which are due on their schedules. None gates a merge, except an open T0 question on a change, which blocks that change's merge as T0 says. (1.5's recovery freeze is a score rule, not a duty.) Overdue ones form one severity-2 tracked item per product (not one each); it doesn't block agents' merges. Meanwhile U2 uses the last round held, or is Not checked with the accepted reason "round overdue", and tier-2 and tier-3 changes still wait for my check before release.

## 10. Getting better, not only not worse

- **10.1 Targets rise.** After each round with users or benchmark, a target met twice in a row is raised, or replaced by a harder one, unless I record that it's where the product should stay.
- **10.2 A share of every cycle.** At least one in five merged PRs on a live product each cycle closes a `ux` item: highest severity first, then most frequent, then removal candidates (C6); every second such PR comes from the gaps found by comparing with the reference products (10.4) when there are any. The full audit counts it with `gh`; a shortfall is a severity-2 item (10.6).
- **10.3 The ratchet.** When a timing or a real-data score improves beyond its noise (the median of at least 10 runs, outside the tolerance), it becomes the new limit for "worse" (9.2). Size budgets (bundle, download, install) don't ratchet: growth needs a reason in the PR, and my OK only past the profile's budget.
- **10.4 Compare with the best.** Each full audit does one main task in each reference product (1.3) and in the product, comparing time, actions, errors, start-up and feel, and files what's worth taking. Budgets are at least as strict as the best reference's measured value, or the gap is a tracked item.
- **10.5 Close the loop.** After a release, the next round (or my week of use) checks the changed tasks; a change that made a task worse is fixed or reverted.
- **10.6 Watch the process.** Each full audit reports the counts in 9.6 over time; a rising count is a severity-2 item.

## 11. Changing this policy

### 11.1 How

I decide. A change to this policy is reviewed by two fresh subagents (blind, then adversarial), like a tier-2 change. A stricter rule applies to new changes at once; within one cycle, each live project gets a targeted audit of that rule, whose fails become tracked items (and count as pre-existing once tracked). A project's own UI policy may add rules and tighten numbers, never loosen these except through declarations (1.5) and waivers (11.2).

### 11.2 Waivers

A waiver names the rule, the case, the reason, an expiry of at most 6 months, and the outside reviewer's answer (9.6). Renewing it needs new evidence. Waivers are listed in the profile. No waiver covers the never-waivable set (S1 to S3, S8, A10, T0, T1, T9, Z1). Declarations (1.5) aren't waivers; designed save tension's relaxation of S1 for runs is the only place the never-waivable set is relaxed, and its fallback replaces it.

## Appendix A. Profile template

```markdown
# UX profile: <product>
Stage: prototype / tool / public tool / pre-release / live / maintenance / retired · Reviewed: YYYY-MM-DD (passes linked)

## Purpose (and what it must never do)
## Core objects and verbs
## Experience intent and reference products
## Core interactions (with feel specs)
## Users: who, evidence, where, abilities, age, languages
## Platforms: versions, oldest and smallest device, typical device, sizes, inputs (first-class / secondary),
   assistive tech, network
## Main tasks
| Task (users' words) | Who | How often | Done means | Targets (set YYYY-MM-DD) |
## Screen table
| Screen or group | Job | Must be visible at smallest size | Primary action | Input per method | Intent order |
## Budgets (with tolerance) and the benchmark walk
## Declarations (with fallbacks)
## Modules
## Design system (where; additions to the platform's)
## Evidence tools and synthetic data
## Applicability list (N/A rules per platform, with reasons)
## Accepted Not-checked reasons (with expiry)
## Third-party surfaces
## Review brief (version)
## Waivers (with expiry and outside answer)
```

## Appendix B. Results table template

```markdown
Change: … · Tier: 2 (confirmed by the blind pass) · Platforms: GNOME, Android

| Rule | GNOME | Android | Notes |
|---|---|---|---|
| U1 | Pass | Pass | runs: link |
| V1 | Fail (sev 2): Devices, "Forget" outranks "Send" in the blur test | Pass | fixed in this PR |
| A8 | Pass | Not checked: TalkBack speech needs a phone (accepted reason, expires 2027-05) | owner-check list |

Adversarial cases tried: …
Owner check: pending (owner-check #123)
```

## Appendix C. Change-kind map

Which rules to read and check for each kind of change. Always add: the never-waivable set (S1 to S3, S8, A10, T0, T1, T9, Z1), A0's touched criteria, the platform module's rules for the touched screens, the product kind's rules (7.9) where the change touches what they cover, and any rule in Appendix H whose subject appears in the diff. A lint checks that every Block rule appears in at least one row or in this always-add list (the product-kind rules count as listed; U2 is checked by rounds with users, and T11 and T12 at release).

| Change                                                        | Rules                                                                                                                                                                                          | Evidence                                                                                                      |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| A fix inside an existing screen (tier 1)                      | The rules whose evidence changed in the visual diff; F1; the touched state of ST1; A1, A2 and A5 if colours changed; A19 if sizes changed; the never-waivable set as Unaffected unless reached | The automated set for that screen; the hero set if it changed                                                 |
| A form or input field (sign-up, pairing code, settings entry) | E1 to E6, A26, T6, W3, S3, L2                                                                                                                                                                  | Each field empty, valid, invalid and pasted, in Arabic and English; keyboard and screen-reader runs           |
| Automatic decisions (filtering, recognition, an LLM feature)  | AI1 to AI5, ALERT1 to ALERT3, the real-data evaluation (Z1, 1.5), T8                                                                                                                           | The evaluation's aggregate numbers on the fixed snapshot; screenshots of how decisions and their reasons show |
| Export, import, saved formats, URLs and links in              | D4, D6, N5, S6                                                                                                                                                                                 | Round-trip tests of each format; old-version files and links                                                  |
| Media and generated documents (video, audio, PDF, charts)     | A13 to A16, A29, V15, A10                                                                                                                                                                      | Caption screenshots; the PDF's tags and reading order; a flash analysis                                       |
| Privacy, permissions, children                                | T2, T4, T5, T9, T6                                                                                                                                                                             | Runs with each permission refused; the data the feature sends                                                 |
| Wording (labels, errors, help, a translation)                 | W1 to W7, A24, L1 to L3, L6, C2, MSG if it's a message                                                                                                                                         | Screenshots at the smallest size and largest text, each theme, English and Arabic                             |
| A new setting or settings row                                 | C5, D1, D2, U6, I1, I4, A8, A18, A19, W1, W2, L3                                                                                                                                               | Settings screen in each state; tree; keyboard-only run                                                        |
| A new or changed screen                                       | U1, U1a, U5, N1 to N7, V1 to V13, A1 to A9, A11, A12, A18 to A25, A28, I1 to I7, F1 to F4, ST1 to ST5, W, L2, L3, C1 to C5, H2, P1, P7, T7                                                     | The full automated set and hero set; task runs per input; tree                                                |
| A dialog or confirmation                                      | N2, N3, N7, V2, S1, S2, W2, A23, A19                                                                                                                                                           | Dialog in each theme and size; keyboard and touch runs; double-press test                                     |
| Deleting, sending, sharing, or changing a live system         | S1 to S9, F2, F3, T2, T4, T5, CLI3, HAND1                                                                                                                                                      | Runs of the flow with failures forced; dry run; rollback test                                                 |
| A list, table or search                                       | N6, I8, I9, S5, ST1, ST2, W7, L4, P2, P4                                                                                                                                                       | Lists empty, normal and 10 times the usual count, with Arabic names                                           |
| Offline, sync or another device                               | ST3 to ST5, F3, F4, E5, D5, S3, I9                                                                                                                                                             | Runs with the network or peer cut and restored                                                                |
| Look or style (tokens, spacing, theme)                        | V3 to V6, V11 to V13, A1, A2, A5, A7, GNOME3, TUI3                                                                                                                                             | Hero set before and after; contrast; greyscale and colour-blind views                                         |
| Performance-sensitive code                                    | P1 to P7, GM6, budgets in the profile                                                                                                                                                          | The benchmark walk, median of 10 runs, before and after                                                       |
| A core interaction                                            | V14, F1, GM3.3, U3, the feel spec                                                                                                                                                              | Task runs; a real-device check in 8.5                                                                         |
| A command-line command or its output                          | CLI1 to CLI8, W3, D6, T5, A5, S7, S8                                                                                                                                                           | Golden-output tests: help, normal, error, summary, `--no-input`                                               |
| A terminal UI screen                                          | TUI1 to TUI6, U1, N2, I3, A1, A5, L2, T7                                                                                                                                                       | Pilot screenshots at 80 × 24 and larger; keyboard-only and mouse-only runs                                    |
| A message or notification                                     | MSG1 to MSG6, T13, O1 to O4, A13, A16, A30, W, L2, T7                                                                                                                                          | The rendered message from synthetic input, in Arabic and English                                              |
| A game HUD element or panel                                   | GM4, A1, A3, A6, V1, N3, I7                                                                                                                                                                    | Screenshots over the brightest and darkest scenes, phone and desktop scale                                    |
| A game control or input                                       | GM1, A18, A20, A22, A30, I3, I7, GM3.3, GM3.4                                                                                                                                                  | Input runs on keyboard, gamepad and touch; remap test                                                         |
| Game challenge, assists, pause, saving, cutscenes             | GM2, GM5, GM8, A21, S3                                                                                                                                                                         | Runs with each assist on; quit and crash mid-scenario, then resume                                            |
| Game world readability and play without sight                 | GM3.1, GM3.2, GM9, A5, A6, A12                                                                                                                                                                 | Screenshots over each lighting state in greyscale and high-contrast mode; a navigation-help run               |
| Game sound, voice or captions                                 | A13 to A16, GM7, GM10.2                                                                                                                                                                        | Caption screenshots at each size; a run with sound off                                                        |
| A shared-session (multiplayer) feature                        | GM10, F4, ST4, A13                                                                                                                                                                             | A two-client run with a dropped player                                                                        |
| Onboarding, install, update or uninstall                      | H1, H4, N7, O1, T4, T6, D3, D7, D8, GM8.2, 1.4's install task                                                                                                                                  | A fresh-install run on each platform, timing each step                                                        |
| A profile edit                                                | 1.7, 0.8, 9.6                                                                                                                                                                                  | Both passes on the profile diff                                                                               |

## Appendix D. Abbreviations

- **AT-SPI:** the Linux accessibility interface that Orca and test scripts read.
- **CEFR B1:** an intermediate reading level of the Common European Framework of Reference for Languages.
- **CLS, INP, LCP:** Core Web Vitals: layout shift, interaction delay, and how long the main content takes to appear.
- **dp, sp:** Android's density-independent pixel and its text equivalent that follows font scale.
- **LUFS:** a measure of loudness.
- **PEAT:** the Photosensitive Epilepsy Analysis Tool.
- **PWA:** a web app that installs and works offline.
- **UIA:** Windows UI Automation, which Narrator and test scripts read.
- **WCAG 2.2:** the W3C's Web Content Accessibility Guidelines; WCAG2ICT applies them to apps.
- **XAG:** the Xbox Accessibility Guidelines, used here for game numbers on every platform.

## Appendix E. Changes

- **4.13 (2026-11-18):** the release gate's held-out, L6 and TRAIN4 scopes; adoption without the hook-up starts no tier-2 work; one owner-check item per PR.
- **4.12 (2026-11-18):** the release gate counts only the changes a release turns on; which of my duties gate the release and which run on schedules; T0 questions still block their change's merge; switch age counts from my OK.
- **4.11 (2026-11-18):** Escape follows libadwaita on GNOME; every product's checked changes ship behind switches, so the owner budget can't deadlock a tagged release; the held-out search runs on the held-out part; D8 restores what it replaced; FILTER4 closes bypasses a child can do from settings by an allowlist default; one list of my duties; small fixes.
- **4.10 (2026-11-18):** GNOME's Reduced Motion setting; Escape never navigates back; D8 uninstall; VTE explicit mode; Godot's Android screen-reader gap closes when the engine supports it; T0 questions block the merge; small fixes.
- **4.9 (2026-11-18):** an owner budget; parent's control defined; TRAIN4 fits frozen formats and invented plants; the held-out revert rule has a tolerance and never reverts safety fixes; required updates; public tools may report publicly; hook-up edits need my approval; small fixes.
- **4.8 (2026-11-18):** T13 republishing; TRAIN4 traceable training content; adoption phases versus my duties; a falling held-out score reverts; D7 updates; install steps never lower security; Android permissions and recents; iPhone timing; filter history is opt-in; the rule digest; small fixes.
- **4.7 (2026-11-18):** due dates in cycles for products that deploy on merge, and a burn-down plan for fails found at adoption; the held-out data never leaves my machine; evidence tools stay out of product manifests; owner-check items are per PR; L3 by automated clip detection; MAC-address bypasses and a phone-reachable cut-off control; the hook-up comes first at adoption; hardware reasons can't cover the devices the profile commits to; `--yes` confirms; one named reference per choice; Godot screens built in code; private reports in every product; receiving while closed.
- **4.6 (2026-11-18):** hardware I don't own no longer breaks the backlog rules; reviews can start before the prompt script; INP measured from event durations, not TBT; emergency follow-up severity; prototype reviews; evidence refs that clones don't fetch; MSG6 deletes confirm; declarations versus the never-waivable set; Godot screens; small fixes.
- **4.5 (2026-11-18):** candidate goldens and rendered-order dumps; local evidence manifests on an orphan branch; tie-breakers make agents' UI choices doc-settled; owner-check queue limits; FILTER4 covers the product's own exits and imprecise ratings; READER and VIEW kinds; P6 prefetch; project testing rules; narrower severity floors; rules named in words for me; HAND1 versus T5; a Public tool stage; platform and API terms; T0 checked against my checklist; added rows travel with their change; Arabic size met by fonts; emergency fixes keep both code passes; consequences for missed adoption phases; held-out data out of the agent's reach.
- **4.4 (2026-11-18):** the change-kind map reaches every Block rule (with a lint); new screens bring their own fixtures; canaries in a detached worktree; field reports stay private; outside links confirm before acting; GM10.5; release gates; T9's law references; IRIS for Linux; the owner edits the live channel description.
- **4.3 (2026-11-18):** after the next adversarial review: the review machinery runs from the base branch; procedure and course content is always checked by me; switches have a lifecycle; snapshots are mine, with a held-out part; judgement rules gate the release, not the merge; recipients and shared audiences (MSG6); an Unaffected result; prose follows AGENTS.md; Arabic judged by golden screenshots; SHARE5; recognition confidence; fixes to the Tool stage, delegated passion work, alternatives, undo toasts, size budgets, the Not-checked cap and the phone density.
- **4.2 (2026-11-18):** after the next blind review: hook-up lines for AGENTS.md (Appendix G); Block fails can't be cleared by an adjudicator; adversarial pass at every tier; owner duties that are overdue don't block agents; local canaries; one combined score for real-data ratchets; game text on phones, 200 % text scaling on GNOME and Windows, Win32 dark mode, undo toasts, Telegram limits, Godot isolates, FILTER4's bypass list; defined major and stable releases.
- **4.1 (2026-11-18):** after a blind and an adversarial review of 4.0: fits with Walkdown's and tele-notify's own policies and with AGENTS.md (both passes for every tier); adoption doesn't freeze existing products; a Tool stage; the stage follows the facts; what agents may decide alone; only I write my verdicts; private real-data evaluations; evidence the author can't curate; product kinds (7.9); shared sessions in games (GM10); install and setup as main tasks; fixes to game text sizes, captions, focus, Arabic isolation, GNOME shortcuts, Telegram limits and the web budgets; the change-kind map replaces the rule index.
- **4.0 (2026-11-18):** tailored to my products (web, GNOME, Android, Windows, Godot, terminal, command line, bot messages) and my workflow (AGENTS.md, subagent reviews, my check before release). Dropped what none of my products has: consoles, TV, XR, voice, wearables, cars, kiosks, regulated devices, ads, purchases, large-team process and statistics. Removed IDs: A17 (speech input), T3 (prices), T10 (ads).
- **1.0 to 3.0:** a general policy for any app or game, reviewed in two rounds of blind and adversarial passes.

## Appendix F. Sources

- WCAG 2.2: https://www.w3.org/TR/WCAG22/ · WCAG2ICT: https://www.w3.org/TR/wcag2ict-22/
- GNOME Human Interface Guidelines: https://developer.gnome.org/hig/
- Material 3: https://m3.material.io/ · Android accessibility: https://developer.android.com/guide/topics/ui/accessibility
- Xbox Accessibility Guidelines: https://learn.microsoft.com/en-us/gaming/accessibility/guidelines
- Game Accessibility Guidelines: https://gameaccessibilityguidelines.com/
- AbleGamers APX: https://accessible.games/accessible-player-experiences/
- Command Line Interface Guidelines: https://clig.dev/
- Core Web Vitals: https://web.dev/articles/vitals
- Deceptive patterns: https://www.deceptive.design/types
- BBC subtitle guidelines: https://www.bbc.co.uk/accessibility/forproducts/guides/subtitles/
- My evidence-first engineering policies (platform and web), and AGENTS.md.

## Appendix G. Hook-up lines for AGENTS.md

To add under AGENTS.md's "Engineering decisions" heading (with the path adjusted to where this file lives):

```markdown
## UI and UX

For any change a user can see, hear or touch, follow `global/UI-UX-POLICY.md` (its section 0.2 says how it fits the
steps above): its evidence is part of step 2, its blockers (section 9) are part of step 5's "merge when CI is green",
and in step 6, don't deploy a tier-2 or tier-3 UI change that is still waiting for my check (its section 8.5), unless
it is merged switched off; report it as waiting instead. A parent agent that delegates UI work to a subagent runs
this policy's evidence and passes on the result itself.
```

## Appendix H. Rule index

One line per group; B = Block, A = Advice.

- **U:** U1 (B) Every main task can be done; U1a (B) Every offered task can be done; U2 (B) Main tasks meet their targets; U3 (A) Task cost doesn't creep; U4 (A) Frequent things are fast; U5 (B) No dead ends; U6 (A) Sensible defaults; U7 (A) Context is kept.
- **N:** N1 (B) Users know where they are; N2 (B) Back and close behave; N3 (B) Close and back never scroll away; N4 (A) Shallow, in users' words; N5 (B) Addresses work and last; N6 (A) Search where things are many; N7 (B) Modals are rare.
- **V:** V1 (B) Every screen in the screen table has an intent, and the look follows it; V2 (B) At most one primary action per view; V3 (B) Tokens, not literals; V4 (B) A spacing scale and alignment; V5 (B) A type scale; V6 (B) Colour with a job; V7 (A) Density fits the users; V8 (B) Space is used; V9 (A) Icons are clear; V10 (A) Images are sharp; V11 (B) Motion has a purpose; V12 (A) Polish; V13 (B) Before and after are compared; V14 (B) Core interactions have a feel spec; V15 (B) Charts tell the truth.
- **A:** A0 (B) The baseline; A1 (B) Text contrast; A2 (B) Non-text contrast; A3 (B) Minimum text sizes; A4 (B) Text scales; A5 (B) Colour is never the only signal; A6 (B) Text over pictures has a backing; A7 (B) Dark and light; A8 (B) Screen readers; A9 (B) Magnification; A10 (B) No seizures; A11 (B) Reduced motion; A12 (B) Sight isn't required; A13 (B) Sound is never the only signal; A14 (B) Captions; A15 (B) Audio description; A16 (B) Volumes; A18 (B) Every first-class input method does every task; A19 (B) Target sizes; A20 (B) Simple alternatives to gestures and motion; A21 (B) Time limits the user can change; A22 (B) No hold, mash or chord required; A23 (B) Focus is visible and never hidden; A24 (B) Plain language; A25 (B) Predictable; A26 (B) Nothing to remember or re-enter; A27 (A) One thing at a time; A28 (B) Usable with cognitive disabilities; A29 (B) Generated documents are accessible; A30 (B) Haptics are optional.
- **I:** I1 (B) Controls look like what they do; I2 (B) Platform controls first; I3 (B) Shortcuts are discoverable and safe; I4 (B) Disabled things say why; I5 (B) Values can be copied; I6 (A) Direct manipulation where it helps; I7 (B) Inputs mix freely; I8 (B) Tables work; I9 (B) History is visible.
- **F:** F1 (B) Every action gets a response; F2 (B) Results the user can't see are confirmed in words; F3 (B) Optimistic updates are honest; F4 (B) Status is visible.
- **P:** P1 (B) No freezes; P2 (A) No hitches; P3 (B) Start-up; P4 (B) Nothing jumps; P5 (B) Budgets don't regress; P6 (A) Feels fast; P7 (B) Local is instant on main tasks.
- **W:** W1 (B) Users' words, one word per thing; W2 (B) Buttons say what they do; W3 (B) Errors in plain words; W4 (A) Short and scannable; W5 (B) Counts, units, dates; W6 (A) One voice; W7 (B) Never cut what matters.
- **E:** E1 (B) Visible labels; E2 (B) The right keyboard and help; E3 (B) Validation helps; E4 (B) Ask only what's needed; E5 (B) Never lose input; E6 (A) Constraints up front.
- **S:** S1 (B) Losing data is undoable or confirmed; S2 (B) Confirmations are safe; S3 (B) Work and progress are never lost silently; S4 (B) Errors recover; S5 (B) Bulk decisions; S6 (B) No hidden side effects; S7 (B) Test and real are never confused; S8 (B) Live systems stay reachable; S9 (B) Access can be recovered.
- **ST:** ST1 (B) Every state is designed; ST2 (A) Empty states teach; ST3 (B) Offline is a state; ST4 (B) Failures are contained; ST5 (B) Others are visible.
- **C:** C1 (B) One design system per product; C2 (B) Same thing, same name, same look, same place; C3 (B) Platform conventions are kept; C4 (B) Parity or a record; C5 (B) New concepts earn their place; C6 (A) Remove what doesn't earn its place.
- **H:** H1 (B) First run; H2 (B) Help is findable; H3 (A) Teach in context; H4 (B) What was taught can be looked up; H5 (A) Grow with the user.
- **O:** O1 (B) Notifications are opt-in and earned; O2 (B) Each notification stands alone; O3 (B) Respect the moment; O4 (A) Badges mean something.
- **T:** T0 (B) The law's interface duties; T1 (B) No dark patterns; T2 (B) Leaving is as easy as joining; T4 (B) Permissions and data; T5 (B) Privacy in the UI; T6 (B) Usable security; T7 (B) Untrusted content stays content; T8 (B) Wellbeing; T9 (B) Children; T11 (B) Accessibility statement and barrier reports; T12 (B) Download pages are true; T13 (B) Republishing keeps its audience.
- **D:** D1 (B) Settings stick; D2 (B) Settings are findable; D3 (B) Updates don't ambush; D4 (B) Data is the user's; D5 (B) Interruptions lose nothing; D6 (B) Learned and scripted surfaces are contracts; D7 (B) Updates are offered, not forced; D8 (B) Uninstalling leaves nothing behind.
- **AI:** AI1 (B) Labelled; AI2 (B) Explained; AI3 (B) The user stays in control; AI4 (B) Honest about limits; AI5 (A) Correctable.
- **L:** L1 (B) Whole strings; L2 (B) Mixed and right-to-left text reads correctly; L3 (B) Layouts survive other text; L4 (B) Local formats; L5 (A) Fonts cover the content; L6 (B) Translations are checked on screen.
- **WEB:** WEB1 (B) Full WCAG AA; WEB2 (B) Browser features work; WEB3 (B) Native elements first; WEB4 (B) Browsers and widths; WEB5 (B) Offline and updates; WEB6 (B) Small servers.
- **GNOME:** GNOME1 (B) libadwaita patterns; GNOME2 (B) Adaptive; GNOME3 (B) System style; GNOME4 (B) Accessible and keyboard; GNOME5 (B) Text direction; GNOME6 (B) Privileges.
- **AND:** AND1 (B) Material and insets; AND2 (B) Back; AND3 (B) State survives; AND4 (B) Scale and size; AND5 (B) Semantics and targets; AND6 (B) Permissions and background work; AND7 (A) Thumb reach.
- **WIN:** WIN1 (B) Controls, keys, themes; WIN2 (B) UI Automation; WIN3 (B) Reading order.
- **GM:** GM1.1 (B) Remapping; GM1.2 (B) Prompts match the device; GM1.3 (B) Sensitivity and inversion; GM1.4 (B) Alternatives to hard inputs; GM1.5 (B) Touch controls; GM1.6 (A) Conventions; GM2.1 (B) Difficulty is a choice, not a judgement; GM2.2 (B) Assists don't punish; GM2.3 (A) A curve; GM3.1 (B) Threats and targets are readable; GM3.2 (B) Failure is explained; GM3.3 (B) The core loop feels right; GM3.4 (B) Picking things in the world; GM4.1 (B) Readable HUD; GM4.2 (B) Adjustable UI; GM4.3 (B) Objectives can be recalled; GM4.4 (A) Diegetic UI has a fallback; GM4.5 (B) Close and back; GM5.1 (B) Pause anywhere; GM5.2 (B) Progress is safe; GM5.3 (B) Cutscenes and dialogue; GM5.4 (A) Sessions fit the device; GM6.1 (B) Frame rate; GM6.2 (B) Input latency; GM6.3 (B) Loading; GM7.1 (B) Subtitles and captions; GM7.2 (B) Important sounds can be seen; GM7.3 (B) Menus can be read aloud; GM8.1 (B) Motion comfort; GM8.2 (B) First launch; GM8.3 (B) Warnings; GM9.1 (B) High-contrast world; GM9.2 (B) Navigation help; GM9.3 (B) Sound cues shown; GM10.1 (B) Pause in company; GM10.2 (B) Voice has alternatives; GM10.3 (B) The connection is a visible state; GM10.4 (B) Roles are clear; GM10.5 (B) Who's in the session.
- **TUI:** TUI1 (B) 80 × 24 and resizing; TUI2 (B) Keys; TUI3 (B) Theme colours; TUI4 (B) No injected markup; TUI5 (B) Arabic in the terminal; TUI6 (B) Beside a running service.
- **CLI:** CLI1 (B) Help and discoverability; CLI2 (B) Errors in plain words; CLI3 (B) Safe by default; CLI4 (B) Re-running is safe; CLI5 (B) Progress and results; CLI6 (B) Output for people and for scripts; CLI7 (B) Asking questions; CLI8 (B) Constrained shells.
- **MSG:** MSG1 (B) Why and what next; MSG2 (B) Outside text; MSG3 (B) Pace and reliability; MSG4 (B) Commands and limits; MSG5 (B) Control; MSG6 (B) Shared audiences.
- **READER:** READER1 (B) Reading direction; READER2 (B) Pick up where you left off; READER3 (B) Fit and zoom.
- **VIEW:** VIEW1 (B) From search to the tag; VIEW2 (B) Smooth at scale; VIEW3 (B) Usable at every zoom.
- **SHARE:** SHARE1 (B) Accept before receiving; SHARE2 (B) Visibility modes; SHARE3 (B) Start where people are; SHARE4 (B) Speed and finishing; SHARE5 (B) Capability check.
- **ALERT:** ALERT1 (B) Latency; ALERT2 (B) Filter quality; ALERT3 (B) See what was missed.
- **TRAIN:** TRAIN1 (B) Content checked; TRAIN2 (B) Debrief; TRAIN3 (B) Progress and records; TRAIN4 (B) Content is traceable and current.
- **FIELD:** FIELD1 (B) Report a problem; FIELD2 (B) Real field conditions.
- **FILTER:** FILTER1 (B) Explain the block; FILTER2 (B) Mistakes reach the parent; FILTER3 (B) Warn before cut-off; FILTER4 (B) Enforce and admit gaps.
- **HAND:** HAND1 (B) Hand over by QR or copy.
- **Z:** Z1 (B) Synthetic data for evidence; real data only in private.
