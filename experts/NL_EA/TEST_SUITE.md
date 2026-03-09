# MT5 NL-EA System Prompt Test Suite
## Version 2.1 -- 39 Cases

This file contains the full regression test suite for the Claude system prompt.
Run these against the prompt in SystemPrompt.mqh to verify correct behaviour
before any prompt changes.

---

## HOW TO RUN

Send each instruction to Claude with the system prompt active.
Check `outcome`, `verb`, and `noun` against expected values.
The React test runner artifact (mt5-test-runner.jsx) automates this --
if you have access to it, use that. Otherwise test manually via the EA.

---

## PASS CRITERIA

| Field | Must match |
|-------|-----------|
| `outcome` | Exactly as specified |
| `verb` | Exactly as specified (ACT cases only) |
| `noun` | Exactly as specified (ACT cases only) |
| JSON | Valid, parseable, no prose outside the object |

---

## TEST CASES

### ONE-SHOT ACT CASES (T01-T10)

| ID | Instruction | Expected outcome | Expected verb | Expected noun | Notes |
|----|-------------|-----------------|---------------|---------------|-------|
| T01 | close all losing trades with magic 94737 | ACT | close_positions | positions | filters: magic=94737, profit_lt=0 |
| T02 | close all buy positions on EURUSD | ACT | close_positions | positions | filters: symbol=EURUSD, type=buy |
| T03 | cancel all pending orders on gold | ACT | cancel_order | orders | filters: symbol=XAUUSD |
| T04 | cancel order ticket 987654 | ACT | cancel_order | orders | filters: ticket=987654 |
| T05 | sum the net P&L for all trades with magic 3848 | ACT | query | positions | query_operation: aggregate=sum, field=profit |
| T06 | how many open gold positions do I have | ACT | query | positions | query_operation: aggregate=count |
| T07 | what is my current equity | ACT | query | account | noun=account |
| T08 | move stop loss to breakeven on all XAUUSD positions | ACT | modify_position | positions | modifications: sl_type=breakeven |
| T09 | close everything | ACT | close_positions | positions | requires_confirmation=true |
| T10 | stop watching everything | ACT | cancel_task | task | empty filters = cancel all tasks |

### CONDITIONAL / PERSISTENT ACT CASES (T11-T18)

| ID | Instruction | Expected outcome | Expected verb | Expected noun | Notes |
|----|-------------|-----------------|---------------|---------------|-------|
| T11 | when ticket 123456789 is in $100 profit reduce volume 10% and set SL to breakeven | ACT | watch | positions | Compound: on_trigger has 2 sub-tasks. Outer verb=watch. is_conditional=true, is_persistent=true |
| T12 | buy gold limit 20 pips below current price SL 5 pips cancel if price drops below entry | ACT | place_pending | orders | pending_order: type=buy_limit, entry_offset_pips=-20, sl_pips=5. cancel_condition: price_below_entry |
| T13 | notify me whenever magic 88877 opens a new trade | ACT | watch | positions | trigger: new_position_opened, magic=88877. is_persistent=true |
| T14 | alert me on telegram when any GBPUSD position goes into 50 pip profit | ACT | watch | positions | trigger: profit_gte (pip-converted value). notification enabled |
| T15 | set breakeven on ticket 555 when it hits $200 profit | ACT | watch | positions | trigger: profit_gte=200, on_trigger: modify_position sl_type=breakeven |
| T16 | place a sell stop on cable 15 pips below current price with a 10 pip stop | ACT | place_pending | orders | pending_order: type=sell_stop, symbol=GBPUSD, entry_offset_pips=-15, sl_pips=10 |
| T17 | stop watching ticket 123 | ACT | cancel_task | task | filters: ticket=123 -- cancels the task watching that ticket |
| T18 | tell me when any losing trade with magic 7001 gets to minus $500 | ACT | watch | positions | trigger: profit_lt=-500, filters: magic=7001 |

### CLARIFY CASES (T19-T24)

| ID | Instruction | Expected outcome | Notes |
|----|-------------|-----------------|-------|
| T19 | close my small gold positions | CLARIFY | "small" has no defined threshold -- ask for size |
| T20 | tighten up my stops on EURUSD | CLARIFY | "tighten" is relative -- ask for pip value or price |
| T21 | reduce volume on ticket 99 by 500 | CLARIFY | Units ambiguous -- 500 what? lots? units? |
| T22 | close my recent trades | CLARIFY | "recent" undefined -- ask for time window |
| T23 | close half my losing positions | CLARIFY | "half" requires ranking/selection judgment -- ask which ones |
| T24 | move all my stops to breakeven | ACT | modify_position / positions -- "all" is unambiguous. requires_confirmation=true. NOTE: This is ACT not CLARIFY |

### DECLINE CASES (T25-T30)

| ID | Instruction | Expected outcome | Notes |
|----|-------------|-----------------|-------|
| T25 | rebalance my portfolio to reduce overall risk | DECLINE | Trading judgment -- no deterministic filter maps to "rebalance" |
| T26 | find me some good trades to take | DECLINE | Strategy/predictive -- EA never recommends entries |
| T27 | close my positions before the news hits | DECLINE | Predictive -- "before the news" requires timing judgment |
| T28 | be more conservative with my stop losses from now on | DECLINE | Meta-configuration -- no deterministic action maps to "more conservative" |
| T29 | close my biggest losing position | DECLINE | Superlative -- "biggest" requires ranking, no deterministic filter. Always DECLINE not CLARIFY |
| T30 | hedge my gold exposure | DECLINE | Hedging always DECLINE, never CLARIFY -- size/ratio/instrument all require trading judgment |

### NEW VERB ACT CASES (T31-T36)

| ID | Instruction | Expected outcome | Expected verb | Expected noun | Notes |
|----|-------------|-----------------|---------------|---------------|-------|
| T31 | buy 0.5 lots of gold with a 30 pip stop | ACT | place_market | positions | market_order: direction=buy, volume=0.5, sl_pips=30. filters: symbol=XAUUSD |
| T32 | trail my gold positions by 20 pips | ACT | trail_stop | positions | is_conditional=true, is_persistent=true, trigger.type=tick, trail_pips=20, symbol=XAUUSD |
| T33 | close by my XAUUSD positions | ACT | close_by | positions | filters: symbol=XAUUSD. Pairs opposite positions |
| T34 | move my buy limit on gold down 10 pips | ACT | modify_order | orders | pending_order.entry_offset_pips=-10, filters: symbol=XAUUSD, type=buy_limit |
| T35 | set my buy limit on EURUSD to expire in 4 hours | ACT | modify_order | orders | pending_order.expiration_hours=4, filters: symbol=EURUSD, type=buy_limit |
| T36 | sell 1.0 lot EURUSD SL 20 pips TP 40 pips | ACT | place_market | positions | market_order: direction=sell, volume=1.0, sl_pips=20, tp_pips=40 |

### NEW VERB CLARIFY CASES (T37-T39)

| ID | Instruction | Expected outcome | Notes |
|----|-------------|-----------------|-------|
| T37 | buy some gold | CLARIFY | Volume missing -- place_market requires explicit volume |
| T38 | trail my gold positions | CLARIFY | Trail distance (pips) not specified |
| T39 | close by my positions | CLARIFY | Symbol required for close_by -- must CLARIFY |

---

## KNOWN TRICKY CASES

**T11 -- Compound task outer verb:**
The outer verb on compound tasks should be `watch` since the outer task is always monitoring.
Claude was previously returning arbitrary verbs here. If this regresses, add to system prompt:
> "For compound tasks with on_trigger, the outer verb must always be 'watch'."

**T24 -- ACT not CLARIFY:**
"Move all my stops to breakeven" looks like it might need clarification (which positions?)
but "all" is deterministic -- it maps to modify_position with no filters (= all positions).
requires_confirmation=true because it affects multiple positions.
This was a deliberate design decision. Do not change to CLARIFY.

**T29 -- Superlative DECLINE:**
"Biggest", "largest", "worst", "best" always DECLINE.
These require ranking which is trading judgment.
Was failing (returning ACT) before prompt v2.0.1 added the explicit superlative rule.

**T30 -- Hedge DECLINE:**
Hedging always DECLINE, never CLARIFY.
Clarification cannot resolve the judgment problem -- size, ratio, and instrument
all require trading decisions regardless of what the operator clarifies.
Was failing (returning CLARIFY) before prompt v2.0.1 added the explicit hedge rule.

**T32 -- Trail stop lifecycle flags:**
trail_stop MUST have is_conditional=true, is_persistent=true, trigger.type="tick".
These are mandatory because trailing stops run on every tick and never auto-deactivate.
The prompt has an explicit rule for this under NEW VERB RULES.

**T39 -- close_by CLARIFY:**
close_by always requires filters.symbol because the EA pairs opposite positions
on the same symbol. Without a symbol, the EA wouldn't know which positions to pair.
The prompt says: "REQUIRES filters.symbol -- always CLARIFY if symbol is missing"

---

## PROMPT VERSION HISTORY

| Version | Changes |
|---------|---------|
| 2.0 | Initial runtime prompt. 28/30 passing. |
| 2.0.1 | Added explicit superlative DECLINE rule (fixed T29). Added explicit hedge DECLINE rule (fixed T30). Stripped worked examples from runtime prompt to reduce token count. 30/30 passing. |
| 2.1 | Added place_market verb + market_order schema. Added modify_order, trail_stop, close_by verbs. Added trail_pips to modifications. Added expiration_hours to pending_order. Added NEW VERB RULES section. 9 new test cases (T31-T39). 39 total. |

---

## SYMBOL ALIASES BUILT INTO PROMPT

| Alias | Resolves to |
|-------|------------|
| gold | XAUUSD |
| silver | XAGUSD |
| oil | USOIL |
| cable | GBPUSD |
| fiber | EURUSD |
| aussie | AUDUSD |
| kiwi | NZDUSD |
| loonie | USDCAD |
| swissy | USDCHF |
| yen | USDJPY |
| nasdaq | NAS100 |
| dow | US30 |
| sp500 | US500 |

---

*Test suite v2.1 -- Richard & Claude (Claude Code)*
*March 2026 -- 39 cases against SystemPrompt.mqh v2.1*
