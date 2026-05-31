# Plan: Conversation Pacing for ActiveChat

> **Scope note.** A small, self-contained engine change: once a duo/group starts, run
> its remaining lines on a **dedicated short-interval burst timer** so a multi-line
> exchange reads as one real-time conversation instead of one line per ambient tick.
> Realizes the open question left in `PLAYER_INTERACTION_PLAN.md` ("whether ambient
> character↔character exchanges should adopt staggered burst timing") for **ambient**
> duos/groups.

## Relevant docs

- docs/config.md
- PLAYER_INTERACTION_PLAN.md (shares the `convLineGap`/`lineGap` burst idea)
- ZONE_AWARE_PLAN.md (per-zone delivery groups must key conversation state)

## Completed

- None yet — all phases below are planned.

---

## Phases (planned)

### **Phase 1 — Burst-paced conversations**

#### Note

> **Problem (the gap today).** A duo/group is started by `nextLine` (it sets `st.item`
> and emits line 1), then each subsequent line of the chain is emitted on the *next
> ambient tick*. So a multi-line conversation is paced by the ambient driver interval
> (`talk_time = {1000,10000}`, `faction_talk_time = {8000,20000}`). Two problems:
>
> 1. **Chains read as disjointed.** Up to 10–20s can pass between *"Quiet on the wall
>    tonight."* and *"Too quiet. I don't like it."* — that doesn't read as one exchange.
> 2. **Sparse configs make it worse.** If an operator widens `talk_time` to make the
>    world quieter, they *also* slow down every in-progress conversation, which is
>    backwards: ambient frequency and within-conversation pacing should be independent
>    knobs. A sparse world should still have its occasional conversations play out
>    crisply, just less often.
>
> **Goal.** When a duo/group starts, run its remaining lines on a dedicated
> short-interval burst timer with its own config, decoupled from the ambient cadence.
> The ambient driver only decides *when a new conversation starts*; the burst timer
> decides *how fast its lines flow once started*.

**Current machinery (what we build on).**

- `nextLine(channel, …)` starts a chain (`st.item` set) or continues one (advances
  `st.ti` over `st.item.data`), returning one line per call.
- `speak(channel, …)` is the per-tick driver: resolve speaker → `nextLine` → render →
  `emit`.
- `speakerForLine` picks the voice for each chain line (A/B for duos, non-repeat for
  groups); per-channel state lives in `t.conv[channel]`.
- `CreateLuaEvent(fn, delay, repeats)` — `repeats=1` gives a one-shot timer (already
  used for the event burst and proposed in the interaction plan's `schedule`).

#### Dependencies & order

The player-sparked burst in `PLAYER_INTERACTION_PLAN.md` uses the same
`convLineGap`/`lineGap` idea; share one runner if both ship. With zone-aware delivery,
the burst must target the **same delivery group** the chain started in — key `t.conv`
by zone bucket, not just channel (see `ZONE_AWARE_PLAN.md`). See `TODO.md` for the
cross-plan ordering.

#### Part A — A self-rescheduling chain timer

**Approach — split responsibilities.**

- **Ambient driver (`speak`)** only ever *starts* an item. When `nextLine` returns a
  multi-line item (`st.item.kind ~= "line"` and the chain has remaining lines), `speak`
  emits line 1 as today, then **hands the rest to a burst runner** and returns. It does
  **not** advance the chain itself anymore.
- **Burst runner** — a one-shot timer that emits the next chain line and reschedules
  itself until the chain is exhausted, at a jittered `convLineGap` interval:

```lua
local function runChainBurst(channel, castFaction)
    local gap = math.random(convLineGap[1], convLineGap[2])
    CreateLuaEvent(function()
        local st = t.conv[channel]
        if (not st) or (not st.item) or (st.item.kind == "line") then return end  -- finished/cleared
        -- emit the next chain line using the SAME fixed cast (nextLine's continue path)
        local raw, speaker, audience, item = nextLine(channel, nil, nil, castFaction)
        if (raw) then emit(audience, formatWorld(speaker, renderTokens(raw, speaker, ctx, item))) end
        if (t.conv[channel] and t.conv[channel].item) then
            runChainBurst(channel, castFaction)   -- more lines: reschedule
        end
    end, gap, 1)
end
```

`nextLine`'s "continue an in-progress chain" branch already runs without needing fresh
candidates/initiator (it reads `st.item`/`st.cast`), so the burst runner can call it
with `nil` candidates safely — verify and, if needed, guard that branch to not fall
through to "start fresh" when called mid-chain.

**Suppress double-emission.** While a chain is mid-flight, the ambient driver tick for
that channel must **not** also fire. Add a `st.bursting` flag set when the burst starts
and cleared when the chain ends; `speak` early-returns for a channel whose state is
`bursting`. (Today the chain advancing *is* the ambient tick, so there's no conflict;
once the burst timer owns continuation, the ambient tick must yield.)

**Behavior this produces.**

- A conversation's lines land `convLineGap` apart (e.g. 1.5–4s), reading as a real
  exchange, **regardless** of how sparse `talk_time` is.
- Ambient frequency (`talk_time`) and within-conversation pacing (`convLineGap`) are
  now orthogonal: widen `talk_time` for a quiet world without making conversations drag.
- Single `line` items are unaffected — no chain, no burst, one-and-done.

#### Part B — Config + opt-in

**Config additions (top of `npcTalk.lua`).**

```lua
local enableBurstConversations = true        -- false = legacy one-line-per-ambient-tick
local convLineGap              = {1500, 4000} -- ms between lines of a chain (jittered)
-- optional: cap a chain's total airtime so a long group can't monopolize a channel
local convMaxLines             = nil          -- nil = run the whole chain
```

When `enableBurstConversations=false`, keep the current behavior exactly (chain advances
on the ambient tick) so this is a clean opt-in.

#### Build order

1. Add config + `st.bursting`; gate everything behind `enableBurstConversations`.
2. Make `speak` start-only for multi-line items; add `runChainBurst`.
3. Verify `nextLine`'s continue branch is safe to call with `nil` candidates mid-chain.
4. Reconcile with zone delivery (key conversation state by delivery group).
5. README + manifest note.

#### Edge cases / correctness checklist

- **Player/cast validity** — the cast is fixed at start (`st.cast`); the burst timer
  just re-voices it, so no re-resolution mid-chain. With zone-aware delivery, the burst
  must target the **same delivery group** the chain started in (see
  `ZONE_AWARE_PLAN.md` — key `t.conv` by zone bucket, not just channel).
- **No overlap** — `st.bursting` guard prevents the ambient tick from starting a second
  item on a channel whose chain is still running.
- **Clean finish** — last line clears `st.item` (as `nextLine` already does) and the
  runner stops rescheduling; clear `st.bursting`.
- **Restart/timer safety** — one-shot timers (`repeats=1`) don't accumulate; confirm a
  chain that's interrupted (e.g. all listeners log out) ends without orphaned timers.
- **Interaction-plan reuse** — the player-sparked burst in `PLAYER_INTERACTION_PLAN.md`
  uses the same `convLineGap`/`lineGap` idea; share one runner if both ship.

#### Verification

- `_luacheck.py` on `npcTalk.lua`.
- In-game: start a duo and confirm its two lines land ~`convLineGap` apart even with
  `talk_time` widened to a sparse setting; confirm single lines are unaffected; confirm
  no channel ever emits two overlapping items; toggle `enableBurstConversations=false`
  and confirm the old cadence returns.
