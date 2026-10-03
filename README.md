# crystal-roguelike

TODO: Write a description here

## Installation

### Homebrew

```bash
brew install plambert/tap/crystal-roguelike
```

That installs the game as `roguelike`. Homebrew asks you to trust a
third-party tap before it will load anything from it; answer the prompt, or
settle it first with `brew trust plambert/tap`.

Bottles are published for Apple Silicon macOS and for x86_64 and arm64 Linux,
so the install pours a binary rather than building one. On an Intel Mac there
is no bottle, and Homebrew cannot install the Crystal compiler there either,
so use a release binary or build from source with a compiler you already have.

### A binary from the releases page

Each tagged release carries a tarball per platform, with `SHA256SUMS` beside
them. It also carries a test build tarball per platform, named
`crystal-roguelike-$version-test-$platform.tar.gz`, which holds
`crystal-roguelike-test`. A test build records a replay log of every run it
plays; see [A test build](#a-test-build).

```bash
version=0.2.1
platform=macos-aarch64   # or linux-x86_64, linux-aarch64
base=https://github.com/plambert/crystal-roguelike.cr/releases/download/v$version

curl -LO "$base/crystal-roguelike-$version-$platform.tar.gz"
curl -LO "$base/SHA256SUMS"
shasum -a 256 --check --ignore-missing SHA256SUMS

tar xzf "crystal-roguelike-$version-$platform.tar.gz"
```

That leaves a `crystal-roguelike-$version-$platform` directory holding the
binary, the licence and this file. Put the binary wherever you keep such
things; it needs nothing beside it.

The Linux binaries are statically linked against musl and run on any
distribution. The macOS binary links every library except libSystem from its
archive, so it needs nothing from Homebrew.

### A nightly build

The head of the default branch is built every night that something was
committed to it, and published as the `nightly` release. Those tarballs carry
no version in their names, so these links go on working:

```bash
platform=macos-aarch64   # or linux-x86_64, linux-aarch64
base=https://github.com/plambert/crystal-roguelike.cr/releases/download/nightly

curl -LO "$base/crystal-roguelike-nightly-$platform.tar.gz"
curl -LO "$base/SHA256SUMS"
shasum -a 256 --check --ignore-missing SHA256SUMS

tar xzf "crystal-roguelike-nightly-$platform.tar.gz"
```

Each platform also has a test build, as
`crystal-roguelike-nightly-test-$platform.tar.gz`. It records a replay log of
every run it plays; see [A test build](#a-test-build).

A nightly is built the same way a release is, from the same workflow. It
reports the version in `shard.yml`, which is the version being worked towards
rather than one that has been released. The commit it came from is named in
the release notes, and the game prints it beside the version in the debug
console.

### From source

Crystal 1.21 or newer, and git-lfs, which one of the dependencies uses for its
terminal measurements:

```bash
git clone https://github.com/plambert/crystal-roguelike.cr.git
cd crystal-roguelike.cr
shards install
shards build --release
./bin/crystal-roguelike
```

Without git-lfs on your PATH, `shards install` fails partway through checking
out `termbuf`. Setting `GIT_LFS_SKIP_SMUDGE=1` does not help, because git
cannot start the filter at all; either install git-lfs or take the filter out
of the picture with `GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_GLOBAL=/dev/null
shards install`. The images are never read by the compiler.

The version the binary reports comes from `shard.yml`, which a macro reads at
compile time by running `shards version`.

### A test build

A test build records a replay log of every run it plays, so a bug found in
play can be reproduced exactly:

```bash
shards build -Dtest_build
./bin/crystal-roguelike --version   # crystal-roguelike 0.2.1 (test build)
```

The logs go to `$XDG_STATE_HOME/roguelike/test_logs/`, or
`~/.local/state/roguelike/test_logs/` when that variable is not set, one
file per run named for the time it started, the seed and the character.
`--replay-log` still names a file of your own. A character saved and carried
on with `--character` goes on in the same file. Check one with
`crystal-roguelike replay verify FILE`.

A test build also offers to send each run's log to the developer. The first
run prints what is sent and asks for a yes or no, and keeps the answer in
`autosubmit` under the state directory. Nothing is sent without a yes.
`--no-autosubmit` turns it off for a run, and `--autosubmit` asks again or
turns it on in any other build. Logs are sent when the game exits, after each
save and after each run that ended. One that could not be sent waits in the
`outbox` directory and goes out next time.

On macOS, `script/build-test` builds a test build that needs nothing from Nix
or Homebrew, so the binary runs on another Mac. It writes
`bin/crystal-roguelike-test` and fails if the binary links any dylib besides
libSystem. The build needs the Homebrew formulas `bdw-gc`, `pcre2`,
`openssl@3` and `zlib`, plus `curl`, `cc`, `make` and `libtool`. The first run
downloads GNU libiconv and builds it into `.static-libs/`. Later runs reuse it:

```bash
script/build-test
```

## Usage

TODO: Write usage instructions here

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/plambert/crystal-roguelike.cr/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

* [Paul M. Lambert](https://github.com/plambert) - creator and maintainer
