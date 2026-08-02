# Contributing

Issues and pull requests are welcome. This is a small package maintained alongside the
rest of the Physiology Workbench family, so responses may be slow.

## Building

```sh
swift build
swift test        # 23 tests, all synthetic
```

CI runs the same on macOS and additionally builds for the iOS simulator; both platforms
are hard requirements.

## House rules

These are the ones a patch is most likely to trip over. The reasoning behind them is in
[LESSONS.md](LESSONS.md).

- **Cite before you port.** A new algorithm gets its [PROVENANCE.md](PROVENANCE.md)
  entry — reference, upstream implementation, pinned commit, key constants — in the same
  commit as its source file. Any change to an algorithm updates that entry.
- **Causal where it matters.** The correctors and the detector run on a live stream and
  may not look forward. Batch variants belong behind the same protocols, but must be
  named as batch at the call site.
- **Nothing Swift-specific in the public surface.** Plain data across the boundary: no
  actors, no `AsyncStream`, no Foundation-only types where a plain one exists.
- **Constants are answerable to hardware.** Every constant here was provisional until a
  chest said otherwise, and one of them was wrong when it did. A patch changing one
  should be re-checked against the annotated Polar H10 protocol (in the PolarKit repo's
  `POLAR.md`), not against the synthetic tests alone.
- **A fallback path is not covered until you have watched its test fail.** Break the
  path deliberately, watch the test go red, put it back.
