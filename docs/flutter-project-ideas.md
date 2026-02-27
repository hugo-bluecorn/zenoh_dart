# Flutter Project Ideas: Real-World Zenoh Usage Patterns

This document proposes Flutter application projects that would naturally exercise
the zenoh communication patterns implemented across the `zenoh_dart` phases.
Each project idea maps to specific phases and patterns from
`docs/synthesis-phases-vs-patterns.md`.

These are **separate projects** from the per-phase demo apps described in
`docs/prompts/cf-flutter-examples.md`. Those demo apps mirror CLI examples
one-to-one. These projects are **composite applications** that combine multiple
zenoh patterns into realistic use cases.

---

## 1. Collaborative Whiteboard — "ZenBoard"

A multi-user drawing canvas where strokes appear in real-time across devices.

### Zenoh Patterns Used

| Pattern | Phase | Usage |
|---------|-------|-------|
| Declared Publisher | 3 | Each user publishes stroke events on `board/{boardId}/strokes/{userId}` |
| Callback Subscriber | 2 | All participants subscribe to `board/{boardId}/strokes/**` |
| Liveliness | 11 | Tokens on `board/{boardId}/presence/{userId}` — avatar dots light up/dim |
| Advanced Subscriber | 18 | Late joiner receives stroke history via recovery — no separate "load" API |
| Storage | 17 | A background "board server" stores all strokes as a queryable map |
| Query | 6 | "Export board" feature queries the storage for the full canvas state |
| Encoding | 16 | Strokes serialized as structured ZBytes (path points, color, width) |
| Scout | 5 | LAN mode: discover nearby boards without a cloud server |

### Why It's Interesting

This single app touches 8 phases. The advanced subscriber history recovery means
a user joining mid-session sees the full drawing without any custom sync logic —
zenoh handles it. The liveliness pattern provides real-time user presence
(colored dots for each participant) with zero custom heartbeat code.

### Key Expression Hierarchy

```
board/
  {boardId}/
    strokes/{userId}        # stroke events (pub/sub)
    presence/{userId}       # liveliness tokens
    state                   # storage queryable (full board state)
```

---

## 2. IoT Dashboard — "ZenHome"

A smart home control panel showing live sensor readings, device status, and
historical trends.

### Zenoh Patterns Used

| Pattern | Phase | Usage |
|---------|-------|-------|
| Pull Subscriber / Ring | 9 | Gauge widgets poll `home/sensors/{id}/temperature` at widget refresh rate — always shows latest value, discards stale readings |
| Callback Subscriber | 2 | Alert stream subscribes to `home/alerts/**` — every alert must be seen |
| Liveliness | 11 | Each device holds a token on `home/devices/{id}/alive` — dashboard shows green/red dots |
| Liveliness Get | 11 | On app launch, snapshot query to `home/devices/**` to populate initial device list |
| Declared Publisher | 3 | "Set thermostat" publishes commands on `home/commands/{deviceId}` |
| Channel Queryable | 8 | Device config endpoint: dashboard sends `get("home/config/{id}")`, device responds with current settings via FIFO queryable |
| Matching Listener | 3 | Publisher on `home/commands/{id}` checks matching status — warns "device unreachable" if no subscriber matched |
| Scout | 5 | "Add device" screen scouts the local network for new zenoh peers |

### Why It's Interesting

The pull subscriber (Phase 9) is the star here — a temperature gauge updating at
2Hz doesn't need every sample from a 100Hz sensor. The Ring channel's "latest
value" semantics are exactly right. Meanwhile, alerts use push (Phase 2)
because you can't miss a fire alarm. This contrast between pull and push
reception in the same app is a powerful teaching example.

### Key Expression Hierarchy

```
home/
  sensors/{id}/{metric}     # telemetry (pub/sub, pull)
  alerts/{severity}         # alerts (push subscriber)
  devices/{id}/alive        # liveliness tokens
  commands/{deviceId}       # control commands (publisher)
  config/{deviceId}         # device config (queryable)
```

---

## 3. Multiplayer Arcade Game — "ZenArena"

A 2D multiplayer game (top-down arena) with real-time position sync.

### Zenoh Patterns Used

| Pattern | Phase | Usage |
|---------|-------|-------|
| SHM Publisher | 4 | Player position/state updates at 60Hz — zero-copy for local peers |
| Pull Subscriber / Ring | 9 | Render loop polls latest opponent positions at frame rate |
| Ping/Pong | 12 | Latency indicator in the HUD — continuous RTT measurement |
| Liveliness | 11 | Player presence tokens — "Player 2 disconnected" overlay |
| Express Publisher | 12 | Power-up spawns published with `isExpress: true` — low latency, no congestion control |
| Priority | 14 | Game state on `Priority.realTime`, chat messages on `Priority.dataLow` |
| Congestion Control | 14 | Position updates use `CongestionControl.drop` (skip stale), chat uses `.block` (don't lose messages) |
| Advanced Publisher | 18 | Heartbeat detection — if a player's publisher stops heartbeating, trigger "idle timeout" |
| Direct Put | 1 | One-shot events: "Player scored", "Game over" |

### Why It's Interesting

This exercises the performance-sensitive patterns. SHM zero-copy (Phase 4) for
position data + Ring channel polling (Phase 9) for render-rate consumption +
priority/congestion tuning (Phase 14) is the trifecta for real-time interactive
apps. The ping/pong latency display (Phase 12) gives players network quality
feedback.

### Key Expression Hierarchy

```
arena/{gameId}/
  players/{id}/pos          # position updates (SHM pub, ring sub)
  players/{id}/alive        # liveliness tokens
  events/{type}             # game events (direct put)
  chat                      # in-game chat (low priority pub/sub)
  ping/{id}                 # latency measurement
```

---

## 4. Distributed Chat — "ZenChat"

A peer-to-peer messaging app that works on LAN without a server or over routers.

### Zenoh Patterns Used

| Pattern | Phase | Usage |
|---------|-------|-------|
| Declared Publisher | 3 | Each user publishes on `chat/{room}/messages/{userId}` |
| Callback Subscriber | 2 | Subscribe to `chat/{room}/messages/**` for real-time messages |
| Advanced Subscriber | 18 | Late joiner recovery — join a room, get the last N messages automatically |
| Miss Detection | 18 | "3 messages missed" indicator if connection was spotty |
| Storage | 17 | "Chat history" node stores messages in a queryable map |
| Query with Payload | 7 | Search: `get("chat/{room}/search", payload: "meeting notes")` — storage queryable filters and replies |
| Liveliness | 11 | Online/offline/typing indicators on `chat/{room}/presence/{userId}` |
| Liveliness Subscriber with History | 11 | On room join, get current online users AND subscribe to changes |
| Encoding | 16 | Messages as structured bytes: text + timestamp + optional attachment reference |
| Scout | 5 | "Nearby chats" — discover peers on the same LAN |

### Why It's Interesting

The advanced subscriber (Phase 18) eliminates the classic "chat history sync"
problem — zenoh's cache + history recovery means late joiners get caught up
transparently. The storage pattern (Phase 17) adds persistence. Miss detection
surfaces "you missed messages" UX that most chat apps hide. The combination of
liveliness (online status) and scout (LAN discovery) makes it work without any
cloud infrastructure.

### Key Expression Hierarchy

```
chat/
  {room}/
    messages/{userId}       # message stream (pub/sub, advanced)
    presence/{userId}       # liveliness tokens (online/typing)
    search                  # full-text search queryable
    history                 # storage queryable
```

---

## 5. Robotics Control Panel — "ZenBot"

A tablet app for monitoring and commanding a fleet of robots (drones, rovers, arms).

### Zenoh Patterns Used

| Pattern | Phase | Usage |
|---------|-------|-------|
| SHM Subscriber | 4 | Camera feed frames from robot to tablet (zero-copy on same host) |
| Pull Subscriber / Ring | 9 | UI renders camera at 30fps — ring channel discards stale frames |
| Callback Subscriber | 2 | Event stream: `robot/{id}/events/**` (warnings, state transitions) |
| Declared Publisher | 3 | Joystick commands: `robot/{id}/cmd_vel` at 20Hz |
| Channel Queryable | 8 | Robot exposes `robot/{id}/config` as FIFO queryable — tablet queries on demand |
| Non-blocking Get | 8 | "Refresh status" button does `tryRecv()` for quick check without blocking UI |
| Liveliness | 11 | Robot fleet status grid — green/yellow/red per robot |
| Ping/Pong | 12 | Per-robot latency indicator — critical for remote operation |
| Throughput | 14 | Diagnostics screen shows data rates per topic |
| Query | 6 | "Show flight log" queries `robot/{id}/logs` — queryable replies with historical data |
| Matching Listener | 3 | Command publisher warns "no robot listening" if match drops |
| Session Info | 5 | Settings screen shows ZID, connected routers, peer count |

### Why It's Interesting

This is the "kitchen sink" project — it exercises nearly every phase (12 out of
18). The combination of SHM for camera frames (Phase 4) + Ring channel for
frame-rate rendering (Phase 9) + ping for latency monitoring (Phase 12)
represents a genuinely challenging real-time system. The queryable pattern
(Phase 8) for on-demand config reads is a natural fit for robots that expose
parameters. The matching listener on the command publisher provides immediate
"connection lost" feedback that's critical for safe robot operation.

### Key Expression Hierarchy

```
robot/
  {id}/
    camera/{stream}         # video frames (SHM pub, ring sub)
    telemetry/{sensor}      # sensor data (pub/sub)
    events/{type}           # state events (push subscriber)
    cmd_vel                 # velocity commands (publisher)
    config                  # configuration queryable
    logs                    # historical log queryable
    alive                   # liveliness token
    ping                    # latency measurement
```

---

## 6. Live Sports Scoreboard — "ZenScore"

A broadcast-style app where a scorekeeper publishes updates and many viewers
subscribe.

### Zenoh Patterns Used

| Pattern | Phase | Usage |
|---------|-------|-------|
| Declared Publisher | 3 | Scorekeeper publishes on `match/{id}/score`, `match/{id}/events` |
| Callback Subscriber | 2 | Viewer app subscribes to `match/{id}/**` |
| Advanced Subscriber | 18 | Viewer joining mid-match gets full score history via cache recovery |
| Advanced Publisher | 18 | Scorekeeper enables cache + heartbeat — viewers detect if feed dies |
| Miss Detection | 18 | "Updates may be delayed" banner if samples missed |
| Liveliness | 11 | Scorekeeper presence token — viewers see "LIVE" / "OFFLINE" badge |
| Query | 6 | "Match summary" queries `match/{id}/summary` — queryable aggregates events |
| Pull Subscriber | 9 | Ticker widget polls latest score at 1Hz even though updates arrive irregularly |
| Priority | 14 | Score changes at `realTime`, commentary at `data` |
| Encoding | 16 | Rich event objects: goal, foul, substitution — each with structured fields |

### Why It's Interesting

The advanced pub/sub (Phase 18) is the hero pattern. Late-joining viewers
getting automatic history recovery, heartbeat-based "is the feed alive?"
detection, and miss recovery for spotty mobile connections solve real broadcast
problems without custom infrastructure. The app has a clean one-to-many
topology that demonstrates zenoh's efficiency for fan-out scenarios.

### Key Expression Hierarchy

```
match/
  {id}/
    score                   # current score (pub/sub, advanced)
    events/{type}           # game events (pub/sub)
    commentary              # text commentary (low priority)
    summary                 # aggregated queryable
    live                    # scorekeeper liveliness token
```

---

## 7. Environmental Monitoring Network — "ZenSense"

A field-deployed sensor mesh with a Flutter dashboard for scientists.

### Zenoh Patterns Used

| Pattern | Phase | Usage |
|---------|-------|-------|
| Callback Subscriber | 2 | Live data stream from `sensors/{stationId}/{metric}` |
| Storage | 17 | Each station runs a storage node — queryable map of all recent readings |
| Query | 6 | "Show last 24h for station-7 temperature" — query the storage |
| Liveliness | 11 | Station health map — tokens on `stations/{id}/alive` |
| Liveliness Get | 11 | Dashboard startup: snapshot all currently alive stations |
| Declared Querier | 10 | Periodic data quality check: querier polls `sensors/**/quality` every 5 minutes |
| Querier Matching | 10 | Alert if expected stations stop responding to quality queries |
| Delete | 1 | Station decommissioned: `delete("sensors/{stationId}")` propagates removal |
| Background Subscriber | 12 | Data logger runs fire-and-forget subscriber — no handle management needed |
| Key Expression Utilities | 17 | `intersects("sensors/station-7/**", "sensors/**/temperature")` for topic routing logic |

### Why It's Interesting

The storage pattern (Phase 17) is central — it's the natural "time-series
database" in a zenoh network. The declared querier (Phase 10) with matching
listener provides proactive monitoring ("station stopped responding") that's
hard to build with pure pub/sub. The key expression utilities (Phase 17) enable
sophisticated topic filtering in the dashboard UI.

### Key Expression Hierarchy

```
sensors/
  {stationId}/
    {metric}                # live readings (pub/sub)
    quality                 # quality queryable
stations/
  {id}/
    alive                   # liveliness tokens
    config                  # station config queryable
```

---

## Pattern Coverage Matrix

Each cell marks which project exercises which phase:

| Phase | ZenBoard | ZenHome | ZenArena | ZenChat | ZenBot | ZenScore | ZenSense |
|-------|:--------:|:-------:|:--------:|:-------:|:------:|:--------:|:--------:|
| 1 Put/Delete | | | X | | | | X |
| 2 Subscriber | X | X | | X | X | X | X |
| 3 Publisher | X | X | | X | X | X | |
| 4 SHM | | | X | | X | | |
| 5 Scout/Info | X | X | | X | | | |
| 6 Query | X | | | | X | X | X |
| 7 SHM Query | | | | X | | | |
| 8 Channels | | X | | | X | | |
| 9 Pull/Ring | | X | X | | X | X | |
| 10 Querier | | | | | | | X |
| 11 Liveliness | X | X | X | X | X | X | X |
| 12 Ping/Pong | | | X | | X | | X |
| 14 Throughput | | | X | | X | | |
| 16 Encoding | X | | | X | | X | |
| 17 Storage | X | | | X | | | X |
| 18 Advanced | X | | X | X | | X | |
| **Total phases** | **8** | **6** | **7** | **8** | **11** | **7** | **7** |

Every phase has at least one natural home. **ZenBot** covers the most phases
(11), making it the best "showcase" app. **ZenChat** and **ZenBoard** are the
most approachable for demonstrating zenoh to newcomers.

---

## Recommended Build Order

If building these incrementally as `zenoh_dart` phases land:

1. **ZenChat** (after Phase 2-3) — start with basic pub/sub messaging, add
   features as phases land. Most relatable use case for demos.
2. **ZenHome** (after Phase 9) — requires pull subscriber for "latest value"
   gauges. Good showcase for mixed push/pull reception.
3. **ZenBoard** (after Phase 11) — liveliness for presence makes the
   whiteboard collaborative. Advanced sub (Phase 18) completes the experience.
4. **ZenScore** (after Phase 18) — needs advanced pub/sub for the core
   experience. Good final demo.
5. **ZenBot** (after Phase 14) — the most complex project, benefits from
   having all phases available.
6. **ZenArena** (after Phase 14) — game-specific; fun but niche.
7. **ZenSense** (after Phase 17) — science/monitoring niche; good for
   storage pattern showcase.

---

## Relationship to Other Docs

| Document | Purpose |
|----------|---------|
| `docs/synthesis-phases-vs-patterns.md` | Maps phases to zenoh patterns — the analytical foundation for this document |
| `docs/phases/phase-NN-*.md` | Per-phase specifications — defines the API surface each project idea draws from |
| `docs/prompts/cf-flutter-examples.md` | Per-phase demo apps (one screen, one pattern) — complementary to these composite projects |
| `docs/prompts/cg-flutter-projects.md` | Continuation prompt for expanding these ideas (see below) |
