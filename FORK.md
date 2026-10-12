# This fork

`rpmalouin/macmon` is a fork of [`vladkens/macmon`](https://github.com/vladkens/macmon), made for one
purpose: a native macOS menu bar app on the same sampler, for my own Mac (an M5 Max on macOS 27).

Upstream is the reference implementation and the source of everything shared — the sudoless sampler, the
terminal UI, `pipe`, `serve`, `stress`, `find-clpc` and the Rust library. This fork keeps all of it and
adds the app. Nothing here is written with the intent of being merged upstream, and nothing here is
published: no crates.io, no Homebrew, no release artifacts. Build it from source.

Nothing is filed upstream either — no pull requests and no issues. The fixes below live here, are
maintained here, and stay local deltas against upstream by design (see [Keeping in step](#keeping-in-step-with-upstream)).
Fork this repository if you want any of it, and support your copy.

If you are looking for `macmon` the tool rather than this app, use upstream:
[`brew install macmon`](https://github.com/vladkens/macmon).

## What the fork adds

### 1. A C ABI over the sampler — `ffi/` (267 production lines)

`macmon-ffi` is a workspace member (`publish = false`) built as an `rlib` + `staticlib`, with a plain C
header at [`ffi/include/macmon.h`](ffi/include/macmon.h). It returns each sample as the same JSON the
`pipe` command emits, rather than as a struct of fields: the ABI then stays fixed while metrics grow, and
a new metric reaches every consumer by existing in `Metrics`.

The library side of the same change: per-process sampling moved out of the app and into the library
behind a new `procs` feature (`src/procs.rs`), so the ABI and the TUI read processes from one place
instead of two.

This is roadmap item 4, done as far as the app needed it. The remaining part of that item — packaging the
dylib and an `XCFramework` — is not done; the app links the staticlib directly.

### 2. The menu bar app — `macos/` (1,319 production lines, 550 test lines)

A SwiftPM package: `MacmonCore` (the model, testable without a screen), `MacmonApp` (the status item and
panel), and `CMacmon`, the clang shim that carries the C header into Swift. SwiftUI for the panel, AppKit
for the status item — an `NSStatusItem` rather than a SwiftUI `MenuBarExtra`, because the threshold dot
carries colour and an attributed title can be set and tested where a menu bar extra's label rendering
cannot.

- `scripts/app-build.sh` builds, signs ad-hoc, and installs the bundle; `make macapp*` wraps it
- `scripts/make-icon.sh` draws the icon with `swift` into `macos/Resources/Macmon.icns`
- the bundle is `Macmon.app` (`LSUIElement`, macOS 14+), identifier `com.ronmalouin.macmon`
- "Start at login" writes `~/Library/LaunchAgents/com.ronmalouin.macmon.plist` — a plain LaunchAgent
  rather than `SMAppService`, which wants a signing identity this Mac does not have

Roadmap item 13.

### 3. Memory pressure in the sampler — `src/metrics.rs`, `src/sources.rs`

`MemMetrics` carries `ram_available` (free + inactive + purgeable + speculative pages) alongside
`ram_usage`, computed by a new `libc_memory()`; `libc_ram()` stays as a wrapper for its older callers.

The reason is a monitor that tells the truth: `ram_usage` is Activity Monitor's "Memory Used", which
counts reclaimable `inactive` pages, so a machine holding a resident local model reads 87–92% while
nothing is wrong, and any threshold on that figure either fires constantly or flaps. `ram_available` is
the pressure figure, and it is what the app's dot is judged on. Roadmap item 14.

### 4. Fixes in the served and device-supplied paths

- **`src/sources.rs`** — a `CFString` from a device (a HID `Product` report, for one) can be longer than
  any fixed buffer, so the conversion sizes its buffer from the string and returns an empty `String`
  rather than aborting the process when the value is not UTF-8. `Copy`-prefixed property reads return a
  `+1` reference: the `Product` key and each property are now released instead of leaking once per
  sample. `system_profiler` is called by absolute path.
- **`src/app/serve.rs`** — a client that opens a connection and stops sending used to hold its thread
  indefinitely; requests and responses now carry a 5-second deadline.
- **`scripts/clpc.py`** — device and build identifiers from an index or a `BuildManifest` are validated
  before being used as path components, so a value cannot write outside the output directory.

## What the fork deliberately leaves alone

These are the guarantees that make the fork safe to run beside upstream, and they are worth keeping:

- **`~/.config/macmon.json`** — the same field names and values, `view_type` as `"Sparkline"` /
  `"Gauge"`. A config written by this build reads in a released upstream build.
- **`pipe` and `/json`** — additive only. One new field (`memory.ram_available`); no renamed field, and
  the deprecated `ecpu_*` / `pcpu_*` aliases stay.
- **The library API** — additive only, and `cargo build --no-default-features` stays green.
- **No new external dependencies** in the library crate. The Cargo changes are the `procs` feature, the
  `ffi` workspace member, and its `[[bin]]`-free packaging.
- **The terminal UI** — untouched by the app work; the app reads the sampler, not the TUI.

## Where the code lives

| Path | What |
| --- | --- |
| `src/` | the sampler, metrics and CLI — upstream's, plus the `procs` feature and `ram_available` |
| `src/app/` | the CLI and the TUI — upstream's |
| `ffi/` | the C ABI, its header, and the JSON seam the app reads |
| `macos/` | the app: SwiftPM package, resources, Swift tests |
| `scripts/app-build.sh`, `scripts/make-icon.sh` | building, signing and installing the app |
| `docs/app.png` | the app screenshot the README shows |
| `dist/` | build output for the app (ignored by git) |

## Checking the app without a screen

The app takes debug switches from the environment, which is how its rendering is checked in a terminal:

| Variable | Effect |
| --- | --- |
| `MACMON_APP_DEBUG=1` | print each sample's status text and dot verdict |
| `MACMON_APP_DEBUG_COMPACT=1` | start with the compact label |
| `MACMON_APP_DEBUG_MINIMAL=1` | start with history and processes hidden |
| `MACMON_APP_DEBUG_POPOVER=1` | open the panel at launch, exercising the click path |
| `MACMON_APP_DEBUG_PNG=<path>` | write the panel as a PNG (via `ImageRenderer`) |

A debug run never saves preferences, so these cannot leave the app starting in a state a test set.

## Keeping in step with upstream

```sh
git remote add upstream https://github.com/vladkens/macmon   # once
git fetch upstream
git log --oneline main..upstream/main        # what is new upstream
git log --oneline upstream/main..main        # what this fork has
git merge upstream/main                      # or rebase, then build and test
```

The app, `ffi/` and `macos/` are fork-only and never conflict. The files both sides touch — `readme.md`,
`Cargo.toml`, `Makefile`, `docs/roadmap.md`, `agents.md`, `src/metrics.rs`, `src/sources.rs`,
`src/app/serve.rs` — are where a merge will need a look, most of all this `readme.md`, which now leads
with the app.

After any sync: `make check`, `make test`, `make macapp-test`, then run it (`make macapp-run`) and read
the panel — the numbers come from live counters, so a green build is not proof the app still shows the
right ones.

## Workflow (differs from upstream)

Upstream works through pull requests; this fork is the owner's own and commits straight to `main` — one
line, no body, no branches, no worktrees:

- `make check` (which also builds the library alone) and `make test` before each commit; the app's tests
  with `make macapp-test`; runtime behaviour checked by hand and reported separately
- docs updated in the same commit as the code they describe
- planned work in `docs/roadmap.md`, each plan in `docs/plans/`, moved to `docs/plans/completed/` when
  the last item of the plan lands
- `changelog.md` is written only in a release commit, from the git history

A release commit upstream triggers CI that publishes the crate, the GitHub release and the Homebrew
formula. This fork has no such pipeline and no intention of publishing, so do not write release commits
here.

## License

MIT, as upstream ([`LICENSE`](LICENSE), copyright vladkens), and the same terms cover this fork's
changes. Attribution stays in the source: the apps and files added here are the fork's, everything else
is upstream's work.
