# The replay the specs check

`golden.jsonl` is one run written down. `spec/roguelike/replay_spec.cr` plays it again and compares
every fingerprint in it against what this build produces.

It holds the actions, so the run is fixed. What changes between builds is the fingerprints.

Record it again with:

```sh
script/record-golden
```

Run that after any change that moves `Game#fingerprint`. A change to the generator, to a rule, and
to anything the character is told all do, because the message log is part of the state. The actions
stay as they are and only the fingerprints and the stamps are written afresh.
