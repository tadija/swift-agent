# Provenance and release conventions

Extracted from `https://github.com/tadija/boy-scout-agent` at commit
`21c1fd6` after architectural Stages 1 and 2. The independent repository starts with one fresh initial commit, as requested by
the owner. No BSA Git commits or refs are transferred. The original MIT license
and copyright attribution are retained. The implementation derives from the
source snapshot above; historical implementation details remain available in
the original repository rather than being imported here.

The first independent version is **0.1.0**, matching `VERSION`. A local annotated
`0.1.0` tag identifies the tested extraction commit. It is not a published
release until the owner pushes that commit and tag to the intended upstream.
Never move a published tag. Use Semantic Versioning; compatible pre-1.0 fixes use
patch releases, and breaking changes use a new minor version. Downstream BSA uses `0.1.0..<0.2.0` (`upToNextMinor`) so a pre-1.0
breaking minor update is not selected automatically. Consumers should review
upgrades and commit their resolved dependency when available.

## Publication sequence (owner action)

After validation and authorization, push upstream `main` and its `0.1.0` tag to
`git@github.com:tadija/swift-agent.git`. Confirm a fresh BSA checkout resolves
`https://github.com/tadija/swift-agent.git` without a mirror, run downstream tests,
and commit the resulting `Package.resolved` before publishing downstream changes.
No GitHub release or remote push is performed by local extraction tooling.

Both repositories own tiny metadata/installer tooling for their own executables;
this intentionally avoids making downstream product metadata part of the engine.
The CLI's self-update hook remains application-owned. The generic CLI is updated
by rebuilding its checkout with the installer. CI packages independently tested
binaries for each host platform; these are workflow artifacts, not releases.

## Initial-release amendment

The owner explicitly authorized amending the initial commit and recreating the
already-published `0.1.0` tag for the final documentation layout. The example
mission now lives at `Docs/Examples/PROMPT.md`. Downstream lockfiles must resolve
the recreated tag revision. This is an authorized initial-release correction;
future published tags should remain immutable.
