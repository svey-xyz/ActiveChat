# Plan: Context-Aware Chatter for ActiveChat

## Implementation status

- **Phase 1 — DONE (2026-05-30).** `ctx` + refresh, time only. Shipped in
  `ActiveChat/npcTalk.lua`. No scorer change, no `npc_text.lua` change (as scoped).
- **Phase 2 — DONE (2026-05-30).** `timeFactor` in the scorer + `times` tag.
  Shipped in `ActiveChat/npcTalk.lua` and `ActiveChat/talk_text/npc_text.lua`.
- **Phase 3 — DONE (2026-05-30).** Active events: `GetActiveGameEvents()` sourcing,
  the new `ActiveChat/context_map.lua` data file, `eventFactor` in the scorer, the
  `events` tag, and active-only `%event%`. Shipped in `ActiveChat/npcTalk.lua`,
  `ActiveChat/context_map.lua` (new), and `ActiveChat/talk_text/npc_text.lua`.
- **Phase 5 — DONE (2026-05-30).** Seasons: `M.monthToSeason` map + holiday→season
  cross-check, `monthToSeason()`/`seasonFactor()`, `normalizeSeasons`, the `seasons`
  tag, `%season%` context binding, and 6 harvest/weather/season lines tagged. Shipped
  in `ActiveChat/npcTalk.lua`, `ActiveChat/context_map.lua`, and
  `ActiveChat/talk_text/npc_text.lua`.
- **Phase 6 — DONE (2026-05-30), event-burst part; dispatcher-wiring DEFERRED.**
  Optional event-activation burst behind `enableEventBurst` (default `false`).
  Shipped in `ActiveChat/npcTalk.lua`, `ActiveChat/context_map.lua`, and a one-line
  cross-reference in `docs/plans/PLAYER_INTERACTION_PLAN.md`.
- **Phase 4 — DONE (2026-05-30).** Nearest events: startup `game_event` schedule
  snapshot, `nearestEvents()`, `ctx.nextEvent`/`ctx.lastEvent`, the `eventWindow`
  tag (`approach`/`after`) extending `eventFactor`, `%nextevent%`/`%lastevent%`
  tokens, the neutral phrase pool, and the nearest-event `%event%` fallback
  (replacing the random one). Shipped in `ActiveChat/npcTalk.lua`,
  `ActiveChat/context_map.lua`, and `ActiveChat/talk_text/npc_text.lua`.
- **Phase 7 — DONE (2026-05-30), documentation.** README only — no engine/content
  change. Added a new **"Context-aware chatter"** section (overview + "The three new
  line tags" table & examples + "The context tokens" + "How context is sourced (and
  what happens if it can't be)" fallback table + "Optional event-activation burst").
  Extended the **tagged-authoring** tag table with `times`/`events`/`eventWindow`/
  `seasons` rows. Updated **"How a line is chosen"**: scorer formula now lists
  `timeFactor`/`eventFactor`/`seasonFactor` with the mirror-`areaFactor` / binary-event
  / fallback-invariant explanation. Updated the **placeholder token table**:
  `%timeofday%`/`%season%`/`%event%` marked context-aware, **added** `%nextevent%`/
  `%lastevent%`, plus an in-character note (fiction words only — never a real clock,
  server time, or printed date). Added a **"Context-aware chatter flags"** sub-table to
  the config reference (`enableContextAware`, `enableTimeContext`, `enableEventContext`,
  `enableSeasonContext`, `timeMatchStrength` 3.0, `seasonMatchStrength` 3.0,
  `contextRefreshMs` 60000, `eventApproachDays` 5, `eventAfterDays` 3,
  `enableEventBurst` false). Documented `context_map.lua` (`eventIdToName`,
  `monthToSeason`, `eventNeutral`, `eventBurst`). Cross-referenced
  PLAYER_INTERACTION_PLAN.md (its Phase-6 `ctx` cross-reference verified present).
  All flag names/defaults, tag names, bucket/season names, and token names verified
  against `npcTalk.lua` and `context_map.lua`. **No doc-vs-code discrepancies in the
  context feature.** (Pre-existing, out-of-scope: the README title/intro still say
  "Eluna" whereas the engine is ALE / `mod-ale` per this plan — left untouched.)
  **With Phase 7 the whole phased plan (1–7) is complete; only Phase 6's
  reaction-dispatcher wiring stays deferred until that dispatcher exists.**

What was added for Phase 5 (line ranges approximate, post-edit):

- **`M.monthToSeason`** in `context_map.lua` — month (1..12) → `"winter"|"spring"|
  "summer"|"autumn"`, northern-hemisphere conventional default (12,1,2=winter;
  3,4,5=spring; 6,7,8=summer; 9,10,11=autumn). Commented as OVERRIDABLE for themed
  realms (perpetual-winter Northrend / southern-hemisphere). Replaces the old
  PLACEHOLDER block (which also reserved `M.timeKeyDisplay`; that pool is still inline
  in the engine — its placeholder note was kept, only the `monthToSeason` line
  promoted).
- **`monthToSeason(month)`** helper in the engine (right before `timeKeyDisplay`).
  Reads `ctxMap.monthToSeason` into module-level `monthToSeasonMap` with an inline NH
  fallback if the data file is older/missing; the helper is nil-safe (non-number /
  unmapped month ⇒ nil ⇒ `ctx.season` stays neutral).
- **`holidayToSeason`** cross-check map (right after `monthToSeason`) — decision 4.
  Maps the EXACT `eventIdToName` display names of the season-unambiguous holidays to a
  season: Winter Veil⇒winter, the Midsummer Fire Festival⇒summer, the Harvest
  Festival/Pilgrim's Bounty⇒autumn, Noblegarden/the Lunar Festival⇒spring. Darkmoon /
  fishing derbies / other season-neutral events are intentionally omitted.
- **`refreshCtx()` season block.** The `os.date("*t", GetGameTime())` decomposition was
  hoisted to a single `local t` shared by time AND season (guarded by
  `enableTimeContext OR enableSeasonContext`). **The Phase-3/4 active-events block was
  moved ABOVE the new season block** so the cross-check reads the fresh `ctx.active`.
  Season block (guarded by `enableSeasonContext`): `ctx.season = monthToSeason(t.month)`
  then iterate `ctx.active` and let any `holidayToSeason[name]` override. Clock absent /
  unmapped month ⇒ `ctx.season` left at its prior/neutral value (factor falls back to
  1.0, `%season%` random).
- **`normalizeSeasons(seasons)`** — verbatim shape of `normalizeTimes` (added right
  before `normalizeEvents`): omitted ⇒ `(true,{})` global; list ⇒ uniform weight 1;
  graded map ⇒ weights copied as-is. `makeItem` stores `seasonsGlobal`/`seasons` in
  BOTH branches (bare-string ⇒ global, table ⇒ `normalizeSeasons(entry.seasons)`).
- **`seasonFactor(item, c)`** — verbatim copy of `timeFactor` (right after `timeFactor`)
  using `seasonMatchStrength` against `ctx.season`: `seasonsGlobal` ⇒ 1.0; flags off /
  neutral season ⇒ 1.0; on-season ⇒ `weight * seasonMatchStrength`; tagged-but-off-season
  ⇒ 0 (HARD EXCLUDE). Multiplied into `scoreLine` after `timeFactor` with an
  `if (sf <= 0) then return 0 end` guard; formula now
  `base × rf × mf × af × tf × sf × ef × rp`.
- **`%season%` context-aware.** `resolveSeason(c)` (right after `resolveTimeOfDay`)
  returns `c.season` when master+season flags on and `c.season` set, else
  `selectRandomSeason()` (today's behaviour). Wired into `renderTokens` replacing the
  direct `selectRandomSeason()` call.
- **`npc_text.lua` tagged lines (6).** All four seasons exercised, both authoring forms
  not needed (all list form, matching the parallel `times` precedent):
  autumn — "Mill's grinding day and night with the harvest in…" (L474), "Whole village
  turns out for the harvest…" (L477), "Harvest's in early this year. The Elwynn fields
  came good and the granary's nearly full…" (L971); winter — "First snow in Dun Morogh…
  Best %season% under the mountain." (L897); summer — "Summer heat in Orgrimmar is no
  joke…" (L1284); spring — "New lambs this morning, three of them…" (L473). Lines whose
  `%season%` token referred to a *different* season than the line's own setting were
  deliberately left untagged (or only winter line tagged, where %season%⇒winter agrees).
  Generic ambience left untagged.

Decisions / deviations (Phase 5):

- **No deviation from the `times` precedent.** `normalizeSeasons` is a structural copy
  of `normalizeTimes`; `seasonFactor` mirrors `timeFactor` (same flag/neutral guards).
- **Block reordering in `refreshCtx`.** The active-events block now precedes the season
  block (was: time → events). Required so the holiday cross-check sees the live event
  set; behaviour for time/events is otherwise unchanged. The `os.date` call is now
  shared (one decomposition instead of two), guarded by either sub-flag.
- **`timeKeyDisplay` left inline.** The optional relocation to `context_map.lua` was not
  performed (out of Phase-5 scope and zero functional benefit); its placeholder note is
  retained in the data file.
- **Fallback invariant verified:** untagged ⇒ 1.0; neutral/disabled season ⇒ 1.0;
  `GetGameTime`/`os.date` absent ⇒ `ctx.season` neutral, `%season%` random; never errors.

Verification (Phase 5): all three touched files compiled clean via LuaJIT (`lupa`).
`npcTalk.lua` ran top-to-bottom under ALE stubs across 6 month/active-event scenarios
(no error). A 27-assertion verbatim harness over
`monthToSeason`/`normalizeSeasons`/`seasonFactor`/`resolveSeason`/cross-check passed:
`monthToSeason(12)=="winter"`, `(7)=="summer"`, `(nil)/(13)==nil`, all four seasons sane;
`seasonFactor` tagged off-season ⇒ 0, on-season ⇒ 3.0 (boosted), graded autumn ⇒ 9.0,
untagged ⇒ 1.0, neutral ctx ⇒ 1.0, `enableSeasonContext` off ⇒ tagged off-season ⇒ 1.0;
`resolveSeason` ⇒ `ctx.season` when enabled, random when disabled/no-ctx; cross-check
summer-month + Winter Veil ⇒ winter, winter-month + Midsummer ⇒ summer, Harvest
Festival ⇒ autumn, Noblegarden ⇒ spring, season-neutral Darkmoon ⇒ month. A full-load
integration probe confirmed `ctx.season` populates end-to-end including all holiday
overrides (e.g. month=7 + Winter Veil active ⇒ `ctx.season=="winter"`).

What was added for Phase 6 (line ranges approximate, post-edit):

- **Transition detection in `refreshCtx()`.** Two module-level locals were added
  next to `ctx`: `ctxActivePrev` (snapshot of the previous refresh's active-event
  name set) and `ctxActiveSeeded` (false until the first refresh records the
  snapshot). Inside the `enableEventContext` block, immediately after
  `ctx.active = activeEventNameSet()`, a new `if (enableEventBurst and fireEventBurst)`
  block diffs the fresh `ctx.active` against `ctxActivePrev`: any name present now but
  absent before is a transition INTO active and calls `fireEventBurst(name)`. The
  snapshot is stored AFTER diffing. The **first** refresh only seeds the snapshot
  (`ctxActiveSeeded` guard) so holidays already live at startup don't all burst at
  once. The previous-set diff gives **once-per-activation** for free — a still-active
  event is in both sets and never re-fires.
- **`fireEventBurst(eventName)`** — forward-declared as a `local` near `ctx`
  (so `refreshCtx`, defined just below, can call it) and **assigned after the
  conversation machinery** (right after `nextLine`), where `t.conv`/`assembleCast`/
  `makeItem`/`resolveSpeaker`/`globalTick` are all in lexical scope. It **reuses the
  existing duo/chain machinery** rather than building a new renderer: it builds a
  two-line duo item via `makeItem("duo", {chain=…, events={eventName}}, true)` (tagged
  with the activated event so `%event%` resolves to it — token & tag agree), assembles
  a same-faction cast around a resolved Alliance speaker (`resolveSpeaker("alliance")`
  + `assembleCast`), and **seeds it into `t.conv["alliance"]`** as
  `{item=…, cast=…, ti=1, audience="shared", …}` so the very next `speak("alliance",…)`
  tick continues it line-by-line through `nextLine`'s existing "continue chain" branch.
  Voiced everyone-visible (`audience="shared"`, Alliance-voiced, matching decision 5).
  Fully guarded: flag off, non-string event, empty pool, no resolvable speaker, or a
  **chain already in progress on the channel** ⇒ it no-ops (never errors, never
  clobbers an ongoing conversation).
- **`M.eventBurst` pool in `context_map.lua`** — 5 festival-agnostic two-line duo
  chains, each using `%event%` so they resolve to the just-activated holiday's name
  (e.g. `{"Word is %event% has begun -- did you hear?", "Aye, just now. Best get to the
  city before the crowds."}`). `npcTalk.lua` reads it into `eventBurstPool` with a
  2-chain inline fallback if the data file is older/missing. **Content choice:** a
  dedicated small pool was added (per scope option 2) because the burst is a true
  character↔character exchange with its own "the festival has begun" framing — reusing
  the existing event-tagged ambient lines wouldn't read as an activation moment.

Decisions / deviations (Phase 6):

- **Dispatcher-wiring deferred (not a deviation — per the Phase-5 handoff).** No
  reaction dispatcher (`dispatch`/`advanceThread`/`npc_reactions.lua`) exists yet, so
  the "wire shared `ctx` into the reaction dispatcher" sub-item has nothing to wire
  into. The shared-`ctx` design already supports it (module-level, read at the top of
  `speak()`); PLAYER_INTERACTION_PLAN.md now carries a one-line cross-reference.
- **Burst reuses the conv machinery (preferred path taken).** Rather than the minimal
  "enqueue via the emit path" fallback the scope allowed, the burst seeds a real duo
  chain into `t.conv`, so it renders as a genuine two-voice exchange with distinct
  same-faction speakers — identical in shape to an ambient duo.
- **Channel-idle guard ⇒ at most one burst per refresh.** To avoid truncating an
  in-progress conversation, `fireEventBurst` skips seeding when the channel already has
  a chain mid-flight. Consequence: if **two** events activate in the **same** refresh,
  only the first seeds a burst that refresh (the second is dropped, not queued). The
  critical invariant — **once-per-activation, no re-fire while still active** — holds
  in all cases. A still-active event never re-bursts on later refreshes.
- **Everyone-visible, Alliance-voiced.** A festival affects the whole world, so the
  burst is `audience="shared"` (broadcast to all) on the "alliance" channel, matching
  how shared lines are normally voiced. No Horde-channel duplicate is seeded (that
  would double-voice the same festival announcement).
- **Default-off invariant verified:** with `enableEventBurst=false` (the default) the
  entire transition-detection block is skipped (`ctxActivePrev`/`ctxActiveSeeded` are
  never touched) and `fireEventBurst` is never called — zero behavioural change, the
  burst path is dead code.

Verification (Phase 6): all touched files (`npcTalk.lua`, `context_map.lua`,
`npc_text.lua`) compiled clean via LuaJIT (`lupa`). A full-load integration harness
(ALE stubs: `GetActiveGameEvents` controllable, `GetGameTime`, `CreateLuaEvent`
capturing the timer closures, `SendWorldMessage` capturing output, a `require` shim,
`contextRefreshMs=0` so every tick refreshes) drove `refreshCtx` through every
scenario with the alliance-driver timer: **flag ON** — startup `active={}` ⇒ no burst;
transition `{}→{Brewfest}` ⇒ a 2-line burst fires and names "Brewfest" via `%event%`;
`{Brewfest}` still active over 8 more ticks ⇒ **no** second burst; startup with
`{Brewfest}` **already** active ⇒ no burst (seed-only). **Flag OFF** — transition into
active over many ticks ⇒ never fires. **API absent** (`GetActiveGameEvents`/
`WorldDBQuery` nil) with flag ON ⇒ never errors, never fires. **Multi-event**
`{}→{Brewfest, Hallow's End}` in one refresh ⇒ exactly one festival burst (idle-guard),
and no re-fire while both stay active.

What was added for Phase 4 (line ranges approximate, post-edit):

- **Schedule snapshot read.** `readEventSchedule()` (added after `activeEventNameSet`,
  before `refreshCtx`) capability-guards `WorldDBQuery` once and runs
  `SELECT eventEntry, UNIX_TIMESTAMP(start_time), length, occurence FROM game_event`.
  **`start_time` is a SQL `timestamp`** — selected through `UNIX_TIMESTAMP()` so ALE
  returns clean integer seconds (a raw datetime string would mis-coerce under
  `GetUInt32`). **`length`/`occurence` are MINUTES** → converted to seconds
  (`*60`) at read time. ALE result iteration uses the documented `ALEQuery` API:
  `q:GetRowCount()` bounds the loop (guarded — falls back to `NextRow()`-walking on
  engines lacking it), `q:GetUInt32(col)` reads columns **0-indexed**, `q:NextRow()`
  advances. The whole read is wrapped in `pcall` so an unexpected result shape leaves
  the snapshot empty rather than erroring module load. Only IDs present in
  `ctxMap.eventIdToName` are stored. Result cached in module-level `eventSchedule`
  (array of `{id,name,startSec,lengthSec,occurSec}`); empty ⇒ `nearestEvents` returns
  `nil,nil`.
- **`nearestEvents(now)`** (after `readEventSchedule`). `now` = game seconds
  (`GetGameTime()`). For each scheduled holiday: non-recurring (`occurSec==0`)
  contributes its single window; **recurring** (`occurSec>0`) projects the cycle
  around `now` — `k = floor((now-startSec)/occurSec)` gives the current/just-past
  cycle start (`prevS`) and the next cycle start (`nextS = prevS + occurSec`), which
  is exactly the **year-wrap** case (next start is next cycle). Keeps the soonest
  future start as `nextEvent` and the most recent past **end** (`prevS+lengthSec`) as
  `lastEvent`. **Horizon constant `NEAREST_HORIZON_DAYS = 30`** (≈ under a holiday
  cycle): any slot whose offset exceeds the horizon is left `nil` so `%event%` uses the
  neutral pool instead of surfacing a far-off holiday as "soon". `DAY_SECONDS = 86400`.
  Day-offsets are `math.floor(seconds/DAY_SECONDS)`.
- **`refreshCtx()`** now populates `ctx.nextEvent`/`ctx.lastEvent` via
  `nearestEvents(nowSec)` inside the `enableEventContext` block (nil-safe: `nowSec`
  from `GetGameTime` guarded, else `os.time()`; empty schedule ⇒ both nil).
- **`eventWindow` tag.** `normalizeEventWindow(w)` (after `normalizeEvents`) coerces to
  `"active"` (default) / `"approach"` / `"after"`; any unrecognised value falls back to
  `"active"` so a typo can't widen eligibility. Stored on the item in BOTH `makeItem`
  branches. `eventFactor(item, c)` extended: still binary; `"active"` = Phase-3
  live-only; `"approach"` ALSO 1.0 when a tagged event `== c.nextEvent.name` AND
  `c.nextEvent.daysAway <= eventApproachDays`; `"after"` symmetric on
  `c.lastEvent`/`eventAfterDays`. The never-exclude-when-API-absent guard is
  preserved and sharpened: if **neither** the active set **nor** the window's relevant
  nearest-event slot is known (`liveKnown` and `nearKnown` both false) ⇒ 1.0; once the
  schedule IS known, an out-of-window tagged line excludes (0).
- **`%nextevent%`/`%lastevent%`.** `resolveNextEvent(c)`/`resolveLastEvent(c)` (after
  `resolveEvent`) return `c.nextEvent.name`/`c.lastEvent.name`, falling back to the
  neutral pool when scheduling is unknown/disabled. Wired into `renderTokens` right
  after the `%event%` gsub.
- **`%event%` fallback replaced.** `resolveEvent` step (3) is now
  `c.nextEvent.name` → `c.lastEvent.name`; step (4) is the neutral pool. The old
  `selectRandomEvent()` is gone from this path — a character never names a random
  specific holiday. Full priority: tag event → `ctx.active` → nextEvent → lastEvent →
  neutral.
- **Neutral phrase pool location:** added as **`M.eventNeutral`** in
  `context_map.lua` (festival-agnostic phrases, articles baked in). `npcTalk.lua`
  reads it into `eventNeutralPool` with a 3-phrase inline fallback if the data file is
  older/missing; `selectNeutralEvent()` draws from it.
- **`npc_text.lua` lines authored (4).** In the "Festivals & holidays" block, after the
  active-only holiday lines: a Winter Veil anticipation line and a Hallow's End
  anticipation line (`eventWindow="approach"`, `%nextevent%`), and a Brewfest aftermath
  line and a Day of the Dead aftermath line (`eventWindow="after"`, `%lastevent%`).
  Display names match `eventIdToName` exactly.

Decisions / deviations (Phase 4):

- **`start_time` read via `UNIX_TIMESTAMP()`** rather than column-casting the
  `timestamp` string — the only robust way to get integer seconds out of ALE for a
  DATETIME column. Noted as a deviation from the plan's literal
  `SELECT … start_time …` (semantically identical, value is seconds either way).
- **`eventFactor` "can't tell" guard refined per-window.** Phase 3 used "empty
  `ctx.active` ⇒ 1.0". Phase 4 generalises: a line excludes only when the signal its
  window depends on IS known. So an `approach` line with `ctx.nextEvent` known but
  non-matching DOES exclude (correct), while one with no schedule at all does not.
- **Horizon = 30 days** (constant `NEAREST_HORIZON_DAYS`), comfortably inside a
  yearly holiday cycle; tune freely.
- **Fallback invariant verified:** `WorldDBQuery` absent / returns nil / raises /
  lacks `GetRowCount` ⇒ empty snapshot, `nearestEvents` nil/nil, `%event%` neutral,
  no errors, no random holiday.

Verification (Phase 4): all three touched files compiled clean via LuaJIT (`lupa`);
`npcTalk.lua` ran top-to-bottom under ALE stubs WITH a fixture `WorldDBQuery`, and also
cleanly with `WorldDBQuery` absent / returning nil / raising / lacking `GetRowCount`.
A 22-assertion harness over verbatim
`normalizeEvents`/`normalizeEventWindow`/`nearestEvents`/`eventFactor`/`resolveEvent`/
`resolveNextEvent`/`resolveLastEvent` passed: `nearestEvents` returns the correct
upcoming/recently-ended pair INCLUDING the **year-wrap** case (next start = next
cycle, daysAway=5) and the **horizon cap** (Brewfest ended >30d ago ⇒ `lastEvent` nil;
empty schedule ⇒ nil,nil); `eventFactor` scores `approach`/`after` >0 ONLY when the
event is `ctx.nextEvent`/`lastEvent` within `eventApproachDays`/`eventAfterDays` (0
otherwise, 0 when it's a different near event, 1.0 when live), default `"active"`
unchanged from Phase 3, untagged 1.0, and the no-signal guard 1.0; `%event%` with
nothing active + known schedule resolves to the nearest event name and with no schedule
to the neutral phrase (never random), tag still wins.

What was added for Phase 3 (line ranges approximate, post-edit):

- **`ActiveChat/context_map.lua` (NEW).** Plain-Lua data file, same philosophy as
  `npc_name.lua`. Returns a table `M` with one Phase-3 field, **`M.eventIdToName`**:
  an `eventEntry → display-name` map keyed to **AzerothCore 3.3.5
  `game_event.eventEntry` IDs** (verified against `data/sql/base/db_world/
  game_event.sql`), mapping to the EXACT display names already in the engine's
  `events` table. Holiday IDs included: `1`=the Midsummer Fire Festival, `2`=Winter
  Veil, `3/4/5/23/71/77`=the Darkmoon Faire (per-zone + building variants all fold to
  one name), `7`=the Lunar Festival, `8`=Love is in the Air, `9`=Noblegarden,
  `10`=Children's Week, `11`=the Harvest Festival, `12`=Hallow's End, `13`=the
  Elemental Invasion, `15`=the Stranglethorn Fishing Extravaganza, `17`=the Scourge
  Invasion, `24/70/91`=Brewfest (+ building events), `26`=Pilgrim's Bounty,
  `50`=Pirates' Day, `51`=the Day of the Dead, `64`=the Kalu'ak Fishing Derby.
  PvP "Call to Arms", AQ war-effort, arena seasons, Brew-of-the-Month and other
  internal events are intentionally omitted (no ambient-chatter display name). A
  commented PLACEHOLDER block reserves `M.monthToSeason` and `M.timeKeyDisplay` for
  Phase 5.
- **Loading.** `local ctxMap = require("context_map")` wrapped in a `pcall`/`type`
  guard, placed right after `selectRandomWeather` and BEFORE the `ctx` block
  (~line 458) so `refreshCtx` can reach it as an upvalue. Same require mechanism ALE
  uses for `npc_text`/`npc_name`. A missing/broken file leaves `ctxMap = {}` and the
  engine falls back to today's random behaviour.
- **`activeEventNameSet()`** — added right after `nowMs()` (~line 531).
  Capability-guarded once (`type(GetActiveGameEvents)=="function"` + `pcall`): maps
  each active game_event ID through `ctxMap.eventIdToName`, returns a set-like
  `{[name]=true}`; unmapped IDs skipped. Returns `{}` if the API is absent/unavailable.
- **`refreshCtx()`** — now populates `ctx.active = activeEventNameSet()` guarded by
  `enableEventContext` (after the time block, before the Phase-4 TODO).
- **`normalizeEvents(events)`** — added immediately after `normalizeTimes`
  (~line 651). Same list/map plumbing, but BINARY: omitted ⇒ `(true, {})` global;
  list `{"Hallow's End"}` ⇒ `(false, {"Hallow's End"})`; map form's keys are taken as
  names (weights ignored). Returns the names as a plain ARRAY (used for membership +
  `%event%` resolution). `makeItem` stores `eventsGlobal`/`events` in BOTH the
  bare-string branch (untagged ⇒ `eventsGlobal=true, events={}`) and the table branch.
- **`eventFactor(item, c)`** — added right after `timeFactor` (~line 1160). BINARY:
  `eventsGlobal ⇒ 1.0`; flags off ⇒ `1.0`; `ctx.active` empty (API absent) ⇒ `1.0`
  (never exclude when we can't tell); one of the line's tagged events in `ctx.active`
  ⇒ `1.0` (applies); none active ⇒ `0` (HARD EXCLUDE). Multiplied into `scoreLine`
  after `timeFactor` with an `if (ef <= 0) then return 0 end` exclude guard; formula
  now `base × rf × mf × af × tf × ef × rp`.
- **`%event%` active-only in `renderTokens`** via a new **`resolveEvent(item, c)`**
  (added after `resolveTimeOfDay`). Priority: (1) tagged line ⇒ the tagged event
  (preferring one in `ctx.active`, else the first tagged name — token & tag agree);
  (2) else an entry from `ctx.active`; (3) else `selectRandomEvent()`. **`renderTokens`
  signature is now `(txt, speaker, ctx, item)`** (trailing `item` optional,
  back-compat). The line item is threaded through: `nextLine` now returns the item as
  a 4th value (all three return points), `speak` captures it and passes it to
  `renderTokens`. **Phase 4 hook:** step (3)'s `selectRandomEvent()` fallback is the
  single line to replace with the nearest-event reference (see resolveEvent's NOTE
  comment).
- **`npc_text.lua` tagged lines (14).** The 11 specific-holiday bare strings in the
  shared "Festivals & holidays" block (L297–307) converted to tagged table entries
  with `events={"<Name>"}` (Brewfest, the Darkmoon Faire, Hallow's End, Winter Veil,
  the Lunar Festival, Pilgrim's Bounty, Love is in the Air, Children's Week, the
  Midsummer Fire Festival, Noblegarden, the Day of the Dead). Plus 3 more that name a
  specific holiday: the Brewfest reunion one-liner (~L838) and duo (~L1045) tagged
  `events={"Brewfest"}`, and the harvest-festival duo (~L734) tagged
  `events={"the Harvest Festival"}`. Lines with a GENERIC `%event%` token (festival-
  agnostic flavor) were left untagged so `%event%` resolves to whatever is live (or
  random). All display names match `context_map.lua` exactly.

Decisions / deviations (Phase 3):

- **`events` stored as an ARRAY, not a map** (unlike `times`/`areas` which are maps).
  `events` is binary with no weights, and `resolveEvent` needs to iterate the names in
  author order to pick the active one / the first — an array is the natural shape. The
  list/map authoring forms are both accepted by `normalizeEvents` (map keys become the
  names) for parity with the other tags.
- **`item` threaded into `renderTokens`** so the `%event%` token can honour the line's
  own `events` tag (token/tag agreement, plan decision). This is a small additive 4th
  param + 4th return value from `nextLine`; no existing caller breaks (both optional).
- **Darkmoon/Brewfest multi-row events folded to one name.** AC schedules these as
  several `game_event` rows (per-zone Darkmoon, separate "building" setup events); every
  such ID maps to the same display name so the holiday resolves identically however the
  server schedules it.
- **Fallback invariant preserved & verified:** empty `ctx.active` (API absent) ⇒
  `eventFactor` 1.0 (never exclude); untagged ⇒ 1.0; `enableEventContext` off ⇒ 1.0.

Verification (Phase 3): all three touched/new files compiled clean via LuaJIT
(Python `lupa`): `context_map.lua`/`npc_name.lua`/`npc_text.lua` `dofile` OK,
`npcTalk.lua` `load()` OK AND a full top-to-bottom run under ALE stubs
(`GetActiveGameEvents`/`GetGameTime`/`CreateLuaEvent`/`SendWorldMessage` +
a `require` shim for the data files) raised no error. A verbatim
`normalizeEvents`/`eventFactor`/`resolveEvent`/`activeEventNameSet` harness passed all
16 assertions: (a) events-tagged line ⇒ 0 when its event NOT active; (b) ⇒ 1.0 when it
IS; (c) untagged ⇒ 1.0 (active or empty); (d) empty `ctx.active` ⇒ tagged 1.0 (no
exclude); (e) `enableEventContext` off ⇒ tagged 1.0; token/tag agreement: a
`events={"Hallow's End"}` line resolves `%event%` to "Hallow's End" whether or not it
is the live event; untagged + live ⇒ the live event name; untagged + nothing live ⇒
random fallback; multi-event tag prefers the active one, else the first; and the
`eventId→name` map resolves IDs 12/24/2/1 to the correct display names.

What was added (line ranges approximate, post-edit):

- **`normalizeTimes(times)`** — added in `npcTalk.lua` immediately after
  `normalizeAreas` (~line 631). An **exact mirror** of `normalizeAreas`: omitted
  ⇒ `(true, {})` (global wildcard); list `{"night","dusk"}` ⇒ `(false, {night=1,
  dusk=1})` via the `times[1] ~= nil` list-vs-map discriminator; graded map
  `{night=3, dusk=1}` ⇒ copied as-is. Returns `(timesGlobal, times-map)`.
- **`makeItem` wiring** — both the bare-string branch (untagged ⇒ `timesGlobal=true,
  times={}`) and the table branch (calls `normalizeTimes(entry.times)` right after
  `normalizeAreas`, stores `timesGlobal`/`times` on the item) now carry the parsed
  time tag, exactly parallel to `areaGlobal`/`areas`.
- **`timeFactor(item, c)`** — added in `npcTalk.lua` immediately after `areaFactor`
  (~line 1102). Parallel to `areaFactor`: `item.timesGlobal ⇒ 1.0`; flags off
  (`enableContextAware`/`enableTimeContext`) ⇒ 1.0; `c`/`c.timeKey` nil/neutral ⇒
  1.0 (no exclusion — preserves the fallback invariant when the clock is unknown);
  on-bucket ⇒ `item.times[c.timeKey] * timeMatchStrength` (graded boost, like
  `areaMatchStrength`; `timeMatchStrength=1` disables boost); tagged-but-off-bucket
  ⇒ `0` (HARD EXCLUDE). Reads the module-level `ctx`.
- **`scoreLine` formula** — now `base × roleFactor × moodFactor × areaFactor ×
  timeFactor × recencyPenalty`. `timeFactor(item, ctx)` is computed right after
  `areaFactor`, with an early `if (tf <= 0) then return 0 end` exclude guard
  mirroring the area guard. Doc comment updated.
- **`npc_text.lua` tagged lines (6)** — `times=` placed right after `areas=`:
  L206 farmer hauling to market `times={dawn=3, morning=1}` (graded); L223 & L238
  lamplighters at dusk `times={"dusk"}` (list); L366 candle/lantern vendor
  `times={dusk=3, night=2}` (graded); L378 curfew-bell guard `times={"night","dusk"}`
  (list); L471 dawn-watch soldier `times={"dawn"}` (list). Generic ambience left
  untagged. Both list and map authoring forms are exercised.

Decisions / deviations:

- **No deviation from the `areas` precedent.** `normalizeTimes` is a byte-for-byte
  structural copy of `normalizeAreas` (only the comment text differs), and
  `timeFactor` mirrors `areaFactor` plus the flag/neutral guards the plan mandates.
- **Neutral-ctx safety added beyond `areaFactor`.** Unlike `areaFactor` (which
  always has a real `char.area`), `timeFactor` returns 1.0 when `ctx.timeKey` is
  nil/neutral so an off-bucket tagged line is **not** excluded when the clock can't
  be read — keeping the "never go silent" invariant even with `GetGameTime`/`os.date`
  absent.

Verification: both files compiled clean with LuaJIT via Python `lupa` (`load()` OK,
no system `luac`). `timeFactor` unit harness (stubbed config + `ctx`, verbatim
`normalizeTimes`/`timeFactor`) passed all cases: (a) graded tagged line off-bucket ⇒
0; (b) on-bucket graded ⇒ 9.0 (`3*timeMatchStrength`), list on-bucket ⇒ 3.0; (c)
untagged ⇒ 1.0 with `timeKey` both set and nil; neutral `timeKey` on a tagged line ⇒
1.0; (d) `enableTimeContext=false` ⇒ tagged off-bucket ⇒ 1.0 (no exclusion).

What was added (line ranges are approximate, post-edit):

- **Config flags** — full block added after `areaMatchStrength` (~lines 40–55):
  `enableContextAware`, `enableTimeContext`, `enableEventContext`,
  `enableSeasonContext`, `timeMatchStrength`, `seasonMatchStrength`,
  `contextRefreshMs`, `eventApproachDays`, `eventAfterDays`, `enableEventBurst`.
  Phase 1 only acts on `enableContextAware` / `enableTimeContext` / `contextRefreshMs`.
- **Context block** — added right after the `selectRandom*` helpers (after
  `selectRandomWeather`, ~lines 443–530): the `ctx` table (commented `topic`
  forward-compat slot present; only `hour`/`timeKey`/`refreshed` populated),
  `bucketHour(h)` (exact from plan), `timeKeyDisplay` (inline timeKey→display pool,
  marked TODO to move to `context_map.lua` later), `nowMs()`, `refreshCtx()`
  (TTL-guarded, capability-guarded `GetGameTime`+`os.date` via `pcall`/`type`
  checks; respects the master/time flags), and the `recordTopic(line)` no-op stub.
- **`resolveTimeOfDay(c)`** — added after `recordTopic`; drives `%timeofday%`.
- **`renderTokens` signature** is now `renderTokens(txt, speaker, ctx)` (trailing
  `ctx` optional for backward compat). The `%timeofday%` gsub now calls
  `resolveTimeOfDay(ctx)` instead of `selectRandomTimeOfDay()` directly.
- **`speak()`** calls `refreshCtx()` at the top, passes `ctx` to `renderTokens`,
  and calls `recordTopic(raw)` before emit.

Decisions / deviations:

- **ms-tick source chosen:** `nowMs()` = `GetGameTime()*1000` when the API exists
  (ALE returns seconds), else `os.time()*1000`. There is **no** existing ms source
  in the file — recency uses a logical `globalTick` counter (see `recencyPenalty`,
  unchanged), and the only realtime use was `math.randomseed(os.time())`. So a new
  capability-guarded `nowMs()` helper was introduced (matches the `os.time`
  convention already present). TTL compares `nowMs()` against `ctx.refreshed`.
- **timeKey→display pool location:** inlined as `timeKeyDisplay` in `npcTalk.lua`
  (commented TODO to relocate to `context_map.lua` in Phase 3/5). Pools reuse the
  existing `timesofday` display vocabulary.
- **Graceful degradation verified:** flags off OR `GetGameTime`/`os.date` absent →
  `ctx.timeKey` stays neutral and `%timeofday%` falls back to
  `selectRandomTimeOfDay()` (today's behaviour). No errors, no silence.

Verification: file compiled with LuaJIT (via Python `lupa`, no system `luac`
available) — `load()` OK and full top-to-bottom run with ALE stubs raised no error.
`bucketHour` checks pass (0→night, 7→dawn, 12→midday, 23→night, plus boundary
cases). Functional check: with `GetGameTime`=07:00, `%timeofday%` drew only from
the dawn pool; nil-ctx fell back to the full random set.

For the Phase 3 agent (active events): follow the Phase 2 shape exactly.
- **Tag parsing**: add `normalizeEvents(events)` next to `normalizeTimes`
  (~line 631), mirroring `normalizeAreas`/`normalizeTimes`. Note `events` is
  **binary by design** (no graded boost) — a list of event display-names that
  hard-excludes when none is active — so the list/map plumbing is the same but the
  factor ignores weights. Store `eventsGlobal`/`events` on the item in `makeItem`'s
  **both** branches (bare-string ⇒ global, table ⇒ `normalizeEvents(entry.events)`),
  right after the `times` wiring.
- **Scorer insertion point**: `scoreLine(item, char, tick)` (~line 1113). Add
  `local ef = eventFactor(item, ctx); if (ef <= 0) then return 0 end` after the
  `timeFactor` guard, and multiply `ef` into the returned product (`base × rf × mf ×
  af × tf × ef × rp`). Define `eventFactor(item, c)` right after `timeFactor`
  (~line 1102), same flag/neutral guards (`enableContextAware`/`enableEventContext`;
  empty `ctx.active` ⇒ 1.0 so events never exclude when the API is absent).
- `ctx.active` (set-like event-name map) is already declared on the `ctx` table and
  populated `{}` by `refreshCtx`; Phase 3 fills it from `GetActiveGameEvents()` +
  the `eventId → name` map in the new `context_map.lua`.
- `ctx` is module-level (just after `selectRandom*`); `timeMatchStrength`/
  `seasonMatchStrength` config and all sub-flags already exist. `renderTokens` is
  already `(txt, speaker, ctx)` for the `%event%` substitution work.
- Seasons (Phase 5) follow the **identical** `normalizeTimes`/`timeFactor` shape
  with `seasonMatchStrength` and graded weights — copy Phase 2 verbatim.



> **Scope note.** ActiveChat's job is **ambient, in-world RP chatter** — atmosphere,
> not player imitation. This feature makes that chatter **read as if it belongs to
> the moment it is spoken in**: night lines at night, festival lines during the
> actual festival, weather/season talk that tracks the real game state instead of a
> coin flip. It is a **selection-and-substitution refinement**, not a new subsystem —
> it reuses the existing line scorer, placeholder substitution, and the documented
> `area` seam. Everything stays inside the fiction (no real-world clocks, no "server
> time" meta) and degrades gracefully: if a context source is unavailable, the engine
> falls back to today's random behaviour and nobody goes silent.

## Why (the gap today)

Three placeholder tokens already exist but resolve to **pure random** values,
disconnected from the live world (`npcTalk.lua`, near the `select*` helpers and the
substitution block ~lines 434–436, 1289–1291):

- `%event%`  → `selectRandomEvent()` — picks any holiday from the `events` table,
  even when no holiday is active. A character cheerfully mentions Winter Veil in the
  middle of summer.
- `%season%` → `selectRandomSeason()` — random, ignores the in-game date.
- `%timeofday%` → `selectRandomTimeOfDay()` — random, ignores the in-game clock. A
  guard says "good to see dawn break" at in-game midnight.

There is **no mechanism at all** for *line-level* time/event awareness: a
"the taverns are roaring tonight" line can fire at noon, and a Hallow's End duo can
fire in spring. The scorer (README "How a line is chosen") weights by
`role × mood × area × recency` — **time and event are not factors**, and tagged lines
can only hard-exclude on `area`.

This plan closes that gap with the **same shape** the `area` tag already uses:
context becomes (1) a small set of **derived ambient facts** read from the game, (2)
**new optional line tags** (`times`, `events`, `seasons`) scored like `areas`, and
(3) **context-bound substitution** so `%event%`/`%season%`/`%timeofday%` resolve to
*what is actually true right now* (or, for events, the nearest one in time).

## Engine: ALE (mod-ale), not classic Eluna

This server runs **[ALE](https://www.azerothcore.org/eluna/)** — the AzerothCore-
maintained Lua engine (module `mod-ale`), the successor to Eluna. The hooks/globals
below are confirmed present in the ALE `Global` class, so the plan pins exact calls
rather than listing candidates:

| Need | ALE call | Returns |
|---|---|---|
| In-game time | `GetGameTime()` | game time in **seconds** (uint32). On AC/3.3.5 the in-game day/night clock follows the **server's local time-of-day** — i.e. what the client shows — so the hour-of-day derived from this timestamp *is* the in-game clock. |
| Active events | `GetActiveGameEvents()` | table of active **event IDs**. |
| Active check | `IsGameEventActive(eventId)` | boolean (handy for a specific known ID). |
| Event schedule | `WorldDBQuery("…game_event…")` | the `game_event` table rows (`eventEntry`, `start_time`, `length`, `occurence`, `holiday`, `description`) — needed for *upcoming / recently-ended* events. |

## Decisions (locked)

1. **Time of day = in-game clock.** Derived from `GetGameTime()`. Because the WoW
   3.3.5 client renders day/night from the server's local time-of-day, the hour
   bucket computed from this timestamp matches what a player sees out the window —
   no wall-clock/timezone meta surfaced.
2. **Events gated on the actually-active game events.** `GetActiveGameEvents()` is the
   source of truth; an event-tagged line fires only when its event is live.
3. **No active event ⇒ reference the nearest one in time.** When nothing is active,
   `%event%` and event-flavored chatter look to the **most-recently-ended** or
   **soonest-upcoming** event (computed from `game_event` scheduling), with
   phase-appropriate wording (anticipation vs. aftermath). New tokens `%nextevent%` /
   `%lastevent%` let authors write these explicitly. Random-holiday substitution is
   gone — a character never names a holiday that isn't active, imminent, or just past.
4. **Season = in-game calendar.** Derived from the in-game month (via `GetGameTime()`),
   cross-checked against the seasonal-holiday calendar (Winter Veil ⇒ winter,
   Midsummer ⇒ summer, Harvest Festival/Pilgrim's Bounty ⇒ autumn, Noblegarden/Lunar
   Festival ⇒ spring). Seasons ship — they matter for harvest/weather flavor — not
   deferred.
5. **Context is a scoring factor, mirroring `area`.** New tags `times` / `events` /
   `seasons` use the **same list/map/hard-exclude semantics** as `areas`. Untagged =
   global wildcard (the fallback pool the matcher needs). Only **event** mismatch and
   explicit time/season tags hard-exclude; everything else just lowers odds. No
   character ever goes silent.
6. **Refresh, don't poll per line.** Context is read into a cached `ctx` table on a
   slow cadence (TTL ~60s, refreshed at tick time if stale) — never recomputed per
   candidate line. Decouples context cost from chatter volume.
7. **All behind config flags**, falling back to today's random behaviour when disabled
   or when an API is missing — safe to ship on any build.
8. **Chat-topic awareness is deferred but designed-for.** `ctx` is built as the single
   "what's true right now" table so a future "what was just said in chat" field drops
   in without reshaping anything (see "Tie-in" and "Forward-compat").

## Current architecture (what we build on)

`ActiveChat/npcTalk.lua` (single script under `if enableScript then … end`):

- **Context-bearing placeholder helpers** (`selectRandomEvent` / `selectRandomSeason`
  / `selectRandomTimeOfDay`, ~lines 434–436) and their tables (`events` ~343,
  `seasons` ~353, `timesofday` ~358). These are the substitution targets we make
  context-aware.
- **The substitution pass** (`renderTokens(txt, speaker)`, ~line 1241; the
  `%token%` gsubs ~1289–1291) runs once per line and already takes the speaking
  `speaker` (used by `cityFor(speaker)` / `homeCityBias`). We thread the cached `ctx`
  through the same call (`renderTokens(txt, speaker, ctx)`).
- **The line scorer** (`score = weight × roleFactor × moodFactor × areaFactor ×
  recencyPenalty`, README "How a line is chosen"). We add `timeFactor`,
  `eventFactor`, `seasonFactor` exactly parallel to `areaFactor`.
- **The `area` precedent end-to-end** — tag parsing (list vs graded map vs omitted),
  `areaMatchStrength`, hard-exclude on unlisted area, and the `FUTURE HOOK` comment in
  `generateCharacter` (~line 793). Context tags reuse this entire pattern, so the
  authoring format and the scorer change is small and familiar.
- **Per-channel repeating timers** (`CreateLuaEvent(fn, {min,max}, 0)`, events block
  ~1368) call `speak(channel, candidates, castFaction)` (~line 1333) — the top of
  `speak` is the natural place to refresh `ctx` (TTL-guarded) before resolving a
  speaker.

The renderer, substitution, formatting, faction scoping, scorer, and timers all stay.
What changes: **what the three time/event tokens resolve to**, and **three new
optional scoring factors** on lines. No new files are required for the engine; one new
content/data block holds the context vocabulary and mappings.

## Reading context (the `ctx` table)

A single module-level cache, refreshed on a slow cadence:

```lua
local ctx = {
  hour      = 0,          -- in-game hour 0..23 (from GetGameTime)
  timeKey   = "night",    -- bucketed: "dawn"|"morning"|"midday"|"afternoon"|"dusk"|"night"
  season    = "spring",   -- derived from in-game month
  active    = {},         -- set-like: { ["Hallow's End"]=true, ... } of ACTIVE events
  nextEvent = nil,        -- { name=..., daysAway=N } soonest upcoming (for %nextevent%)
  lastEvent = nil,        -- { name=..., daysAgo=N }  most recently ended (for %lastevent%)
  -- topic  = nil,        -- FORWARD-COMPAT: last chat topic (deferred; see Tie-in)
  refreshed = 0,          -- ms tick of last refresh
}
```

### In-game time — `GetGameTime()`

`GetGameTime()` returns the game time in **seconds** (a uint32 server timestamp). On
AzerothCore 3.3.5 the client's day/night cycle is driven by the server's local
time-of-day, so the hour-of-day derived from this timestamp **is** the in-game clock
the player sees — exactly what "use in-game time, not real-world" asks for. Derive the
hour with `os.date` over the timestamp (`os.date` here is a *decomposition* of the
game timestamp, never a surfaced real date):

```lua
local t   = os.date("*t", GetGameTime())   -- t.hour 0..23, t.month 1..12
ctx.hour  = t.hour
```

Bucket the hour into `ctx.timeKey`:

```lua
-- coarse, fiction-friendly buckets; tune freely
local function bucketHour(h)
  if h < 5  then return "night"     end
  if h < 8  then return "dawn"      end
  if h < 11 then return "morning"   end
  if h < 14 then return "midday"    end
  if h < 18 then return "afternoon" end
  if h < 21 then return "dusk"      end
  return "night"
end
```

The existing `timesofday` strings (`"dawn"`, `"dusk"`, `"midnight"`, …) are the
*display* vocabulary; `timeKey` is the coarser *tag/selection* vocabulary. Map each
`timeKey` to a small pool of display strings so `%timeofday%` reads naturally
(`night → {"midnight","nightfall","the small hours before dawn"}`).

### Active events — `GetActiveGameEvents()`

`GetActiveGameEvents()` returns a table of active **event IDs**. Build `ctx.active` by
mapping those IDs → the display names already in the `events` table via a small
`eventId → name` map (`game_event` IDs are stable per expansion; authored in
`context_map.lua`). `IsGameEventActive(eventId)` is the cheap single-ID check if you
ever need one specific event. If the call is unavailable, `ctx.active = {}` and the
engine falls back.

### Nearest event when nothing is active (decision 3)

The holiday IDs in `ctx.active` say *what's on now* but not *what's near*. To reference
a recently-ended or upcoming event, read the **schedule** once and cache it:

```lua
-- Read game_event scheduling once at startup (and re-read rarely):
--   SELECT eventEntry, start_time, length, occurence FROM game_event
-- length & occurence are MINUTES; recurring holidays use occurence to repeat.
-- For each known holiday id, compute the next start >= now and the last end <= now
-- relative to GetGameTime(); keep the soonest-upcoming and most-recent-ended whose
-- id maps to a display name. Store as ctx.nextEvent / ctx.lastEvent with day offsets.
```

This needs no extra API beyond `WorldDBQuery` + `GetGameTime()` and the same
`eventId → name` map. When `ctx.active` is empty, `%event%` resolves to
`ctx.nextEvent` (preferred) or `ctx.lastEvent`, and the wording pools choose
anticipation vs. aftermath phrasing (see "Context-aware substitution"). If scheduling
can't be read, `%event%`-bearing untagged lines fall back to a neutral phrase pool
("the next festival") rather than naming anything.

### Season — in-game calendar (decision 4)

Derive `ctx.season` from the in-game month (`t.month` from the `GetGameTime()`
decomposition) via a `month → season` map, then sanity-check against the seasonal
holiday calendar so the two never disagree (if Winter Veil is active it's winter
regardless of month-map edge cases). Northern-hemisphere mapping by default; the map
lives in `context_map.lua` so a themed realm (e.g. perpetual-winter Northrend) can
override it. Season feeds harvest/weather/festival flavor, so it ships in the main
sequence — not deferred.

### Refresh discipline

```lua
local CTX_TTL = 60000  -- ms
local function refreshCtx()
  local now = <ms tick>
  if now - ctx.refreshed < CTX_TTL then return end
  local t        = os.date("*t", GetGameTime())   -- guarded; nil-safe
  ctx.hour       = t.hour
  ctx.timeKey    = bucketHour(ctx.hour)
  ctx.season     = monthToSeason(t.month)
  ctx.active     = activeEventNameSet()            -- {} if API missing
  ctx.nextEvent, ctx.lastEvent = nearestEvents(GetGameTime())  -- nil if schedule unknown
  ctx.refreshed  = now
end
```

Call `refreshCtx()` at the top of `speak()` (cheap due to TTL) so the first line
after a holiday begins is already aware. The schedule scan that backs `nearestEvents`
is computed from a startup-cached `game_event` snapshot, so the per-refresh cost is
just arithmetic over a handful of holidays.

## New line tags (parallel to `areas`)

Authoring gains three optional tags, identical in semantics to `areas` (README
"Tagged authoring format"):

| Field | Meaning |
|---|---|
| `times`   | Time-of-day fit. **Omit** = any time. List (`{"night","dusk"}`) = uniform fit, unlisted buckets hard-excluded. Map (`{night=3, dusk=1}`) = graded. |
| `events`  | Event fit. **Omit** = fires regardless of events (global). A **list** of event display-names = the line fires **only while one of those events is active** (`ctx.active`); otherwise **hard-excluded**. |
| `eventWindow` | Opt-in for the lead-up/aftermath of an `events`-tagged line. `"active"` (default) = only while live. `"approach"` = also fire in the N-day run-up. `"after"` = also fire in the N-day wind-down. Lets you author anticipation/aftermath lines that key off `ctx.nextEvent`/`ctx.lastEvent`. |
| `seasons` | Season fit. Same list/map/hard-exclude semantics as `times`. |

Examples:

```lua
-- night-only ambience (random in city by day, this stays silent until evening)
{ "The lamplighters are done; only the watch is awake now.",
  roles={"guard"}, times={"night","dusk"} },

-- fires ONLY while Hallow's End is the live game event
{ "Mind the Headless Horseman if you're out past dark for %event%.",
  events={"Hallow's End"}, times={night=3, dusk=2} },

-- anticipation: fires in the run-up to Winter Veil (not during)
{ "Only a few days until %nextevent% -- have you hung the holly yet?",
  events={"Winter Veil"}, eventWindow="approach" },

-- aftermath: fires just after Brewfest ends
{ "Quiet now that %lastevent% is over. The kegs are all dry.",
  events={"Brewfest"}, eventWindow="after" },

-- graded by time, no hard exclude
{ "%city% smells of bread already.", times={dawn=3, morning=2} },

-- harvest flavor, autumn only
{ "Good harvest this year -- the granaries are near full.",
  seasons={"autumn"}, roles={"farmer"} },
```

Untagged lines stay **global wildcards** — the universal fallback pool. The README's
standing guidance holds: *tag a line only when its content clearly implies a context*;
leave generic ambience untagged so the matcher always has eligible fallbacks.

## Scorer changes

Extend the per-candidate score (README formula) with three factors that mirror
`areaFactor` exactly:

```
score = weight
      × roleFactor
      × moodFactor
      × areaFactor
      × timeFactor    (1.0 if untagged; per-bucket weight if ctx.timeKey listed; 0 = EXCLUDE if times tagged and bucket absent)
      × eventFactor   (1.0 if untagged; if events tagged: applies when its event is in ctx.active — or, per eventWindow, within the approach/after window of ctx.nextEvent/lastEvent — else 0 = EXCLUDE)
      × seasonFactor   (1.0 if untagged; per-season weight if ctx.season listed; 0 = EXCLUDE if seasons tagged and season absent)
      × recencyPenalty
```

- `timeFactor` / `seasonFactor` follow `areaFactor` to the letter: omitted ⇒ 1.0
  (global), list/map ⇒ matched weight, tagged-but-unmatched ⇒ 0 (hard-exclude). New
  config `timeMatchStrength` / `seasonMatchStrength` (default `3.0`, like
  `areaMatchStrength`; `1` disables) controls how hard a *present-but-graded* match
  is boosted.
- `eventFactor` is **binary by design**: an event-tagged line is fundamentally
  about that event, so it either applies or it must not appear — no "low floor".
  *Applies* means the event is in `ctx.active`, **or** (for `eventWindow="approach"`/
  `"after"`) the line's event is the `ctx.nextEvent`/`ctx.lastEvent` within the
  configured window. Everything else excludes. This is the one place besides `area`
  where mismatch means exclude.
- **Fallback guarantee preserved.** Because untagged lines remain 1.0 on every new
  factor, the global pool is never excluded; a character always has candidates even
  if every tagged line is out of context. This is the same invariant `area` relies on.

The new factors are pure functions of `(line, ctx)` and add a few table lookups per
candidate — negligible next to the existing role/mood/area work.

## Context-aware substitution

Thread `ctx` into the substitution pass (it already receives `speaker`):

- `%timeofday%` → a display string drawn from `ctx.timeKey`'s pool (so it agrees with
  the clock and with any `times` tag on the line). Fallback: `selectRandomTimeOfDay()`
  when context disabled/unavailable.
- `%season%` → `ctx.season`. Fallback: `selectRandomSeason()`.
- `%event%` → resolves to the **most relevant real event**, in priority order:
  1. if the line has an `events` tag, the tagged event (so token and tag always agree);
  2. else an entry from `ctx.active` (something live right now);
  3. else (decision 3) the nearest event in time — `ctx.nextEvent` preferred, then
     `ctx.lastEvent`;
  4. else (schedule unknown) a neutral phrase pool ("the next festival", "the
     holidays"). **Never** a random specific holiday.
- `%nextevent%` → `ctx.nextEvent.name` (soonest upcoming); `%lastevent%` →
  `ctx.lastEvent.name` (most recently ended). These let authors write explicit
  anticipation/aftermath lines (paired with `eventWindow`). Both fall back to the
  neutral phrase pool when scheduling is unknown.

This keeps token output and line eligibility **consistent**: a character only ever
names a holiday that is active, imminent, or just past — never a wrong one.

## Tie-in: Player Interaction plan

`PLAYER_INTERACTION_PLAN.md` already wants responders to be "aware of other things in
chat." Context is exactly that awareness, and it composes cleanly:

- **Shared `ctx`.** The reaction dispatcher (`dispatch` / `advanceThread`) reads the
  same `ctx` table, so a greeting answered at in-game night can pull a night-flavored
  reply, and a Hallow's End greeting can trigger event-flavored banter — using the
  same `times`/`events`/`seasons` tags on reaction content (`npc_reactions.lua`).
- **Event-sparked ambient bursts.** When an event flips active, optionally fire a
  one-shot "the festival has begun" character↔character burst (reuses the staggered
  burst renderer the interaction plan proposes). Behind a flag; rate-limited to once
  per event activation.
- **"Other things in chat" awareness (deferred, but designed-for).** The interaction
  plan's "aware of other things in chat" is **not built here**, but `ctx` is shaped to
  receive it: the commented `ctx.topic` slot is reserved for a future light ring buffer
  of the last N ambient lines' *topics* (e.g. avoid two weather lines back-to-back, or
  let a responder reference what was just said). Because it would be just another `ctx`
  field consumed by the same scorer/substituter, adding it later needs **no reshaping**
  — only a new factor and a writer that records each emitted line's topic. Build the
  rest of this plan knowing that field is coming.

The shared seam is: **`ctx` is the single source of "what's true right now," read by
both the ambient scorer/substituter and the interaction responder.** Build it once;
let it grow.

## Forward-compat checklist (so chat-awareness drops in cleanly)

- Keep `ctx` a flat, extensible table; never assume its field set is fixed.
- Make each scoring factor a standalone `factor(line, ctx)` function so a future
  `topicFactor` slots into the product without touching the others.
- Have the emit path call a single `recordTopic(line)` no-op stub now, so wiring a
  real ring buffer later is a one-function change, not a hunt through the renderer.

## Files

| File | Change |
|---|---|
| `ActiveChat/npcTalk.lua` | Add config flags; add `ctx` + `refreshCtx`/`bucketHour`/`monthToSeason`/`activeEventNameSet`/`nearestEvents`; read the `game_event` schedule snapshot at startup; call `refreshCtx` at the top of `speak()`; add `timeFactor`/`eventFactor`/`seasonFactor` (and the `eventWindow` logic) to the scorer; make `%timeofday%`/`%season%`/`%event%`/`%nextevent%`/`%lastevent%` context-aware in `renderTokens`; add the `recordTopic` no-op stub. |
| `ActiveChat/talk_text/npc_text.lua` | Add `times`/`events`/`seasons`/`eventWindow` tags to lines that clearly imply them. Leave generic ambience untagged. (Optional, incremental — engine works with zero tagged lines.) |
| `ActiveChat/context_map.lua` *(new, small)* | The context vocabulary/maps kept out of the engine: `timeKey → display-string pools`, `month → season`, and the **`eventId → display-name`** map (keyed to AC `game_event` IDs, so `GetActiveGameEvents()` IDs and the `game_event` schedule both resolve to the names already in the `events` table). Plain Lua tables, edited without touching the engine — same philosophy as `npc_name.lua`. |
| `README.md` | Document the three new tags, the config flags, context sourcing + fallback behaviour, and the in-character rule (no real clocks/dates surfaced). Update the `%event%`/`%season%`/`%timeofday%` token rows to note they are now context-aware. |
| `docs/plans/PLAYER_INTERACTION_PLAN.md` | Cross-reference: responders read shared `ctx`. (One-line note; no behavioural change required there.) |

## Config additions (top of `npcTalk.lua`)

```lua
local enableContextAware   = true    -- master switch for the whole feature
local enableTimeContext    = true    -- in-game-clock-aware times + %timeofday%
local enableEventContext   = true    -- active-event gating + %event%
local enableSeasonContext  = true    -- in-game-month season + %season%
local timeMatchStrength    = 3.0     -- like areaMatchStrength; 1 = off
local seasonMatchStrength  = 3.0
local contextRefreshMs     = 60000   -- ctx cache TTL
local eventApproachDays     = 5      -- "approach" window before an event starts
local eventAfterDays        = 3      -- "after" window once an event ends
local enableEventBurst      = false  -- one-shot "festival has begun" burst on activation (ties to interaction plan)
```

When `enableContextAware = false` (or a sub-flag off, or an API missing), the
corresponding factor is forced to 1.0 and the token falls back to its random helper —
i.e. **exactly today's behaviour**. (There is deliberately no "random holiday" flag:
decision 3 replaces random-event substitution with nearest-event reference.)

## Edge cases / correctness checklist

- **API absence is normal.** If the game-time/event API isn't present on the build,
  `refreshCtx` leaves that field neutral and the matching factor is 1.0 — never error,
  never go silent. Guard every API call (`pcall` or existence check) once at startup
  and cache the capability.
- **No hard-exclude trap.** Tagged-only content + out-of-context = the global untagged
  pool carries the tick. Verify a character whose every tagged line is excluded still
  speaks (this is the `area` invariant; keep it).
- **Token/tag agreement.** When a line is `events={"Hallow's End"}`, `%event%` must
  resolve to *Hallow's End*, not another active event — the tag's event wins.
- **Nearest-event sanity.** `nearestEvents` must handle recurring holidays
  (`occurence`-based repeats) and the wrap-around case (an event whose next start is
  next year). Cap day-offsets so a far-off event isn't surfaced as "soon"; if nothing
  is within a sane horizon, leave `ctx.nextEvent`/`lastEvent` nil and let `%event%`
  use the neutral phrase pool.
- **No meta leakage.** `%timeofday%`/`%season%` resolve to fiction words only; never
  emit "22:00", "server time", or a real date. Season comes from a *mapping* over the
  `GetGameTime()` month, not a printed month.
- **Midnight boundary / DST.** The hour comes from `os.date("*t", GetGameTime())`;
  buckets are coarse so skew near a boundary is cosmetically harmless. Season is
  month-granularity, so DST is irrelevant there.
- **Refresh cost bounded** by TTL; never per-candidate. Confirm `refreshCtx` early-
  exits on the common path.
- **Event burst rate-limit.** Track last-seen active-event set; fire the optional
  burst only on a transition into active, once, not every refresh.
- **Respect master switches** (`enableScript`, `enableFactionChat`) and the existing
  `area`/recency behaviour unchanged.

## Phased implementation

1. ✅ **DONE — `ctx` + refresh, time only.** Add `ctx`, `bucketHour`, `refreshCtx` (time field
   only) over `os.date("*t", GetGameTime())`, capability-guarded. Make `%timeofday%`
   context-aware with random fallback. Add the `recordTopic` no-op stub now (forward-
   compat). Ship and observe — no scorer change yet, no content change.
   *(See "## Implementation status" near the top for line ranges and details.)*
2. ✅ **DONE — `timeFactor` in the scorer + `times` tag.** Added the factor as a
   standalone `timeFactor(item, ctx)` parallel to `areaFactor`, parsed `times`
   (list/map) via `normalizeTimes` mirroring `normalizeAreas`, and tagged 6
   obviously day/night lines in `npc_text.lua`. Fallback invariant verified.
   *(See "## Implementation status" near the top for line ranges and details.)*
3. ✅ **DONE — Active events.** Added `GetActiveGameEvents()` sourcing + the
   `eventId → name` map in the new `context_map.lua` + `eventFactor` + `events` tag
   + active-only `%event%`. Tagged the existing holiday lines.
   *(See "## Implementation status" near the top for line ranges and details.)*
4. ✅ **DONE — Nearest events.** Read the `game_event` schedule snapshot at startup
   (`readEventSchedule` via `WorldDBQuery` + `UNIX_TIMESTAMP(start_time)`,
   capability-guarded, cached in `eventSchedule`); added `nearestEvents` (recurring +
   year-wrap + `NEAREST_HORIZON_DAYS=30` cap), `ctx.nextEvent`/`lastEvent`,
   `%nextevent%`/`%lastevent%`, the `eventWindow` tag (`approach`/`after`) in
   `eventFactor`, the neutral phrase pool (`context_map.lua` `M.eventNeutral`), and the
   nearest-event `%event%` fallback (replacing the random one). Authored 4
   approach/aftermath lines.
   *(See "## Implementation status" near the top for line ranges and details.)*
5. ✅ **DONE — Seasons.** Added `monthToSeason` (+ `M.monthToSeason` map),
   `seasonFactor`, `normalizeSeasons` + `seasons` tag, `%season%` context binding via
   `resolveSeason`, and the holiday-calendar cross-check (`holidayToSeason`, applied
   after the month derivation in `refreshCtx`). Tagged 6 harvest/snow/heat/lambs lines
   across all four seasons.
   *(See "## Implementation status" near the top for line ranges and details.)*
6. ✅ **DONE (event burst) — Interaction tie-in (optional).** Added the optional
   event-activation burst behind `enableEventBurst` (default `false` ⇒ zero
   behavioural change): on a transition INTO active (diff of the fresh `ctx.active`
   against a module-level snapshot in `refreshCtx`), a one-shot character↔character
   "the festival has begun" duo burst is seeded into the existing conversation
   machinery (`t.conv`), once per activation. **The "wire shared `ctx` into the
   reaction dispatcher" sub-item is DEFERRED** — there is no dispatcher
   (`dispatch`/`advanceThread`/`npc_reactions.lua`) built yet, so there is nothing
   to wire into; the shared-`ctx` design already accommodates it (module-level,
   read at the top of `speak()`), and PLAYER_INTERACTION_PLAN.md now cross-references
   it. *(See "## Implementation status" for details.)*
7. ✅ **DONE — README + cross-reference** the player-interaction plan. Added a new
   "Context-aware chatter" section (overview, the three new line tags with examples,
   the context tokens, context sourcing + fallback table, the optional event burst),
   extended the tagged-authoring tag table with `times`/`events`/`eventWindow`/
   `seasons`, updated the "How a line is chosen" scorer formula with `timeFactor`/
   `eventFactor`/`seasonFactor`, updated the placeholder token rows for
   `%timeofday%`/`%season%`/`%event%` (now context-aware) + added `%nextevent%`/
   `%lastevent%` + the in-character no-real-clock rule, and added a
   "Context-aware chatter flags" config sub-table. Interaction-plan cross-reference
   confirmed present in PLAYER_INTERACTION_PLAN.md (Phase 6) and re-cited from the
   README. *(See "## Implementation status" for details.)*

   **The phased implementation (1–7) is now COMPLETE.** The only deferred sub-item is
   Phase 6's reaction-dispatcher wiring, which has nothing to wire into until the
   (separate) player-interaction dispatcher exists; the shared-`ctx` seam already
   accommodates it and is cross-referenced.

## Verification

- **Syntax/load:** `luac -p` (or `load`) every touched file; `_luacheck.py` if used
  in this repo.
- **Offline harness (pure functions):** assert `bucketHour(0)=="night"`,
  `bucketHour(7)=="dawn"`, `bucketHour(12)=="midday"`, `bucketHour(23)=="night"`;
  `monthToSeason(12)=="winter"`; `nearestEvents` over a fixture schedule returns the
  correct upcoming/recently-ended pair (including the year-wrap case); and a scorer
  unit test proving (a) an `events`-tagged line scores 0 when its event isn't in
  `ctx.active` and >0 when it is, (b) an `eventWindow="approach"` line scores >0 only
  when its event is `ctx.nextEvent` within `eventApproachDays`, (c) a `times`-tagged
  line hard-excludes off-bucket, (d) an untagged line always scores >0 regardless of
  `ctx`.
- **Fallback test:** stub `GetGameTime`/`GetActiveGameEvents` as absent → confirm
  every factor is 1.0, tokens fall back to random/neutral, no errors, ambient chatter
  unchanged.
- **In-game matrix:** set the server clock to a night hour → night lines appear,
  `%timeofday%` reads as night; with `StartGameEvent`/`StopGameEvent` (ALE globals)
  force a holiday active → event-tagged lines and a correct `%event%` appear and
  vanish when it ends; just before/after a scheduled holiday → approach/aftermath
  lines and `%nextevent%`/`%lastevent%` read correctly; toggle each sub-flag off →
  reverts to random for that dimension; confirm a character with only out-of-context
  tagged lines still speaks from the global pool.
- **Tone check:** read tagged lines aloud — they must sit naturally beside untagged
  ambience and never surface a real clock/date.
- **Regression:** ambient World timers fire unchanged; `area`/role/mood/recency
  behaviour identical when context disabled.

## Decisions resolved (was: open)

- **In-game vs real time** → **in-game** (`GetGameTime()`); the 3.3.5 client renders
  day/night from the server clock anyway, so this matches what players see.
- **ALE calls** → pinned: `GetGameTime()`, `GetActiveGameEvents()`,
  `IsGameEventActive(id)`, `StartGameEvent`/`StopGameEvent` (for testing),
  `WorldDBQuery` over `game_event`. All confirmed in the ALE `Global` class.
- **`%event%` with nothing active** → reference the **nearest event in time**
  (`ctx.nextEvent` → `ctx.lastEvent` → neutral phrase). No random-holiday path.
- **Seasons** → **shipped**, sourced from the in-game calendar (month + holiday
  cross-check). Relevant for harvest/weather flavor.
- **Chat-topic awareness** → **deferred**, but `ctx`/scorer/emit path are built so it
  drops in as one more field + factor (see "Forward-compat checklist").

## Remaining choices (low-stakes, sane defaults set)

- **Bucket boundaries** in `bucketHour` and the **`month → season`** mapping — tune to
  taste; defaults are northern-hemisphere and conventional WoW day/night.
- **`eventApproachDays` / `eventAfterDays`** window sizes (defaults 5 / 3).
- **Season hemisphere/theming** — `context_map.lua` exposes the map for themed realms
  (e.g. perpetual-winter Northrend).
- **The `eventId → name` map coverage** — start with the holidays already in the
  `events` table; add IDs as you author event-specific content.
