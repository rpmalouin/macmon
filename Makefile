.PHONY: prepare check test build update

CARGO_FLAGS := --release --locked

prepare:
	cargo +nightly fmt
	cargo clippy $(CARGO_FLAGS) --workspace --fix --all-targets --allow-dirty -- -D warnings
	cargo check $(CARGO_FLAGS)

check:
	cargo +nightly fmt --check
	cargo clippy $(CARGO_FLAGS) --workspace --all-targets -- -D warnings
	cargo check $(CARGO_FLAGS) --bin macmon
	cargo check $(CARGO_FLAGS) -p macmon --lib --no-default-features
	cargo check $(CARGO_FLAGS) -p macmon-ffi

test:
	cargo test $(CARGO_FLAGS) --workspace

build:
	cargo build $(CARGO_FLAGS) --workspace
	ls -lh target/release/$(shell basename $(CURDIR))

update:
	cargo upgrade -i

.PHONY: loc bench remote macapp macapp-run macapp-test macapp-icon macapp-install macapp-uninstall

loc: # production lines, tests excluded; REF=origin/main compares with a git ref
	@python3 scripts/loc.py $(REF)

bench: # compare startup time
	cargo build $(CARGO_FLAGS)
	hyperfine --warmup 3 --min-runs 60 \
		'macmon pipe -s 1 -i 100' \
		'./target/release/macmon pipe -s 1 -i 100'

remote:
	@test -n "$(host)" || (echo "Usage: make remote host=user@host" >&2; exit 1)
	@rsync -az Cargo.toml Cargo.lock Makefile src "$(host):macmon/"
	@ssh "$(host)" 'cd ~/macmon && cargo build $(CARGO_FLAGS) && ./target/release/macmon debug'
	@ssh "$(host)" 'cd ~/macmon && ./target/release/macmon pipe -s 1 -i 100 > /dev/null'

macapp: # the menu bar app in dist/, ad-hoc signed (scripts/app-build.sh)
	scripts/app-build.sh

macapp-run: # build the app and open it
	scripts/app-build.sh run

macapp-test: # the app's Swift tests
	scripts/app-build.sh test

macapp-icon: # draw and pack the app icon (scripts/make-icon.sh)
	scripts/make-icon.sh

macapp-install: # build, then copy the app to /Applications (or ~/Applications)
	scripts/app-build.sh install

macapp-uninstall: # remove the installed app
	scripts/app-build.sh uninstall
