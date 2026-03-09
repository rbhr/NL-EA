# NL_EA — Step 4 Skeleton
## World Tech Edge · MT5 Natural Language Expert Advisor

---

## Files in This Package

| File | Purpose |
|------|---------|
| `NL_EA.mq5` | Main EA — OnInit, OnDeinit, OnTick, OnTimer, all message routing |
| `State.mqh` | EA mode (LIVE/TRAINING) + conversation state machine |
| `TaskQueue.mqh` | STask struct, queue management, trigger evaluation |
| `JsonParser.mqh` | Claude JSON response → STask (wraps JAson library) |
| `Claude.mqh` | Claude API POST via WebRequest |
| `Telegram.mqh` | Telegram poll (getUpdates) + send (sendMessage) via WebRequest |
| `Executor.mqh` | Primitive dispatcher — **ALL STUBS in Step 4, safe on live accounts** |

---

## Installation

### 1. Install JAson library
- Download JAson.mqh from: https://www.mql5.com/en/code/13663
- Place in: `MQL5/Include/JAson.mqh`

### 2. Copy EA files
- Copy all 6 files into: `MQL5/Experts/NL_EA/`
- Structure should be:
  ```
  MQL5/Experts/NL_EA/
    NL_EA.mq5
    State.mqh
    TaskQueue.mqh
    JsonParser.mqh
    Claude.mqh
    Telegram.mqh
    Executor.mqh
  ```

### 3. Allow URLs in MT5
In MT5: **Tools → Options → Expert Advisors → Allowed URLs**
Add both:
```
https://api.anthropic.com
https://api.telegram.org
```

### 4. Compile
- Open NL_EA.mq5 in MetaEditor
- Press F7 to compile
- Should compile with 0 errors, 0 warnings

### 5. Configure EA Inputs
| Parameter | Value |
|-----------|-------|
| Claude API Key | From console.anthropic.com |
| Telegram Bot Token | From @BotFather |
| Telegram Chat ID | Your personal Telegram chat ID |
| Poll Interval | 1000 (ms) |
| Startup Mode | TRAINING (recommended) |
| Confirmation Threshold | 500.0 |
| System Prompt | Paste full content of system-prompt-runtime.txt |

**Getting your Telegram Chat ID:** Message @userinfobot on Telegram — it replies with your chat ID.

---

## Step 4 Behaviour (Stubs Active)

The EA is fully functional as a skeleton:
- All Telegram polling and sending works
- All slash commands work (/live, /train, /tasks, /status, /stop)
- TRAINING mode propose/approve/flag flow works
- CLARIFY flow works
- Task queue evaluation runs on every tick
- **Executor returns [STUB] messages** — no actual trades placed

This means Step 4 is safe to load on a live account for integration testing.

---

## Step 5 Plan

Replace stubs in Executor.mqh one at a time, in this order:
1. `query` — read-only, safest to test first
2. `modify_position` — SL/TP changes, no volume risk
3. `cancel_order` — removes pending orders
4. `close_positions` — closes live positions
5. `partial_close` — reduces position volume
6. `place_pending` — places new orders

Test each primitive on demo account before activating the next.

---

## Architecture Reminder

```
Claude's job:  intent extraction only
EA's job:      execution only
These never cross.
```

Claude never sees MT5 state. The EA never makes trading decisions.
