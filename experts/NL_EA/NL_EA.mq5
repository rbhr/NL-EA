//+------------------------------------------------------------------+
//| NL_EA.mq5  --  Natural Language Expert Advisor                  |
//| World Tech Edge  --  MT5 NL-EA  --  Step 4                      |
//|                                                                  |
//| OnTimer() -- polls Telegram, processes messages                  |
//| OnTick()  -- evaluates task queue triggers                       |
//|                                                                  |
//| DEPENDENCY: JAson.mqh in MQL5/Include/                          |
//| Download: https://www.mql5.com/en/code/13663                    |
//|                                                                  |
//| ALLOWED URLS (Tools > Options > Expert Advisors):               |
//|   https://api.anthropic.com                                      |
//|   https://api.telegram.org                                       |
//+------------------------------------------------------------------+


#property copyright "World Tech Edge"
#property version   "4.0"
#property strict

#include "State.mqh"
#include "TaskQueue.mqh"
#include "JsonParser.mqh"
#include "Claude.mqh"
#include "Telegram.mqh"
#include "Executor.mqh"
#include "SystemPrompt.mqh"

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input string       InpClaudeApiKey     = "";              // Claude API Key
input string       InpTelegramToken    = "";              // Telegram Bot Token
input string       InpTelegramChatId   = "";              // Telegram Chat ID
input int          InpPollIntervalMs   = 1000;            // Poll interval (ms)
input ENUM_EA_MODE InpStartupMode      = EA_MODE_TRAINING;// Startup mode
input double       InpConfirmThreshold = 500.0;           // P&L confirm threshold ($)
input long         InpMagicNumber      = 0;               // Default Magic Number
input string       InpOrderComment     = "NL_EA";         // Default Order Comment
input bool         InpForceUnlock      = false;           // Force unlock on startup

//+------------------------------------------------------------------+
//| Globals                                                          |
//+------------------------------------------------------------------+
CState     g_state;
CTaskQueue g_queue;
CClaude    g_claude;
CTelegram  g_telegram;
CExecutor  g_executor;

//+------------------------------------------------------------------+
int OnInit()
  {
   Print("=== NL_EA v4.0 init ===");

   if(InpClaudeApiKey   == "") { Alert("NL_EA: Claude API Key required");   return INIT_PARAMETERS_INCORRECT; }
   if(InpTelegramToken  == "") { Alert("NL_EA: Telegram Bot Token required");return INIT_PARAMETERS_INCORRECT; }
   if(InpTelegramChatId == "") { Alert("NL_EA: Telegram Chat ID required");  return INIT_PARAMETERS_INCORRECT; }

   long chat_id = StringToInteger(InpTelegramChatId);
   g_telegram.Init(InpTelegramToken, chat_id);

   //── Account lock check ─────────────────────────────────────
   long my_account = AccountInfoInteger(ACCOUNT_LOGIN);
   string my_broker = AccountInfoString(ACCOUNT_COMPANY);
   long locked_account = 0;
   long stale_pin_id   = 0;

   if(g_telegram.GetPinnedLockAccount(locked_account, stale_pin_id))
     {
      if(locked_account != my_account)
        {
         if(InpForceUnlock)
           {
            Print("NL_EA: Force-unlocking channel from account ", locked_account);
           }
         else
           {
            string err = "NL_EA REFUSED: Channel locked by account " +
                         IntegerToString(locked_account) +
                         "\nThis EA is on account " + IntegerToString(my_account) +
                         " (" + my_broker + ")" +
                         "\nUnload the other EA first, or set Force Unlock = true";
            Alert(err);
            g_telegram.Send(err);
            return INIT_FAILED;
           }
        }
     }

   //── Acquire lock: send + pin ───────────────────────────────
   string lock_text = "NL_EA_LOCK:" + IntegerToString(my_account) +
                      "\nAccount: " + IntegerToString(my_account) +
                      " (" + my_broker + ")" +
                      "\nSince: " + TimeToString(TimeGMT(), TIME_DATE | TIME_SECONDS) + " UTC";
   long lock_id = g_telegram.SendAndGetId(lock_text);
   if(lock_id > 0)
     {
      g_telegram.PinMessage(lock_id);
      g_telegram.SetLockMsgId(lock_id);
      Print("NL_EA: Channel locked. Pin msg_id=", lock_id);
     }
   else
      Print("NL_EA: WARNING - could not send lock message");

   //── Continue normal init ───────────────────────────────────
   g_claude.Init(InpClaudeApiKey, CLAUDE_SYSTEM_PROMPT);
   g_executor.Init(InpMagicNumber, InpOrderComment);

   if(InpStartupMode == EA_MODE_LIVE) g_state.SetLive();
   else                               g_state.SetTraining();

   if(!EventSetMillisecondTimer(InpPollIntervalMs))
     { Print("NL_EA: Timer failed"); return INIT_FAILED; }

   g_telegram.Send("NL_EA v4.0 online\nMode: " + g_state.ModeLabel() +
                   "\nAccount: " + IntegerToString(my_account) +
                   " (" + my_broker + ")" +
                   "\nSymbol: " + _Symbol + "\nReady for instructions");

   Print("=== NL_EA ready. Mode: ", g_state.ModeLabel(), " ===");
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();

   //── Release account lock ──────────────────────────────────
   long lock_id = g_telegram.LockMsgId();
   if(lock_id > 0)
     {
      g_telegram.UnpinMessage(lock_id);
      Print("NL_EA: Lock released. Unpinned msg_id=", lock_id);
     }

   g_telegram.Send("NL_EA offline (reason " + IntegerToString(reason) + ")\n"
                   "Account: " + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) +
                   " released");
   Print("=== NL_EA deinit reason=", reason, " ===");
  }

//+------------------------------------------------------------------+
void OnTimer()
  {
   STgMessage msgs[];
   int n = g_telegram.Poll(msgs);
   for(int i = 0; i < n; i++) ProcessMessage(msgs[i]);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   int fired[];
   int n = g_queue.EvaluateTriggers(fired);
   for(int i = 0; i < n; i++) HandleTriggeredTask(fired[i]);
  }

//+------------------------------------------------------------------+
void ProcessMessage(STgMessage &msg)
  {
   Print("[EA] Received: ", msg.text, msg.is_callback ? " [callback]" : "");

   //── Inline keyboard callback ─────────────────────────
   if(msg.is_callback)
     {
      g_telegram.AnswerCallbackQuery(msg.callback_query_id);

      if(msg.callback_data == "approve")
        {
         if(!g_state.IsPendingReview()) { g_telegram.Send("No pending action"); return; }
         HandlePendingReview("yes");
         return;
        }
      if(msg.callback_data == "flag")
        {
         if(!g_state.IsPendingReview()) { g_telegram.Send("No pending action"); return; }
         HandlePendingReview("wrong");
         return;
        }
      if(msg.callback_data == "focus_on")  { HandleFocusToggle(true);  return; }
      if(msg.callback_data == "focus_off") { HandleFocusToggle(false); return; }

      Print("[EA] Unknown callback_data: ", msg.callback_data);
      return;
     }

   //── Regular text message ─────────────────────────────
   string text = msg.text;
   if(StringGetCharacter(text, 0) == '/') { HandleCommand(text); return; }

   switch(g_state.ConvState())
     {
      case STATE_PENDING_REVIEW:  HandlePendingReview(text);  break;
      case STATE_PENDING_CLARIFY: HandlePendingClarify(text); break;
      default:                    HandleNewInstruction(text); break;
     }
  }

//+------------------------------------------------------------------+
void HandleNewInstruction(string instruction)
  {
   // Focus mode: prepend ticket context
   if(g_state.FocusActive() && g_state.FocusTicket() > 0)
     {
      instruction = "regarding ticket " + IntegerToString((long)g_state.FocusTicket())
                  + ": " + instruction;
      Print("[EA] Focus context prepended: ", instruction);
     }

   SClaudeResponse resp;
   if(!g_claude.Ask(instruction, resp))
     {
      g_telegram.SendWithMode("CLAUDE API ERROR\nCould not reach Claude. Please try again.", g_state.ModeLabel());
      return;
     }

   if(resp.outcome == "DECLINE")
     {
      g_telegram.SendWithMode("DECLINED\n" + resp.outcome_reason +
                              "\nPlease issue a specific instruction instead.", g_state.ModeLabel());
      g_state.SetIdle();
      return;
     }

   if(resp.outcome == "CLARIFY")
     {
      g_telegram.SendWithMode("CLARIFICATION NEEDED\nInstruction: " + instruction +
                              "\nQuestion: " + resp.clarification, g_state.ModeLabel());
      g_state.SetPendingClarify(instruction);
      return;
     }

   if(resp.outcome == "ACT")
     {
      if(!resp.task_parsed)
        {
         g_telegram.SendWithMode("PARSE ERROR\nClaude returned ACT but task parse failed.", g_state.ModeLabel());
         g_state.SetIdle();
         return;
        }
      DispatchActTask(resp.task, resp.task_json);
      return;
     }

   g_telegram.SendWithMode("UNEXPECTED RESPONSE: " + resp.outcome, g_state.ModeLabel());
   g_state.SetIdle();
  }

//+------------------------------------------------------------------+
void DispatchActTask(STask &task, string task_json)
  {
   if(task.verb == VERB_CANCEL_TASK) { HandleCancelTask(task); return; }

   if(task.is_persistent)
     {
      if(g_state.IsLive())
        {
         int id = g_queue.Add(task);
         g_telegram.SendWithMode("TASK CREATED -- Task #" + IntegerToString(id) + "\n"
                                 + BuildTaskSummary(task), g_state.ModeLabel());
        }
      else
        {
         int id = g_queue.Add(task, false);
         string prop_text = "[TRAINING]\nPROPOSED TASK -- Task #" + IntegerToString(id) + "\n"
                           + BuildTaskSummary(task) + "\n\nTap or type a correction:";
         string btns[2][2];
         btns[0][0] = "Activate";  btns[0][1] = "approve";
         btns[1][0] = "Discard";   btns[1][1] = "flag";
         g_telegram.SendWithButtons(prop_text, btns, 2);
         g_state.SetPendingReview(task_json, id);
        }
      return;
     }

   if(g_state.IsLive())
     {
      SExecResult result;
      g_executor.Execute(task, result);
      // Focus mode: capture ticket from market orders
      if(g_state.FocusActive() && result.success && result.opened_ticket > 0)
        {
         g_state.SetFocusTicket(result.opened_ticket);
         result.summary += "\n\nFocus ticket: #" + IntegerToString((long)result.opened_ticket);
        }
      g_telegram.SendWithMode(result.summary, "LIVE");
      g_state.SetIdle();
     }
   else
     {
      string prop_text = "[TRAINING]\nPROPOSED ACTION\n" + BuildTaskSummary(task)
                        + "\n\nTap or type a correction:";
      string btns[2][2];
      btns[0][0] = "Execute";  btns[0][1] = "approve";
      btns[1][0] = "Wrong";    btns[1][1] = "flag";
      g_telegram.SendWithButtons(prop_text, btns, 2);
      g_state.SetPendingReview(task_json, -99);
     }
  }

//+------------------------------------------------------------------+
void HandlePendingReview(string text)
  {
   if(g_state.IsApproval(text))
     {
      string pjson = g_state.PendingTaskJson();
      int    pid   = g_state.PendingTaskId();
      STask task;
      CJsonParser parser;
      if(!parser.ParseTask(pjson, task))
        {
         g_telegram.Send("ERROR: could not parse pending task");
         g_state.SetIdle();
         return;
        }
      if(pid > 0)
        {
         g_telegram.SendWithMode("Task #" + IntegerToString(pid) + " ACTIVATED\n"
                                 + BuildTaskSummary(task), "TRAINING");
         g_state.SetIdle();
         return;
        }
      SExecResult result;
      g_executor.Execute(task, result);
      // Focus mode: capture ticket from market orders
      if(g_state.FocusActive() && result.success && result.opened_ticket > 0)
        {
         g_state.SetFocusTicket(result.opened_ticket);
         result.summary += "\n\nFocus ticket: #" + IntegerToString((long)result.opened_ticket);
        }
      g_telegram.SendWithMode(result.summary, "TRAINING");
      g_state.SetIdle();
      return;
     }

   if(g_state.IsFlag(text))
     {
      int pid = g_state.PendingTaskId();
      if(pid > 0) g_queue.Remove(pid);
      g_telegram.SendWithMode("FLAGGED\nProposed action discarded and logged\nReady for next instruction", "TRAINING");
      Print("[EA] Flagged: ", g_state.PendingTaskJson());
      g_state.SetIdle();
      return;
     }

   // Correction -- re-run through Claude
   int pid = g_state.PendingTaskId();
   if(pid > 0) g_queue.Remove(pid);
   g_state.SetIdle();
   HandleNewInstruction(text);
  }

//+------------------------------------------------------------------+
void HandlePendingClarify(string answer)
  {
   string combined = g_state.PendingInstruction() + " -- clarification: " + answer;
   g_state.SetIdle();
   HandleNewInstruction(combined);
  }

//+------------------------------------------------------------------+
void HandleTriggeredTask(int task_id)
  {
   STask task;
   if(!g_queue.GetById(task_id, task))
     { Print("[EA] Triggered task #", task_id, " not found"); return; }

   Print("[EA] Task #", task_id, " triggered");
   SExecResult result;
   g_executor.Execute(task, result);
   g_telegram.SendWithMode("TASK #" + IntegerToString(task_id) + " TRIGGERED\n" + result.summary,
                           g_state.ModeLabel());
   if(!task.is_persistent) g_queue.Remove(task_id);
  }

//+------------------------------------------------------------------+
void HandleCancelTask(STask &task)
  {
   if(!task.filters.has_ticket && !task.filters.has_magic && !task.filters.has_symbol)
     {
      int count = g_queue.Count();
      g_queue.RemoveAll();
      g_telegram.SendWithMode("ALL TASKS STOPPED\n" + IntegerToString(count)
                              + " tasks cancelled\nMT5 positions unchanged", g_state.ModeLabel());
      g_state.SetIdle();
      return;
     }

   if(task.filters.has_ticket)
     {
      int ids[];
      int n = g_queue.GetActiveIds(ids);
      for(int i = 0; i < n; i++)
        {
         STask t;
         if(g_queue.GetById(ids[i], t) && t.filters.has_ticket && t.filters.ticket == task.filters.ticket)
           {
            g_queue.Remove(ids[i]);
            g_telegram.SendWithMode("Task #" + IntegerToString(ids[i]) + " CANCELLED\n"
                                    + "Was watching ticket " + IntegerToString((long)task.filters.ticket)
                                    + "\nMT5 position unchanged", g_state.ModeLabel());
            g_state.SetIdle();
            return;
           }
        }
      g_telegram.SendWithMode("No active task found watching ticket "
                              + IntegerToString((long)task.filters.ticket), g_state.ModeLabel());
     }
   g_state.SetIdle();
  }

//+------------------------------------------------------------------+
void HandleCommand(string cmd)
  {
   string c = cmd;
   StringToLower(c);
   StringTrimLeft(c);
   StringTrimRight(c);

   if(c == "/start")
     {
      string help = "NL-EA -- Natural Language Expert Advisor\n"
                   + "Mode: " + g_state.ModeLabel() + "\n\n"
                   + "COMMANDS:\n"
                   + "/start    Show this menu\n"
                   + "/live     Auto-execute mode\n"
                   + "/train    Review-first mode\n"
                   + "/status   Account overview\n"
                   + "/tasks    Active task queue\n"
                   + "/stop     Cancel all tasks\n"
                   + "/unlock   Release channel lock\n"
                   + "/focus    Sticky ticket mode\n\n"
                   + "WHAT I CAN DO:\n"
                   + "Open: \"buy 0.5 lots gold SL 30 pips\"\n"
                   + "Close: \"close all losing trades\"\n"
                   + "Modify: \"set SL to breakeven on 123\"\n"
                   + "Pending: \"buy limit gold 20 pips below\"\n"
                   + "Trail: \"trail ticket 123 by 5 pips\"\n"
                   + "Watch: \"notify me when gold > $2000\"\n"
                   + "Query: \"what is my total profit?\"\n"
                   + "Close by: \"close by my XAUUSD\"";
      g_telegram.Send(help);
      return;
     }
   if(c == "/live")
     { g_state.SetLive();     g_telegram.Send("LIVE MODE\nInstructions execute immediately.\nType /train to return to training mode."); return; }
   if(c == "/train")
     { g_state.SetTraining(); g_telegram.Send("TRAINING MODE\nAll actions proposed before executing.\nType /live for automatic execution."); return; }
   if(c == "/tasks")
     { g_telegram.Send(g_queue.SummaryText()); return; }
   if(c == "/status")
     { g_telegram.Send(BuildStatusText()); return; }
   if(c == "/stop")
     {
      int count = g_queue.Count();
      g_queue.RemoveAll();
      g_state.SetIdle();
      g_telegram.Send("ALL TASKS STOPPED\n" + IntegerToString(count)
                      + " tasks cancelled\nMT5 positions unchanged\nEA idle");
      return;
     }
   if(c == "/unlock")
     {
      long own_lock = g_telegram.LockMsgId();
      if(own_lock > 0)
        {
         g_telegram.UnpinMessage(own_lock);
         g_telegram.SetLockMsgId(0);
        }
      long stale_acct = 0, stale_id = 0;
      if(g_telegram.GetPinnedLockAccount(stale_acct, stale_id))
        {
         if(stale_id > 0) g_telegram.UnpinMessage(stale_id);
        }
      g_telegram.Send("CHANNEL UNLOCKED\nAny account can now start an EA on this channel.");
      return;
     }
   if(c == "/focus" || c == "/focus on" || c == "/focus off")
     {
      if(c == "/focus on")  { HandleFocusToggle(true);  return; }
      if(c == "/focus off") { HandleFocusToggle(false); return; }

      // No argument -- show status + toggle buttons
      string ft_text = "FOCUS MODE\nCurrently: " + (g_state.FocusActive() ? "ON" : "OFF");
      if(g_state.FocusActive() && g_state.FocusTicket() > 0)
         ft_text += "\nActive ticket: #" + IntegerToString((long)g_state.FocusTicket());
      ft_text += "\n\nTap to toggle:";
      string btns[2][2];
      btns[0][0] = "ON";   btns[0][1] = "focus_on";
      btns[1][0] = "OFF";  btns[1][1] = "focus_off";
      g_telegram.SendWithButtons(ft_text, btns, 2);
      return;
     }

   g_telegram.Send("Unknown command: " + cmd +
                   "\nAvailable: /start /live /train /tasks /status /stop /unlock /focus");
  }

//+------------------------------------------------------------------+
void HandleFocusToggle(bool on)
  {
   if(on)
     {
      g_state.SetFocusActive(true);
      g_state.SetFocusTicket(0);
      g_telegram.Send("FOCUS ON\nNext trade opened will set the active ticket.\n"
                      "All subsequent instructions will reference that ticket.\n"
                      "Send /focus off to disable.");
     }
   else
     {
      g_state.ClearFocus();
      g_telegram.Send("FOCUS OFF\nInstructions interpreted without ticket context.");
     }
  }

//+------------------------------------------------------------------+
string BuildTaskSummary(STask &task)
  {
   string verb = "unknown";
   switch(task.verb)
     {
      case VERB_CLOSE_POSITIONS: verb="close_positions"; break;
      case VERB_MODIFY_POSITION: verb="modify_position"; break;
      case VERB_PLACE_PENDING:   verb="place_pending";   break;
      case VERB_CANCEL_ORDER:    verb="cancel_order";    break;
      case VERB_PARTIAL_CLOSE:   verb="partial_close";   break;
      case VERB_QUERY:           verb="query";           break;
      case VERB_WATCH:           verb="watch";           break;
      case VERB_PLACE_MARKET:    verb="place_market";    break;
      case VERB_MODIFY_ORDER:    verb="modify_order";    break;
      case VERB_TRAIL_STOP:      verb="trail_stop";      break;
      case VERB_CLOSE_BY:        verb="close_by";        break;
      case VERB_CANCEL_TASK:     verb="cancel_task";     break;
     }
   string s = "Verb: " + verb;
   if(task.filters.has_symbol) s += "  Symbol: " + task.filters.symbol;
   if(task.filters.has_magic)  s += "  Magic: "  + IntegerToString(task.filters.magic);
   if(task.filters.has_ticket) s += "  Ticket: " + IntegerToString((long)task.filters.ticket);
   if(task.filters.has_task_id) s += "  TaskID: " + IntegerToString(task.filters.task_id);

   //── Modification details ──────────────────────────────────
   if(task.modifications.sl_type != MOD_NONE)
     {
      string sl = "";
      switch(task.modifications.sl_type)
        {
         case MOD_BREAKEVEN: sl = "breakeven"; break;
         case MOD_PRICE:     sl = DoubleToString(task.modifications.sl_value, 5); break;
         case MOD_PIPS:      sl = DoubleToString(task.modifications.sl_value, 1) + " pips"; break;
        }
      s += "\nSL: " + sl;
     }
   if(task.modifications.tp_type != MOD_NONE)
     {
      string tp = "";
      switch(task.modifications.tp_type)
        {
         case MOD_PRICE: tp = DoubleToString(task.modifications.tp_value, 5); break;
         case MOD_PIPS:  tp = DoubleToString(task.modifications.tp_value, 1) + " pips"; break;
         default:        tp = DoubleToString(task.modifications.tp_value, 5); break;
        }
      s += "\nTP: " + tp;
     }
   if(task.modifications.has_trail_pips)
      s += "\nTrail: " + DoubleToString(task.modifications.trail_pips, 1) + " pips";
   if(task.modifications.has_reduce_volume_pct)
      s += "\nReduce: " + DoubleToString(task.modifications.reduce_volume_pct, 0) + "%";

   //── Market order details ──────────────────────────────────
   if(task.market_order.direction != "")
     {
      s += "\nDirection: " + task.market_order.direction;
      if(task.market_order.has_volume)  s += "  Vol: " + DoubleToString(task.market_order.volume, 2);
      if(task.market_order.has_sl_pips) s += "  SL: " + DoubleToString(task.market_order.sl_pips, 1) + " pips";
      if(task.market_order.has_tp_pips) s += "  TP: " + DoubleToString(task.market_order.tp_pips, 1) + " pips";
     }

   //── Pending order details ─────────────────────────────────
   if(task.pending_order.type != PENDING_NONE)
     {
      string ptype = "";
      switch(task.pending_order.type)
        {
         case PENDING_BUY_LIMIT:  ptype = "buy_limit";  break;
         case PENDING_SELL_LIMIT: ptype = "sell_limit"; break;
         case PENDING_BUY_STOP:   ptype = "buy_stop";   break;
         case PENDING_SELL_STOP:  ptype = "sell_stop";  break;
        }
      s += "\nOrder: " + ptype;
      if(task.pending_order.has_entry_price)       s += "  Entry: " + DoubleToString(task.pending_order.entry_price, 5);
      if(task.pending_order.has_entry_offset_pips) s += "  Offset: " + DoubleToString(task.pending_order.entry_offset_pips, 1) + " pips";
      if(task.pending_order.has_volume)            s += "  Vol: " + DoubleToString(task.pending_order.volume, 2);
      if(task.pending_order.has_sl_pips)           s += "  SL: " + DoubleToString(task.pending_order.sl_pips, 1) + " pips";
      if(task.pending_order.has_tp_pips)           s += "  TP: " + DoubleToString(task.pending_order.tp_pips, 1) + " pips";
      if(task.pending_order.has_expiration_hours)  s += "  Expires: " + DoubleToString(task.pending_order.expiration_hours, 1) + "h";
     }

   //── Query details ─────────────────────────────────────────
   if(task.query_op.aggregate != AGG_NONE)
     {
      string agg = "", fld = "";
      switch(task.query_op.aggregate) { case AGG_SUM: agg="sum"; break; case AGG_COUNT: agg="count"; break; case AGG_AVG: agg="avg"; break; case AGG_LIST: agg="list"; break; }
      switch(task.query_op.field)     { case FIELD_PROFIT: fld="profit"; break; case FIELD_VOLUME: fld="volume"; break; case FIELD_SYMBOL: fld="symbol"; break; case FIELD_TICKET: fld="ticket"; break; case FIELD_TYPE: fld="type"; break; case FIELD_SWAP: fld="swap"; break; }
      s += "\nQuery: " + agg + "(" + fld + ")";
     }

   //── Trigger ───────────────────────────────────────────────
   if(task.trigger.type != TRIGGER_NONE)
     {
      s += "\nTrigger: ";
      switch(task.trigger.type)
        {
         case TRIGGER_PROFIT_GTE:     s += "profit >= $" + DoubleToString(task.trigger.value,2); break;
         case TRIGGER_PROFIT_LT:      s += "profit < $"  + DoubleToString(task.trigger.value,2); break;
         case TRIGGER_NEW_POS_OPENED: s += "new position opened"; break;
         case TRIGGER_PRICE_CROSSES:  s += "price crosses " + DoubleToString(task.trigger.value,5); break;
         case TRIGGER_TICK:           s += "every tick"; break;
         default: s += "?";
        }
     }

   if(task.has_on_trigger)  s += "\nCompound: yes";
   s += "\nPersistent: " + (task.is_persistent ? "yes" : "no");
   return s;
  }

//+------------------------------------------------------------------+
string BuildStatusText()
  {
   string s = "ACCOUNT STATUS\nMode: " + g_state.ModeLabel() + "\n\n";
   s += "Balance:     $" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE),    2) + "\n";
   s += "Equity:      $" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY),     2) + "\n";
   s += "Free Margin: $" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE),2) + "\n";
   if(AccountInfoDouble(ACCOUNT_MARGIN) > 0)
      s += "Margin Level:  " + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL),1) + "%\n";
   s += "\nOpen positions: " + IntegerToString(PositionsTotal());
   s += "\nPending orders: " + IntegerToString(OrdersTotal());
   s += "\nActive tasks:   " + IntegerToString(g_queue.Count());
   return s;
  }
