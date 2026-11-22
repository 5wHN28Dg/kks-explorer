# Walkdown 1.0 (approved 2026-11-23)

The user approved this scope on 2026-11-23. Walkdown Plant's 1.0 and its 0.4.0 demo build are in
docs/plant3d/MILESTONES.md, under "v1.0 scope". Walkdown 1.0 comes first.

**Goal:** the daily tool, finished and safe to update. **Target:** December 14–23, 2026. **GitHub milestone:**
"Walkdown 1.0".

## In 1.0

- **Every severity 1 and 2 UX issue fixed.** None is at severity 1. The severity 2 issues are: Back and Escape (#366
  and its follow-ups #429–#431), touch targets (#367), contrast (#368, #369), colour as the only signal (#370),
  screen-reader names (#374, #433), alternatives to gestures (#375), text size and layouts (#376), Windows scaling
  (#377), the destructive-action follow-ups (#414–#417), a reading correction being typed that gets lost (#466), and
  #441 and #448 below.
- **Owner checks done and their switches turned on:** #485 (the web's phone header), #488 (offline state, with #372),
  #513 (Windows dark colours), #516 (Windows text size). Their blockers get fixed first: #511, #483, #486, #487, #489.
  Also #442, the policy decisions only the owner can make.
- **Updates and destructive actions:** #441 (a server update reports PASS or FAIL), #439 (the install guides explain
  the warnings beforehand, and give Plant's install steps), #448 (removing a device needs a deliberate act).
- **The release** on every platform, with the full Android e2e, the Windows VMs and CI green; then the deploy.
- **Docs:** the user and manager guides on the wiki, and release notes.
- **Release-ready means:** the release gates, plus every severity 1 and 2 issue fixed, plus the owner checks done.
- **Known dependency advisories** (libjxl, zlib: #57, #58, #72) don't hold the release. The release notes name them.
  Upgrade as soon as a non-major fixed version exists.
- **Owner checks** use the policy's normal monthly budgets (60 and 30 minutes). There is no extra December budget, so
  the date depends on when the owner can do the checks.

## Later (post-1.0)

- The importer and data backlog in CLAUDE.md. It improves the data, not the app, and can run alongside as data work.
- The severity 3 and 4 UX issues. The policy gives them no due date.
- The policy's phase 3: the full audit and the first round with real users, by its own date.
- The flaky-test issues (#360, #398, #420, #497) and #494. Fix any of them that blocks a release run.

Any open Walkdown issue that is in no GitHub milestone is post-1.0.
