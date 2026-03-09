# MT5 NL-EA — Handoff to Claude Code
## World Tech Edge · Steps 1–5 (partial) Complete

---

## WHAT THIS IS

A MetaTrader 5 Expert Advisor (EA) that accepts natural language trading instructions from an operator via **Telegram**, uses the **Claude API** to extract structured intent, and executes the resulting trade operations against a live or demo MT5 account.

**Owner:** World Tech Edge (Richard, Adelaide AU)
**Current status:** Step 5 complete. All six core primitives live. Step 6 (end-to-end testing) pending market open.
**Working relationship:** Richard and Claude (claude.ai) designed and built this together. Claude Code continues the build from here. Richard remains the collaborator on all decisions.

---

## THE ONE PRINCIPLE THAT CANNOT BE COMPROMISED

> **Claude's job is intent extraction. The EA's job is execution. These two responsibilities never cross.**

Claude never queries MT5 state, never looks up prices, never makes trading decisions. It solely translates natural language into a structured JSON task object. The EA owns all MT5 context and carries out the actual operations.

---

## ARCHITECTURE

```
Operator (Richard)
    | Telegram message
Telegram Bot
    | MT5 WebRequest (HTTP)
MT5 EA (MQL5)
    |-- Telegram Listener       -- receives NL + approval replies via OnTimer()
    |-- Claude Intent Extractor -- POSTs to Claude API, parses Task JSON
    |-- Task Queue Engine       -- OnTick() loop, evaluates monitoring tasks
    |-- Primitive Executor      -- executes trade operations against MT5
    |-- Telegram Notifier       -- sends results back to operator
```

**Locked technical decisions:**
- MT5 native `WebRequest()` for all HTTP -- no Python bridge
- Telegram long-polling via getUpdates (no webhook needed)
- JAson.mqh for JSON parsing (must be in MQL5/Include/)
- Claude API called via POST from MQL5
- All credentials as EA input parameters (never in code)

---

## FILE STRUCTURE

All files live in `MQL5/Experts/NL_EA/`:

| File | Purpose |
|------|---------|
| `NL_EA.mq5` | Main EA -- OnInit, OnDeinit, OnTick, OnTimer, message routing |
| `State.mqh` | EA mode (LIVE/TRAINING) + conversation state machine |
| `TaskQueue.mqh` | STask struct, queue management, trigger evaluation |
| `JsonParser.mqh` | Claude JSON response -> STask (wraps JAson) |
| `Claude.mqh` | Claude API POST + response unwrapping |
| `Telegram.mqh` | Telegram poll + send |
| `Executor.mqh` | Primitive dispatcher -- see status below |
| `SystemPrompt.mqh` | Claude system prompt v2.0.1 embedded as MQL5 string |

**Dependency:** JAson.mqh must be in `MQL5/Include/` (https://www.mql5.com/en/code/13663)

**Allowed URLs** (Tools > Options > Expert Advisors):
- https://api.anthropic.com
- https://api.telegram.org

---

## EXECUTOR STATUS -- ALL PRIMITIVES LIVE

| Primitive | Status | Notes |
|-----------|--------|-------|
| `query` | LIVE | account, positions (sum/count/avg/list), history |
| `modify_position` | LIVE | breakeven, pips, price -- uses TRADE_ACTION_SLTP |
| `cancel_order` | LIVE | filters by ticket/magic/symbol/type, TRADE_ACTION_REMOVE, backward iteration |
| `place_market` | LIVE | buy/sell, SL/TP pips, IOC filling, default magic/comment from inputs |
| `close_positions` | LIVE | opposite deal at market, realised P&L sum, uses PositionMatchesFilters |
| `partial_close` | LIVE | volume split via reduce_volume_pct, VOLUME_STEP/MIN validation, skip reporting |
| `place_pending` | LIVE | limit/stop, entry price/offset, SL/TP pips, expiration_hours support |
| `watch` | LIVE | template expansion, position placeholders {ticket} {symbol} {profit} etc |
| `modify_order` | LIVE | TRADE_ACTION_MODIFY on pending orders -- entry/SL/TP/expiration changes |
| `trail_stop` | LIVE | persistent tick-based trailing SL, never moves SL backwards |
| `close_by` | LIVE | TRADE_ACTION_CLOSE_BY, pairs opposite positions on same symbol |

**Key features added:**
- `InpMagicNumber` and `InpOrderComment` EA input parameters (defaults, overridable per-instruction)
- Pending order expiration via `expiration_hours` field
- Trailing stop as persistent task (TRIGGER_TICK + modify SL each tick)
- Close-by for hedged accounts (saves spread)

**Next:** Step 6 -- end-to-end demo testing, then system prompt update for new verbs

---

## TASK SCHEMA -- THE CONTRACT

Every Claude response is a JSON envelope. The EA parses exactly this structure.

### Response Envelope
```json
{
  "prompt_version": "2.0",
  "outcome": "ACT | CLARIFY | DECLINE",
  "outcome_reason": "one sentence",
  "task": { "...Task object or null..." },
  "clarification_needed": "question string or null",
  "schema_notes": "observations or null"
}
```

### Task Object
```json
{
  "verb": "close_positions|modify_position|place_pending|place_market|cancel_order|partial_close|query|watch|cancel_task|modify_order|trail_stop|close_by",
  "noun": "positions|orders|history|account|task",
  "filters": {
    "magic?": "number",
    "symbol?": "string -- always uppercase e.g. XAUUSD",
    "ticket?": "number",
    "profit_lt?": "number",
    "profit_gte?": "number",
    "type?": "buy|sell|buy_limit|sell_limit|buy_stop|sell_stop",
    "comment?": "string",
    "time_after?": "ISO 8601 datetime"
  },
  "trigger?": {
    "type": "profit_gte|profit_lt|price_crosses|new_position_opened|tick",
    "value?": "number",
    "ticket?": "number",
    "magic?": "number"
  },
  "on_trigger?": ["array of Task objects -- all fire simultaneously"],
  "cancel_condition?": {
    "type": "price_below_entry|price_above_entry|time_elapsed",
    "value?": "number"
  },
  "modifications?": {
    "sl_type?": "breakeven|price|pips",
    "sl_value?": "number",
    "tp_type?": "price|pips",
    "tp_value?": "number",
    "reduce_volume_pct?": "number 0-100",
    "trail_pips?": "number -- for trail_stop verb"
  },
  "pending_order?": {
    "type": "buy_limit|sell_limit|buy_stop|sell_stop",
    "entry_offset_pips?": "number -- negative=below, positive=above current price",
    "entry_price?": "number",
    "sl_pips?": "number",
    "tp_pips?": "number",
    "volume?": "number lots",
    "expiration_hours?": "number -- hours until order expires (e.g. 4.0 = 4 hours)"
  },
  "market_order?": {
    "direction": "buy|sell",
    "volume": "number lots -- REQUIRED",
    "sl_pips?": "number",
    "tp_pips?": "number"
  },
  "query_operation?": {
    "aggregate": "sum|count|avg|list",
    "field": "profit|volume|symbol|ticket|type|swap"
  },
  "notification?": {
    "channel": "telegram",
    "message_template": "string -- supports {ticket} {symbol} {profit} {volume} {type} {magic}"
  },
  "is_conditional": "boolean",
  "is_persistent": "boolean",
  "requires_confirmation": "boolean"
}
```

---

## CONVERSATION STATE MACHINE

Three states, managed in State.mqh:

```
IDLE
  |-- slash command -> handle -> IDLE
  |-- new instruction -> POST Claude ->
        ACT  + one-shot  + LIVE     -> execute -> IDLE
        ACT  + one-shot  + TRAINING -> propose -> PENDING_REVIEW
        ACT  + persistent + LIVE    -> add to queue -> IDLE
        ACT  + persistent + TRAINING -> add to queue -> PENDING_REVIEW
        CLARIFY                     -> ask question -> PENDING_CLARIFY
        DECLINE                     -> notify -> IDLE

PENDING_REVIEW (TRAINING mode only)
  |-- approval keyword (yes/ok/correct/approved/go/execute/confirm/do it)
  |       one-shot: execute -> IDLE
  |       persistent: already in queue, confirm activation -> IDLE
  |-- flag keyword (wrong/flag/incorrect/no/bad/skip/discard/cancel)
  |       remove from queue if persistent, log for prompt review -> IDLE
  |-- any other text -> treat as correction, re-POST Claude -> (loops)

PENDING_CLARIFY (both modes)
  |-- any reply -> append to original instruction -> re-POST Claude -> (loops)
```

**Approval keywords:** yes, ok, correct, approved, go, execute, confirm, do it
**Flag keywords:** wrong, flag, incorrect, no, bad, skip, discard, cancel

---

## SLASH COMMANDS

| Command | Action |
|---------|--------|
| `/live` | Switch to LIVE mode (immediate execution) |
| `/train` | Switch to TRAINING mode (propose before execute) |
| `/tasks` | List all active monitoring tasks |
| `/status` | Account summary (balance, equity, margin, positions, tasks) |
| `/stop` | Cancel ALL monitoring tasks (does NOT touch MT5 positions/orders) |

---

## OPERATING MODES

**TRAINING (default on startup):** Claude extracts intent -> EA proposes action -> operator approves/corrects/flags -> EA executes. Safe for learning the system.

**LIVE:** Claude extracts intent -> EA executes immediately on ACT. For production use.

Mode toggle: `/live` and `/train` commands. EA always starts in TRAINING.

---

## EA INPUT PARAMETERS

| Parameter | Purpose |
|-----------|---------|
| `InpClaudeApiKey` | Anthropic API key |
| `InpTelegramToken` | Telegram Bot token (from @BotFather) |
| `InpTelegramChatId` | Operator chat ID (from @userinfobot) |
| `InpPollIntervalMs` | Telegram poll interval in ms (default 1000) |
| `InpStartupMode` | EA_MODE_TRAINING or EA_MODE_LIVE |
| `InpConfirmThreshold` | P&L threshold for auto-confirmation ($, default 500) |
| `InpSystemPrompt` | Full Claude system prompt (paste from SystemPrompt.mqh) |

---

## EXECUTOR IMPLEMENTATION PATTERN

All live primitives follow this pattern -- use it for remaining stubs:

```mql5
bool CExecutor::Execute_Something(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";   // ALWAYS use nl variable for newlines in strings -- never literal \n

   // 1. Iterate positions/orders
   // 2. Apply filters (PositionMatchesFilters helper available)
   // 3. Build MqlTradeRequest
   // 4. OrderSend(req, res)
   // 5. Log success/failure with retcode
   // 6. Build r.summary using nl variable
   // 7. Set r.success = (failed == 0)
   // 8. return r.success
  }
```

**Critical:** Never use literal newline characters or multiline string concatenation in MQL5 string literals. Always use `string nl = "\n"` and concatenate with `+`. This was the source of multiple compile failures.

**PipsToPrice helper:** Already implemented in CExecutor -- converts pip count to price distance accounting for 3/5 digit brokers.

**PositionMatchesFilters helper:** Already implemented -- pass ticket + STaskFilters, returns bool.

---

## NEW PRIMITIVES -- IMPLEMENTATION NOTES

### modify_order (TRADE_ACTION_MODIFY)
- Iterates pending orders, applies filters (ticket/magic/symbol/type)
- Changes entry price (absolute or offset pips from current entry), SL, TP, expiration
- SL/TP in pips are calculated relative to the (possibly new) entry price
- Expiration via `expiration_hours` -> `ORDER_TIME_SPECIFIED`

### trail_stop (persistent tick-based)
- Uses `modifications.trail_pips` for trail distance
- On each tick: computes ideal SL from current BID (BUY) or ASK (SELL) minus trail distance
- **Never moves SL backwards** -- only tightens the stop
- BUY: ideal_sl = BID - trail_dist, only move if ideal_sl > current_sl
- SELL: ideal_sl = ASK + trail_dist, only move if ideal_sl < current_sl
- Expected usage: persistent task with TRIGGER_TICK

### close_by (TRADE_ACTION_CLOSE_BY)
- Requires symbol filter -- pairs BUY and SELL positions on that symbol
- Collects all BUY tickets and SELL tickets matching filters
- Pairs them 1:1 and sends TRADE_ACTION_CLOSE_BY for each pair
- Reports pairs closed and any remaining unmatched positions
- Saves spread vs closing each at market

### place_pending expiration
- New field: `expiration_hours` in pending_order object
- EA calculates `TimeCurrent() + hours * 3600` and sets `ORDER_TIME_SPECIFIED`
- Also available on modify_order for changing expiration of existing orders

---

## SCOPE BOUNDARIES -- ALWAYS DECLINE

| Category | Examples |
|----------|---------|
| Trading judgment | "rebalance my portfolio", "reduce my risk exposure" |
| Strategy | "find me good trades", "tell me what to buy" |
| Predictive | "close before the news", "exit if things go bad" |
| Superlative ranking | "close my biggest losing position" |
| Meta-configuration | "be more conservative", "tighten everything up" |
| Hedging | "hedge my gold exposure" -- always DECLINE, never CLARIFY |

---

## STEP 6 -- END-TO-END DEMO TEST

Once all primitives are live:
1. Open several demo positions on different symbols
2. Test each primitive via natural language
3. Test compound tasks (on_trigger array)
4. Test persistent watch tasks (add, verify in /tasks, let trigger fire)
5. Verify TRAINING -> LIVE mode switch works mid-session
6. Test /stop clears queue without touching positions

---

## WHAT RICHARD CARES ABOUT

- **Architectural clarity** -- explain the why, not just the what
- **Clean separation of concerns** -- Claude extracts intent, EA executes, never blurred
- **Safe by default** -- TRAINING mode on startup, confirm before destructive actions
- **Iterative build** -- one primitive at a time, tested before moving on
- **Real trader instructions** -- test cases came from actual workflow
- **High energy** -- match it

---

*Handoff document -- Richard & Claude (claude.ai) design + build session*
*Date: March 2026 · EA version: 5.0-partial · query + modify_position live*
