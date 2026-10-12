# macmon

Rootless Apple Silicon monitor and Rust library. Shared sampling and metric types live in `src/metrics.rs`, macOS API access in `src/sources.rs`, and CLI commands in `src/app/`.

The TUI is in `src/app/tui/`. Per-process usage (`src/app/procs.rs`) comes from libproc for the user's own processes, the setuid `/bin/ps` for other users' processes, and GPU time from the IORegistry (`IOAccelerator` children).

## Development

- Keep CLI-only code and dependencies behind the `app` feature; preserve library builds with `--no-default-features`.
- Keep normal metric collection rootless and preserve fallbacks for older systems.
- Add focused tests for changed behavior. `make prepare` applies formatting and fixes; do not use it as a read-only check.
- Change dependencies only with `cargo add` / `cargo remove` / `cargo upgrade`, never by hand.
- Makefile: the first `.PHONY` lists the standard targets (`prepare`, `check`, `test`, `build`, `update`); project-specific targets go after them in their own section with a second `.PHONY`. A target longer than a line or two calls a script in `scripts/` (`sh`, or Python run with `uv run`).
- Never run Instruments or `xcrun xctrace` (Metal System Trace): on the owner's Mac it froze the window server and needed a hard reset. Profile with sampling tools such as `sample` or a temporary local timer.
- TUI colors only through `tui/theme.rs` (terminal ANSI colors, no RGB), so macmon follows the terminal's theme.
- Keep `~/.config/macmon.json` compatible with released versions: same field names and values (`view_type` is `"Sparkline"` / `"Gauge"`).
- Release builds abort on panic: every terminal mode the TUI enables must be undone in `restore_term_once`.
- The TUI saves settings on key presses: for manual runs set `HOME` to a temporary directory.

## Metric sources

- Before investigating or changing power sources, read [Power sources and macOS 27](readme.md#power-sources-and-macos-27) and the relevant evidence in [docs/clpc-discovery.md](docs/clpc-discovery.md).
- Check counter availability before treating zero CPU/ANE readings as zero consumption.
- Verify CLPC report IDs, CPU/GPU/ANE assignments, and units against an independent reference under separate component loads. Table positions and response to load alone do not establish a mapping.
- For sampling changes, validate rootless readings with `macmon pipe` on the affected hardware and macOS version. Report runtime results separately from build and unit-test results, and identify untested configurations.

## Workflow

- Work directly on `main`: commit and push, one line in the style of the history (`feat: …`, `fix: …`, `chore: …`, `docs: …`), no body, docs updated in the same commit. No branches, no pull requests, no worktrees — this is the owner's own fork and it is not developed through review.
- Before each commit, run `make check` (it also checks the library alone, with `--no-default-features`) and `make test`; runtime behaviour that the tests can't cover is checked by hand (`macmon pipe`, `macmon debug`, the TUI) and reported separately from the build.
- Keep planned work in [docs/roadmap.md](docs/roadmap.md), not in GitHub issues; link each item's plan there and tick the item in the commit that finishes it.
- Keep features small. Measure production lines (tests excluded) with `make loc REF=origin/main` and report the change with the work. When a feature needs more than ~200 production lines, the implementing agent stops and reports to the orchestrator before going on; the orchestrator simplifies the task or asks the person. There is no fixed budget for the whole codebase.
- Agree the plan with the person. For multi-step work write the plan to `docs/plans/yyyymmdd-<name>.md`: the agreed behavior, decisions and a task checklist. While working, only tick its checkboxes: no evidence, progress or status prose. The commit that finishes the plan's last item adds a first line `Done: yyyy-mm-dd` and a short final `## Result` section, and moves the plan to `docs/plans/completed/` (fixing links to it). Plans stay; never delete them.
- Review the diff before pushing a feature, and treat the checks as the gate: run `codex review -c model_reasoning_effort=xhigh "Review the working tree against origin/main. make check and make test were run."` when it is available, and fix or reject each finding with a reason. There is no pull request and no automatic review to catch what this misses.
- A release is a `release: vX.Y.Z` commit on `main` (changelog written by the person's skill, version bumped); CI then publishes the crate, the GitHub release and the Homebrew formula.
- Batch small related changes (docs, tooling, small fixes) into one commit instead of one commit each.
- The agent the person talks to orchestrates: it writes each task for a subagent, verifies every report itself (the diff, `make check`, `make test`, runtime results where relevant) instead of trusting it, and keeps the person informed. It does directly only small edits that depend on its own context.
- Report a blocker as soon as you hit it: an unreachable machine, a missing permission or tool, a failing service, or anything else that stops the task. Tell whoever delegated the task right away (a subagent messages the orchestrator), say what can still be done without it, and keep doing that part. Never wait or poll silently for more than a few minutes.
- Ask the person only when JSON or Prometheus output, the config format or the library API must break, a new dependency is needed, or the request is ambiguous. Otherwise decide and say so in the report.
- Keep docs to `readme.md` (users), the rustdoc, `docs/roadmap.md`, `docs/plans/` and the research notes in `docs/`. No progress journals, hash receipts, run logs or disclaimer paragraphs.
- `changelog.md` is written only in a release commit, by the person's changelog skill from the git history: don't edit it in feature work.
