---
type: "query"
date: "2026-11-02T15:35:35.295907+00:00"
question: "Review main playback flows, state consistency and playback modes"
contributor: "graphify"
outcome: "useful"
source_nodes: ["PlaybackUseCases", "AudioNotifier", "AudioPlayerService"]
---

# Q: Review main playback flows, state consistency and playback modes

## Answer

Expanded graph vocabulary: playback audio player mode shuffle repeat queue current song pause next discontinuity. Graph located PlaybackUseCases, AudioNotifier and AudioPlayerService; direct source verification found 9 defects documented in graphify-out/PLAYBACK_AUDIT.md. Seven standalone characterization probes reproduced queue identity/position loss, premature end pause, stale completion pausing a new song, overlapping metadata writes, swallowed play failure, and search index mismatch. Additional static findings: LoopMode.one causes manual next/previous to replay same item in just_audio 0.9.46; active queue diverges from filtered UI after scan/mutations; null current-song emission does not clear AudioState. Not native-device verified. Semantic graph alone does not encode these dynamic defects.

## Outcome

- Signal: useful

## Source Nodes

- PlaybackUseCases
- AudioNotifier
- AudioPlayerService