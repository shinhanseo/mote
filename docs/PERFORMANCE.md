# Performance notes

Measured on the development Mac on 2026-11-02. These are short process-level measurements, not battery-life or watt measurements.

## Changes

- Build native binaries with `-O -whole-module-optimization` for both supported architectures.
- Release the panel's SwiftUI rendering tree on close; rebuild it on open. Hidden panel timelines no longer remain attached.
- Use explicit periodic panel animation schedules, with a static frame under Reduce Motion.
- Materialize menu icon frames as 1x/2x template bitmaps. An `NSImage` drawing handler is lazy: caching that object alone still executes drawing later.
- Animate menu icons at 2.5 frames/second; 1 frame/second in Low Power Mode, stopped while idle, screen asleep or Reduce Motion is enabled.
- Change the menu title and accessibility description only when their values/state change.
- Publish the job array and persist wait timestamps only when changed. Limit last-activity UI publishing to once/second; approval and input transitions are still handled immediately.
- Keep the 3-second local-record fallback and live IPC monitoring. Allow 0.3 seconds of timer coalescing tolerance.
- Cache usage snapshots by file size, modification time and inode; reparse changed files, filter quota candidates before JSON parsing, cap the cache at 64 paths.
- Drain Foundation autoreleased JSON temporaries per IPC frame on the long-lived worker; prune old question metadata with retained turns.

## Comparison

Both builds were freshly launched, then the panel was closed with Escape. One Codex conversation was active, another pinned conversation was complete. Captured using `top`, 2-second intervals; discard the first sample. Live agent traffic varies, so this is sequential observation, not a deterministic benchmark.

| Build | CPU mean | CPU range | Footprint during sample |
| --- | ---: | ---: | ---: |
| Previous implementation | 12.98% | 11.2–14.1% | 37–38 MB |
| Optimized implementation, initial check | 2.43% | 1.6–3.8% | 35–36 MB |

Final verification after the per-frame autorelease-pool change: 15 interval samples, mean CPU 2.47%, max 3.0%, footprint about 31 MB.

Initial comparison used 10 interval samples per build. CPU reduction in this comparison: about 81%. The previous long-running instance had a roughly 244 MB footprint, but restarting that same implementation returned it to about 38 MB. Do not attribute the entire long-running-versus-fresh difference to optimization. Multi-hour memory stability and battery discharge remain to be measured.

## Reproduce

```sh
pgrep -fl '/Mote.app/Contents/MacOS/Mote'
python3 Tools/measure-performance.py --pid PID --samples 16 --interval 2
```

Use the same panel state, number of active agents, power mode and workload. Also compare panel open, all tasks idle, and Low Power Mode separately. macOS CPU percentages are per-core scale, not battery percentages. The tool reads CPU/footprint only, not conversations or credentials.

Regression checks cover approval/question/resume, read receipts, grouped notifications, closing-panel content release, Retina template images, unchanged-job publisher suppression and usage cache append/truncate/replacement invalidation.
