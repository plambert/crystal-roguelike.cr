# The replays the specs check

Both files hold the same run: the same seed and the same actions. They differ in the fingerprints.
`spec/roguelike/replay_spec.cr` plays each one again and compares every fingerprint in it against
what this build produces, under the scheme each value names.

* `golden.jsonl` holds fingerprints of the streamed scheme, `sha256s:`. This build records that
  scheme, so the file says this build plays the run the way it did when the file was recorded.
* `golden-sha256.jsonl` holds fingerprints of the canonical scheme, `sha256:`. Builds before the
  streamed scheme recorded those. The file says a replay from such a build still verifies.

Record both again with:

```sh
script/record-golden
```

Run that after any change that moves `Game#fingerprint`. A change to the generator or to a rule
does. The actions stay as they are and only the fingerprints and the stamps are written afresh.
The game never records the canonical scheme. The script sets it for `golden-sha256.jsonl` alone.
