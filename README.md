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
them:

```bash
version=0.1.0
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
distribution. The macOS binary links the collector and pcre2 from their
archives, so it needs nothing from Homebrew.

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
