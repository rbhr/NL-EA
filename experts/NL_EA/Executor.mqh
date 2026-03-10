//+------------------------------------------------------------------+
//| Executor.mqh  --  Primitive dispatcher                          |
//| World Tech Edge  --  MT5 NL-EA  --  Step 5+                     |
//|                                                                  |
//| All primitives LIVE:                                             |
//|   query          account, positions, history                     |
//|   modify_position breakeven, pips, price                        |
//|   cancel_order    ticket/magic/symbol/type filters               |
//|   place_market    buy/sell, SL/TP pips, magic/comment            |
//|   close_positions opposite deal at market, realised P&L          |
//|   partial_close   volume split, step/min validation              |
//|   place_pending   limit/stop, entry/offset, SL/TP, expiration   |
//|   watch           template expansion, position placeholders      |
//|   modify_order    TRADE_ACTION_MODIFY on pending orders          |
//|   trail_stop      persistent tick-based trailing SL              |
//|   close_by        TRADE_ACTION_CLOSE_BY opposite positions       |
//+------------------------------------------------------------------+
#ifndef NL_EA_EXECUTOR_MQH
#define NL_EA_EXECUTOR_MQH

#include "TaskQueue.mqh"
#include "JsonParser.mqh"

struct SExecResult
  {
   bool   success;
   bool   silent;     // true = don't notify Telegram (e.g. trail_stop unchanged)
   string summary;
   void Clear() { success=false; silent=false; summary=""; }
  };

class CExecutor
  {
public:
   void Init(long default_magic, string default_comment);
   bool Execute(STask &task, SExecResult &result);

private:
   long   m_default_magic;
   string m_default_comment;
   bool Execute_ClosePositions(STask &task, SExecResult &r);
   bool Execute_ModifyPosition(STask &task, SExecResult &r);
   bool Execute_PlacePending  (STask &task, SExecResult &r);
   bool Execute_CancelOrder   (STask &task, SExecResult &r);
   bool Execute_PartialClose  (STask &task, SExecResult &r);
   bool Execute_Query         (STask &task, SExecResult &r);
   bool Execute_Watch         (STask &task, SExecResult &r);
   bool Execute_PlaceMarket   (STask &task, SExecResult &r);
   bool Execute_ModifyOrder   (STask &task, SExecResult &r);
   bool Execute_TrailStop     (STask &task, SExecResult &r);
   bool Execute_CloseBy       (STask &task, SExecResult &r);

   bool   PositionMatchesFilters(ulong ticket, STaskFilters &f);
   double PipsToPrice(string symbol, double pips);
   ENUM_ORDER_TYPE_FILLING GetFilling(string symbol);
  };

//+------------------------------------------------------------------+
void CExecutor::Init(long default_magic, string default_comment)
  {
   m_default_magic   = default_magic;
   m_default_comment = default_comment;
   Print("[Exec] Init magic=", m_default_magic, " comment=", m_default_comment);
  }

//+------------------------------------------------------------------+
bool CExecutor::Execute(STask &task, SExecResult &result)
  {
   result.Clear();

   // Compound task: on_trigger array present -- dispatch all sub-tasks
   if(task.has_on_trigger && StringLen(task.on_trigger_json) > 0)
     {
      Print("[Exec] Compound task -- dispatching sub-tasks");
      CJAVal arr;
      if(!arr.Deserialize(task.on_trigger_json))
        {
         result.success = false;
         result.summary = "FAILED: could not parse compound sub-tasks";
         return false;
        }
      string combined = "";
      bool   all_ok   = true;
      int    n        = arr.Size();
      for(int i = 0; i < n; i++)
        {
         STask sub;
         sub.Clear();
         CJsonParser p;
         if(!p.ParseTask(arr[i].Serialize(), sub)) { all_ok=false; continue; }
         SExecResult sr;
         Execute(sub, sr);
         combined += sr.summary + "\n";
         if(!sr.success) all_ok = false;
        }
      result.success = all_ok;
      result.summary = combined;
      return all_ok;
     }

   switch(task.verb)
     {
      case VERB_CLOSE_POSITIONS: return Execute_ClosePositions(task, result);
      case VERB_MODIFY_POSITION: return Execute_ModifyPosition(task, result);
      case VERB_PLACE_PENDING:   return Execute_PlacePending(task, result);
      case VERB_CANCEL_ORDER:    return Execute_CancelOrder(task, result);
      case VERB_PARTIAL_CLOSE:   return Execute_PartialClose(task, result);
      case VERB_QUERY:           return Execute_Query(task, result);
      case VERB_WATCH:           return Execute_Watch(task, result);
      case VERB_PLACE_MARKET:    return Execute_PlaceMarket(task, result);
      case VERB_MODIFY_ORDER:    return Execute_ModifyOrder(task, result);
      case VERB_TRAIL_STOP:      return Execute_TrailStop(task, result);
      case VERB_CLOSE_BY:        return Execute_CloseBy(task, result);
      case VERB_CANCEL_TASK:
         result.success = true;
         result.summary = "cancel_task handled by EA";
         return true;
      default:
         result.success = false;
         result.summary = "FAILED: unknown verb";
         return false;
     }
  }

//+------------------------------------------------------------------+
// Primitive implementations -- Step 5 complete
//+------------------------------------------------------------------+

bool CExecutor::Execute_ClosePositions(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";
   int    closed  = 0;
   int    failed  = 0;
   double pnl_sum = 0;
   string log_str = "";

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionMatchesFilters(ticket, task.filters)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double profit = PositionGetDouble(POSITION_PROFIT);
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int    digits  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      //--- Close = opposite direction at market
      //--- BUY position closes at BID, SELL position closes at ASK
      bool   close_buy = (pos_type == POSITION_TYPE_BUY);
      double price     = close_buy ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(symbol, SYMBOL_ASK);

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action       = TRADE_ACTION_DEAL;
      req.position     = ticket;
      req.symbol       = symbol;
      req.volume       = volume;
      req.type         = close_buy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price        = NormalizeDouble(price, digits);
      req.deviation    = 10;
      req.type_filling = GetFilling(symbol);

      if(OrderSend(req, res))
        {
         closed++;
         pnl_sum += profit;
         string dir = close_buy ? "BUY" : "SELL";
         log_str += nl + "  #" + IntegerToString((long)ticket)
                    + " " + symbol + " " + dir
                    + " vol=" + DoubleToString(volume, 2)
                    + " P&L=" + DoubleToString(profit, 2);
         Print("[Exec] Closed #", ticket, " ", symbol, " P&L=", profit);
        }
      else
        {
         failed++;
         Print("[Exec] Close FAILED #", ticket, " retcode=", res.retcode, " comment=", res.comment);
         log_str += nl + "  #" + IntegerToString((long)ticket) + " FAILED retcode=" + IntegerToString(res.retcode);
        }
     }

   if(closed == 0 && failed == 0)
     {
      //── Fallback: if ticket filter set, try cancel_order ────
      if(task.filters.has_ticket)
        {
         Print("[Exec] No position matched ticket ", (long)task.filters.ticket, " -- trying cancel_order fallback");
         return Execute_CancelOrder(task, r);
        }
      r.success = true;
      r.summary = "CLOSE POSITIONS: no positions matched filters";
      return true;
     }

   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   r.success = (failed == 0);
   r.summary  = "CLOSE POSITIONS RESULT" + nl;
   r.summary += "Closed: " + IntegerToString(closed);
   if(failed > 0) r.summary += "  Failed: " + IntegerToString(failed);
   r.summary += nl + "Realised P&L: " + currency + " " + DoubleToString(pnl_sum, 2);
   r.summary += log_str;
   return r.success;
  }

bool CExecutor::Execute_ModifyPosition(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";
   int    modified = 0;
   int    failed   = 0;
   string log_str  = "";

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      //--- Apply filters
      if(task.filters.has_ticket && task.filters.ticket != ticket)                              continue;
      if(task.filters.has_magic  && PositionGetInteger(POSITION_MAGIC) != task.filters.magic)  continue;
      if(task.filters.has_symbol && PositionGetString(POSITION_SYMBOL) != task.filters.symbol) continue;
      if(task.filters.has_type)
        {
         ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(task.filters.type == "buy"  && pt != POSITION_TYPE_BUY)  continue;
         if(task.filters.type == "sell" && pt != POSITION_TYPE_SELL) continue;
        }

      string symbol     = PositionGetString(POSITION_SYMBOL);
      double entry      = PositionGetDouble(POSITION_PRICE_OPEN);
      double current_sl = PositionGetDouble(POSITION_SL);
      double current_tp = PositionGetDouble(POSITION_TP);
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double pip = PipsToPrice(symbol, 1.0);

      //--- Calculate new SL
      double new_sl = current_sl;
      if(task.modifications.sl_type == MOD_BREAKEVEN)
         new_sl = entry;
      else if(task.modifications.sl_type == MOD_PRICE)
         new_sl = task.modifications.sl_value;
      else if(task.modifications.sl_type == MOD_PIPS)
        {
         if(pos_type == POSITION_TYPE_BUY)
            new_sl = entry - PipsToPrice(symbol, task.modifications.sl_value);
         else
            new_sl = entry + PipsToPrice(symbol, task.modifications.sl_value);
        }

      //--- Calculate new TP
      double new_tp = current_tp;
      if(task.modifications.tp_type == MOD_PRICE)
         new_tp = task.modifications.tp_value;
      else if(task.modifications.tp_type == MOD_PIPS)
        {
         if(pos_type == POSITION_TYPE_BUY)
            new_tp = entry + PipsToPrice(symbol, task.modifications.tp_value);
         else
            new_tp = entry - PipsToPrice(symbol, task.modifications.tp_value);
        }

      //--- Normalise prices
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      new_sl = NormalizeDouble(new_sl, digits);
      new_tp = NormalizeDouble(new_tp, digits);

      //--- Send modification request
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = symbol;
      req.sl       = new_sl;
      req.tp       = new_tp;

      if(OrderSend(req, res))
        {
         modified++;
         log_str += nl + "  #" + IntegerToString((long)ticket)
                    + " " + symbol + " SL=" + DoubleToString(new_sl, digits)
                    + " TP=" + DoubleToString(new_tp, digits);
         Print("[Exec] Modified #", ticket, " SL=", new_sl, " TP=", new_tp);
        }
      else
        {
         failed++;
         Print("[Exec] Modify FAILED #", ticket, " retcode=", res.retcode, " comment=", res.comment);
         log_str += nl + "  #" + IntegerToString((long)ticket) + " FAILED retcode=" + IntegerToString(res.retcode);
        }
     }

   if(modified == 0 && failed == 0)
     {
      r.success = true;
      r.summary = "MODIFY: no positions matched filters";
      return true;
     }

   r.success = (failed == 0);
   r.summary  = "MODIFY RESULT" + nl;
   r.summary += "Modified: " + IntegerToString(modified);
   if(failed > 0) r.summary += "  Failed: " + IntegerToString(failed);
   r.summary += log_str;
   return r.success;
  }

bool CExecutor::Execute_PlacePending(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";

   //--- Validate required fields
   if(!task.filters.has_symbol || task.filters.symbol == "")
     {
      r.summary = "PLACE PENDING FAILED: no symbol specified";
      return false;
     }
   if(!task.pending_order.has_volume || task.pending_order.volume <= 0)
     {
      r.summary = "PLACE PENDING FAILED: no volume specified";
      return false;
     }

   string symbol = task.filters.symbol;
   int    digits  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double ask     = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid     = SymbolInfoDouble(symbol, SYMBOL_BID);

   //--- Map pending type to MT5 order type
   ENUM_ORDER_TYPE otype = ORDER_TYPE_BUY_LIMIT;
   string olabel = "BUY_LIMIT";
   switch(task.pending_order.type)
     {
      case PENDING_BUY_LIMIT:  otype = ORDER_TYPE_BUY_LIMIT;  olabel = "BUY_LIMIT";  break;
      case PENDING_SELL_LIMIT: otype = ORDER_TYPE_SELL_LIMIT; olabel = "SELL_LIMIT"; break;
      case PENDING_BUY_STOP:   otype = ORDER_TYPE_BUY_STOP;   olabel = "BUY_STOP";   break;
      case PENDING_SELL_STOP:  otype = ORDER_TYPE_SELL_STOP;  olabel = "SELL_STOP";  break;
     }

   //--- Determine entry price
   double entry_price = 0;
   if(task.pending_order.has_entry_price)
     {
      entry_price = task.pending_order.entry_price;
     }
   else if(task.pending_order.has_entry_offset_pips)
     {
      //--- Offset from current price: negative=below, positive=above
      double offset = PipsToPrice(symbol, task.pending_order.entry_offset_pips);
      if(otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_BUY_STOP)
         entry_price = ask + offset;
      else
         entry_price = bid + offset;
     }
   else
     {
      r.summary = "PLACE PENDING FAILED: no entry price or offset specified";
      return false;
     }
   entry_price = NormalizeDouble(entry_price, digits);

   //--- SL/TP calculation from pips
   double sl = 0;
   double tp = 0;
   bool is_buy_type = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_BUY_STOP);
   if(task.pending_order.has_sl_pips && task.pending_order.sl_pips > 0)
     {
      if(is_buy_type)
         sl = entry_price - PipsToPrice(symbol, task.pending_order.sl_pips);
      else
         sl = entry_price + PipsToPrice(symbol, task.pending_order.sl_pips);
      sl = NormalizeDouble(sl, digits);
     }
   if(task.pending_order.has_tp_pips && task.pending_order.tp_pips > 0)
     {
      if(is_buy_type)
         tp = entry_price + PipsToPrice(symbol, task.pending_order.tp_pips);
      else
         tp = entry_price - PipsToPrice(symbol, task.pending_order.tp_pips);
      tp = NormalizeDouble(tp, digits);
     }

   //--- Build and send
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action       = TRADE_ACTION_PENDING;
   req.symbol       = symbol;
   req.volume       = task.pending_order.volume;
   req.type         = otype;
   req.price        = entry_price;
   req.sl           = sl;
   req.tp           = tp;
   req.type_filling = GetFilling(task.filters.symbol);
   if(task.filters.has_magic)
      req.magic = (ulong)task.filters.magic;
   else
      req.magic = (ulong)m_default_magic;
   if(task.filters.has_comment)
      req.comment = task.filters.comment;
   else
      req.comment = m_default_comment;

   //--- Expiration: if hours specified, convert to absolute datetime
   if(task.pending_order.has_expiration_hours && task.pending_order.expiration_hours > 0)
     {
      req.type_time  = ORDER_TIME_SPECIFIED;
      req.expiration = TimeCurrent() + (int)(task.pending_order.expiration_hours * 3600);
     }

   if(OrderSend(req, res))
     {
      Print("[Exec] Pending order placed: ", olabel, " ", symbol,
            " vol=", task.pending_order.volume, " price=", entry_price,
            " ticket=", res.order, " retcode=", res.retcode);
      r.success = true;
      r.summary  = "PENDING ORDER PLACED" + nl;
      r.summary += olabel + " " + DoubleToString(task.pending_order.volume, 2) + " " + symbol + nl;
      r.summary += "Entry:  " + DoubleToString(entry_price, digits) + nl;
      r.summary += "Ticket: #" + IntegerToString((long)res.order);
      if(sl > 0) r.summary += nl + "SL:     " + DoubleToString(sl, digits);
      if(tp > 0) r.summary += nl + "TP:     " + DoubleToString(tp, digits);
      r.summary += nl + "Magic:  " + IntegerToString(req.magic);
      if(req.comment != "") r.summary += nl + "Comment: " + req.comment;
      if(task.pending_order.has_expiration_hours)
         r.summary += nl + "Expires: " + DoubleToString(task.pending_order.expiration_hours, 1) + " hours";
      return true;
     }
   else
     {
      Print("[Exec] Pending order FAILED retcode=", res.retcode, " comment=", res.comment);
      r.summary  = "PENDING ORDER FAILED" + nl;
      r.summary += "Retcode: " + IntegerToString(res.retcode) + nl;
      r.summary += "Comment: " + res.comment;
      return false;
     }
  }

bool CExecutor::Execute_CancelOrder(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";
   int    cancelled = 0;
   int    failed    = 0;
   string log_str   = "";

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;

      //--- Apply filters
      if(task.filters.has_ticket && task.filters.ticket != ticket)                          continue;
      if(task.filters.has_magic  && OrderGetInteger(ORDER_MAGIC)  != task.filters.magic)   continue;
      if(task.filters.has_symbol && OrderGetString(ORDER_SYMBOL)  != task.filters.symbol)  continue;
      if(task.filters.has_type)
        {
         ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(task.filters.type == "buy_limit"  && ot != ORDER_TYPE_BUY_LIMIT)  continue;
         if(task.filters.type == "sell_limit" && ot != ORDER_TYPE_SELL_LIMIT) continue;
         if(task.filters.type == "buy_stop"   && ot != ORDER_TYPE_BUY_STOP)   continue;
         if(task.filters.type == "sell_stop"  && ot != ORDER_TYPE_SELL_STOP)  continue;
        }

      string symbol = OrderGetString(ORDER_SYMBOL);
      string otype  = EnumToString((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE));

      //--- Delete pending order via TRADE_ACTION_REMOVE
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;

      if(OrderSend(req, res))
        {
         cancelled++;
         log_str += nl + "  #" + IntegerToString((long)ticket) + " " + symbol + " " + otype + " cancelled";
         Print("[Exec] Cancelled order #", ticket, " ", symbol, " ", otype);
        }
      else
        {
         failed++;
         Print("[Exec] Cancel FAILED #", ticket, " retcode=", res.retcode, " comment=", res.comment);
         log_str += nl + "  #" + IntegerToString((long)ticket) + " FAILED retcode=" + IntegerToString(res.retcode);
        }
     }

   if(cancelled == 0 && failed == 0)
     {
      //── Fallback: if ticket filter set, try close_positions ─
      if(task.filters.has_ticket)
        {
         Print("[Exec] No order matched ticket ", (long)task.filters.ticket, " -- trying close_positions fallback");
         return Execute_ClosePositions(task, r);
        }
      r.success = true;
      r.summary = "CANCEL ORDER: no pending orders matched filters";
      return true;
     }

   r.success = (failed == 0);
   r.summary  = "CANCEL ORDER RESULT" + nl;
   r.summary += "Cancelled: " + IntegerToString(cancelled);
   if(failed > 0) r.summary += "  Failed: " + IntegerToString(failed);
   r.summary += log_str;
   return r.success;
  }

bool CExecutor::Execute_PartialClose(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";

   if(!task.modifications.has_reduce_volume_pct || task.modifications.reduce_volume_pct <= 0)
     {
      r.summary = "PARTIAL CLOSE FAILED: no reduce_volume_pct specified";
      return false;
     }

   double pct     = task.modifications.reduce_volume_pct / 100.0;
   int    closed  = 0;
   int    failed  = 0;
   int    skipped = 0;
   string log_str = "";

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionMatchesFilters(ticket, task.filters)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      double full_vol = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      int    digits  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

      //--- Calculate partial volume and normalise to broker step
      double vol_step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double vol_min  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double close_vol = full_vol * pct;
      close_vol = MathFloor(close_vol / vol_step) * vol_step;

      if(close_vol < vol_min)
        {
         skipped++;
         Print("[Exec] Partial skip #", ticket, " close_vol=", close_vol, " < min=", vol_min);
         log_str += nl + "  #" + IntegerToString((long)ticket)
                    + " " + symbol + " SKIPPED (vol " + DoubleToString(close_vol, 2)
                    + " < min " + DoubleToString(vol_min, 2) + ")";
         continue;
        }

      //--- Close partial: opposite direction at market
      bool   close_buy = (pos_type == POSITION_TYPE_BUY);
      double price     = close_buy ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                   : SymbolInfoDouble(symbol, SYMBOL_ASK);

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action       = TRADE_ACTION_DEAL;
      req.position     = ticket;
      req.symbol       = symbol;
      req.volume       = close_vol;
      req.type         = close_buy ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.price        = NormalizeDouble(price, digits);
      req.deviation    = 10;
      req.type_filling = GetFilling(symbol);

      if(OrderSend(req, res))
        {
         closed++;
         string dir = close_buy ? "BUY" : "SELL";
         log_str += nl + "  #" + IntegerToString((long)ticket)
                    + " " + symbol + " " + dir
                    + " closed " + DoubleToString(close_vol, 2)
                    + " of " + DoubleToString(full_vol, 2);
         Print("[Exec] Partial closed #", ticket, " ", close_vol, "/", full_vol);
        }
      else
        {
         failed++;
         Print("[Exec] Partial close FAILED #", ticket, " retcode=", res.retcode, " comment=", res.comment);
         log_str += nl + "  #" + IntegerToString((long)ticket) + " FAILED retcode=" + IntegerToString(res.retcode);
        }
     }

   if(closed == 0 && failed == 0 && skipped == 0)
     {
      r.success = true;
      r.summary = "PARTIAL CLOSE: no positions matched filters";
      return true;
     }

   r.success = (failed == 0);
   r.summary  = "PARTIAL CLOSE RESULT (" + DoubleToString(task.modifications.reduce_volume_pct, 0) + "%)" + nl;
   r.summary += "Closed: " + IntegerToString(closed);
   if(skipped > 0) r.summary += "  Skipped: " + IntegerToString(skipped);
   if(failed > 0)  r.summary += "  Failed: " + IntegerToString(failed);
   r.summary += log_str;
   return r.success;
  }

bool CExecutor::Execute_Query(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   //--- ACCOUNT query
   if(task.noun == NOUN_ACCOUNT)
     {
      double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity    = AccountInfoDouble(ACCOUNT_EQUITY);
      double margin    = AccountInfoDouble(ACCOUNT_MARGIN);
      double free_mar  = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double mar_level = (margin > 0) ? AccountInfoDouble(ACCOUNT_MARGIN_LEVEL) : 0;

      r.summary  = "ACCOUNT QUERY" + nl;
      r.summary += "Balance:     " + currency + " " + DoubleToString(balance,  2) + nl;
      r.summary += "Equity:      " + currency + " " + DoubleToString(equity,   2) + nl;
      r.summary += "Free Margin: " + currency + " " + DoubleToString(free_mar, 2);
      if(margin > 0)
         r.summary += nl + "Margin Lvl:  " + DoubleToString(mar_level, 1) + "%";
      r.success = true;
      Print("[Exec] Query account done");
      return true;
     }

   //--- POSITIONS query
   if(task.noun == NOUN_POSITIONS)
     {
      double sum_val  = 0;
      int    count    = 0;
      string list_str = "";

      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(task.filters.has_magic  && PositionGetInteger(POSITION_MAGIC) != task.filters.magic)   continue;
         if(task.filters.has_symbol && PositionGetString(POSITION_SYMBOL) != task.filters.symbol)  continue;
         if(task.filters.has_ticket && task.filters.ticket != ticket)                               continue;
         if(task.filters.has_profit_lt  && PositionGetDouble(POSITION_PROFIT) >= task.filters.profit_lt)  continue;
         if(task.filters.has_profit_gte && PositionGetDouble(POSITION_PROFIT) <  task.filters.profit_gte) continue;
         if(task.filters.has_type)
           {
            ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            if(task.filters.type == "buy"  && pt != POSITION_TYPE_BUY)  continue;
            if(task.filters.type == "sell" && pt != POSITION_TYPE_SELL) continue;
           }

         double profit = PositionGetDouble(POSITION_PROFIT);
         double volume = PositionGetDouble(POSITION_VOLUME);
         string symbol = PositionGetString(POSITION_SYMBOL);
         string ptype  = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "buy" : "sell";
         count++;

         if(task.query_op.field == FIELD_VOLUME) sum_val += volume;
         else                                    sum_val += profit;

         if(task.query_op.aggregate == AGG_LIST)
            list_str += nl + "  #" + IntegerToString((long)ticket)
                        + " " + symbol + " " + ptype
                        + " vol=" + DoubleToString(volume, 2)
                        + " P&L=" + DoubleToString(profit, 2);
        }

      string flabel = (task.query_op.field == FIELD_VOLUME) ? "Volume" : "P&L";
      string cnt    = " (" + IntegerToString(count) + " positions)";

      if(task.query_op.aggregate == AGG_COUNT)
         r.summary = "QUERY RESULT" + nl + "Count: " + IntegerToString(count) + " positions";
      else if(task.query_op.aggregate == AGG_SUM)
         r.summary = "QUERY RESULT" + nl + "Sum " + flabel + ": " + currency + " " + DoubleToString(sum_val, 2) + cnt;
      else if(task.query_op.aggregate == AGG_AVG)
         r.summary = "QUERY RESULT" + nl + "Avg " + flabel + ": " + currency + " " + DoubleToString(count > 0 ? sum_val/count : 0, 2) + cnt;
      else if(task.query_op.aggregate == AGG_LIST)
         r.summary = "QUERY RESULT" + nl + IntegerToString(count) + " positions:" + (count == 0 ? nl + "  (none)" : list_str);
      else
         r.summary = "QUERY RESULT" + nl + "Sum P&L: " + currency + " " + DoubleToString(sum_val, 2) + cnt;

      r.success = true;
      Print("[Exec] Query positions done count=", count);
      return true;
     }

   //--- HISTORY query
   if(task.noun == NOUN_HISTORY)
     {
      datetime from = task.filters.has_time_after ? task.filters.time_after : 0;
      HistorySelect(from, TimeCurrent());

      double sum_val  = 0;
      int    count    = 0;
      string list_str = "";

      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong deal = HistoryDealGetTicket(i);
         if(deal == 0) continue;
         if(HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         if(task.filters.has_magic  && HistoryDealGetInteger(deal, DEAL_MAGIC)  != task.filters.magic)  continue;
         if(task.filters.has_symbol && HistoryDealGetString(deal,  DEAL_SYMBOL) != task.filters.symbol) continue;

         double profit = HistoryDealGetDouble(deal, DEAL_PROFIT)
                         + HistoryDealGetDouble(deal, DEAL_SWAP)
                         + HistoryDealGetDouble(deal, DEAL_COMMISSION);
         double volume = HistoryDealGetDouble(deal, DEAL_VOLUME);
         count++;

         if(task.query_op.field == FIELD_VOLUME) sum_val += volume;
         else                                    sum_val += profit;

         if(task.query_op.aggregate == AGG_LIST)
            list_str += nl + "  #" + IntegerToString((long)deal)
                        + " " + HistoryDealGetString(deal, DEAL_SYMBOL)
                        + " P&L=" + DoubleToString(profit, 2);
        }

      string cnt = " (" + IntegerToString(count) + " trades)";

      if(task.query_op.aggregate == AGG_COUNT)
         r.summary = "HISTORY QUERY" + nl + "Count: " + IntegerToString(count) + " closed trades";
      else if(task.query_op.aggregate == AGG_SUM)
         r.summary = "HISTORY QUERY" + nl + "Sum P&L: " + currency + " " + DoubleToString(sum_val, 2) + cnt;
      else if(task.query_op.aggregate == AGG_LIST)
         r.summary = "HISTORY QUERY" + nl + IntegerToString(count) + " trades:" + (count == 0 ? nl + "  (none)" : list_str);
      else
         r.summary = "HISTORY QUERY" + nl + "Sum P&L: " + currency + " " + DoubleToString(sum_val, 2) + cnt;

      r.success = true;
      Print("[Exec] Query history done count=", count);
      return true;
     }

   r.success = false;
   r.summary = "QUERY ERROR: unknown noun -- expected account, positions, or history";
   return false;
  }

bool CExecutor::Execute_Watch(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";

   //--- If notification enabled, expand template with position data
   if(task.notification.enabled && task.notification.message_template != "")
     {
      string msg = task.notification.message_template;

      //--- Try to fill placeholders from first matching position
      for(int i = 0; i < PositionsTotal(); i++)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(!PositionMatchesFilters(ticket, task.filters)) continue;

         string sym   = PositionGetString(POSITION_SYMBOL);
         double prof  = PositionGetDouble(POSITION_PROFIT);
         double vol   = PositionGetDouble(POSITION_VOLUME);
         long   mag   = PositionGetInteger(POSITION_MAGIC);
         string ptype = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? "buy" : "sell";

         StringReplace(msg, "{ticket}", IntegerToString((long)ticket));
         StringReplace(msg, "{symbol}", sym);
         StringReplace(msg, "{profit}", DoubleToString(prof, 2));
         StringReplace(msg, "{volume}", DoubleToString(vol, 2));
         StringReplace(msg, "{type}",   ptype);
         StringReplace(msg, "{magic}",  IntegerToString(mag));
         break;
        }

      Print("[Exec] Watch notify: ", msg);
      r.success = true;
      r.summary = msg;
      return true;
     }

   //--- No template -- just report that the watch fired
   Print("[Exec] Watch triggered (no notification template)");
   r.success = true;
   r.summary = "WATCH TRIGGERED" + nl + "No notification template configured";
   return true;
  }

//+------------------------------------------------------------------+
bool CExecutor::PositionMatchesFilters(ulong ticket, STaskFilters &f)
  {
   if(!PositionSelectByTicket(ticket)) return false;
   if(f.has_magic  && PositionGetInteger(POSITION_MAGIC)  != f.magic)  return false;
   if(f.has_symbol && PositionGetString(POSITION_SYMBOL)  != f.symbol) return false;
   if(f.has_ticket && (ulong)PositionGetInteger(POSITION_TICKET) != f.ticket) return false;
   if(f.has_profit_lt  && PositionGetDouble(POSITION_PROFIT) >= f.profit_lt)  return false;
   if(f.has_profit_gte && PositionGetDouble(POSITION_PROFIT) <  f.profit_gte) return false;
   if(f.has_type)
     {
      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(f.type=="buy"  && pt != POSITION_TYPE_BUY)  return false;
      if(f.type=="sell" && pt != POSITION_TYPE_SELL) return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| GetFilling -- auto-detect the correct filling mode for a symbol  |
//| Queries SYMBOL_FILLING_MODE bitmask and picks the best match.    |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING CExecutor::GetFilling(string symbol)
  {
   int modes = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
   if((modes & SYMBOL_FILLING_FOK) != 0) return ORDER_FILLING_FOK;
   if((modes & SYMBOL_FILLING_IOC) != 0) return ORDER_FILLING_IOC;
   return ORDER_FILLING_RETURN;
  }

//+------------------------------------------------------------------+
double CExecutor::PipsToPrice(string symbol, double pips)
  {
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double pip    = (digits == 3 || digits == 5) ? point * 10.0 : point;
   return pips * pip;
  }


bool CExecutor::Execute_PlaceMarket(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";

   //--- Validate required fields
   if(!task.filters.has_symbol || task.filters.symbol == "")
     {
      r.summary = "PLACE MARKET FAILED: no symbol specified";
      return false;
     }
   if(!task.market_order.has_volume || task.market_order.volume <= 0)
     {
      r.summary = "PLACE MARKET FAILED: no volume specified";
      return false;
     }

   string symbol = task.filters.symbol;
   bool   is_buy = (task.market_order.direction == "buy");
   int    digits  = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   //--- Fill price: ASK for buy, BID for sell
   double price = is_buy ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(symbol, SYMBOL_BID);

   //--- SL/TP calculation
   double sl = 0;
   double tp = 0;
   if(task.market_order.has_sl_pips && task.market_order.sl_pips > 0)
     {
      if(is_buy)
         sl = price - PipsToPrice(symbol, task.market_order.sl_pips);
      else
         sl = price + PipsToPrice(symbol, task.market_order.sl_pips);
      sl = NormalizeDouble(sl, digits);
     }
   if(task.market_order.has_tp_pips && task.market_order.tp_pips > 0)
     {
      if(is_buy)
         tp = price + PipsToPrice(symbol, task.market_order.tp_pips);
      else
         tp = price - PipsToPrice(symbol, task.market_order.tp_pips);
      tp = NormalizeDouble(tp, digits);
     }

   //--- Build and send order
   MqlTradeRequest req = {};
   MqlTradeResult  res = {};
   req.action    = TRADE_ACTION_DEAL;
   req.symbol    = symbol;
   req.volume    = task.market_order.volume;
   req.type      = is_buy ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   req.price     = NormalizeDouble(price, digits);
   req.sl        = sl;
   req.tp        = tp;
   req.deviation = 10;
   req.type_filling = GetFilling(symbol);
   if(task.filters.has_magic)
      req.magic = (ulong)task.filters.magic;
   else
      req.magic = (ulong)m_default_magic;
   if(task.filters.has_comment)
      req.comment = task.filters.comment;
   else
      req.comment = m_default_comment;

   if(OrderSend(req, res))
     {
      string dir = is_buy ? "BUY" : "SELL";
      Print("[Exec] Market order placed: ", dir, " ", symbol,
            " vol=", task.market_order.volume, " ticket=", res.order,
            " price=", res.price, " retcode=", res.retcode);
      r.success = true;
      r.summary  = "MARKET ORDER PLACED" + nl;
      r.summary += dir + " " + DoubleToString(task.market_order.volume, 2) + " " + symbol + nl;
      r.summary += "Ticket: #" + IntegerToString((long)res.order) + nl;
      r.summary += "Price:  " + DoubleToString(res.price, digits);
      if(sl > 0) r.summary += nl + "SL:     " + DoubleToString(sl, digits);
      if(tp > 0) r.summary += nl + "TP:     " + DoubleToString(tp, digits);
      r.summary += nl + "Magic:  " + IntegerToString(req.magic);
      if(req.comment != "") r.summary += nl + "Comment: " + req.comment;
      return true;
     }
   else
     {
      Print("[Exec] Market order FAILED retcode=", res.retcode, " comment=", res.comment);
      r.summary  = "MARKET ORDER FAILED" + nl;
      r.summary += "Retcode: " + IntegerToString(res.retcode) + nl;
      r.summary += "Comment: " + res.comment;
      return false;
     }
  }

//+------------------------------------------------------------------+
bool CExecutor::Execute_ModifyOrder(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";
   int    modified = 0;
   int    failed   = 0;
   string log_str  = "";

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;

      //--- Apply filters
      if(task.filters.has_ticket && task.filters.ticket != ticket)                          continue;
      if(task.filters.has_magic  && OrderGetInteger(ORDER_MAGIC)  != task.filters.magic)   continue;
      if(task.filters.has_symbol && OrderGetString(ORDER_SYMBOL)  != task.filters.symbol)  continue;
      if(task.filters.has_type)
        {
         ENUM_ORDER_TYPE ot = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
         if(task.filters.type == "buy_limit"  && ot != ORDER_TYPE_BUY_LIMIT)  continue;
         if(task.filters.type == "sell_limit" && ot != ORDER_TYPE_SELL_LIMIT) continue;
         if(task.filters.type == "buy_stop"   && ot != ORDER_TYPE_BUY_STOP)   continue;
         if(task.filters.type == "sell_stop"  && ot != ORDER_TYPE_SELL_STOP)  continue;
        }

      string symbol = OrderGetString(ORDER_SYMBOL);
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      ENUM_ORDER_TYPE otype = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
      double current_price = OrderGetDouble(ORDER_PRICE_OPEN);
      double current_sl    = OrderGetDouble(ORDER_SL);
      double current_tp    = OrderGetDouble(ORDER_TP);

      //--- Determine new entry price (keep current if not changing)
      double new_price = current_price;
      if(task.pending_order.has_entry_price)
         new_price = task.pending_order.entry_price;
      else if(task.pending_order.has_entry_offset_pips)
        {
         //--- Offset from current entry price
         new_price = current_price + PipsToPrice(symbol, task.pending_order.entry_offset_pips);
        }
      new_price = NormalizeDouble(new_price, digits);

      //--- Determine new SL
      bool is_buy_type = (otype == ORDER_TYPE_BUY_LIMIT || otype == ORDER_TYPE_BUY_STOP);
      double new_sl = current_sl;
      if(task.modifications.sl_type == MOD_PRICE)
         new_sl = task.modifications.sl_value;
      else if(task.modifications.sl_type == MOD_PIPS)
        {
         if(is_buy_type)
            new_sl = new_price - PipsToPrice(symbol, task.modifications.sl_value);
         else
            new_sl = new_price + PipsToPrice(symbol, task.modifications.sl_value);
        }
      new_sl = NormalizeDouble(new_sl, digits);

      //--- Determine new TP
      double new_tp = current_tp;
      if(task.modifications.tp_type == MOD_PRICE)
         new_tp = task.modifications.tp_value;
      else if(task.modifications.tp_type == MOD_PIPS)
        {
         if(is_buy_type)
            new_tp = new_price + PipsToPrice(symbol, task.modifications.tp_value);
         else
            new_tp = new_price - PipsToPrice(symbol, task.modifications.tp_value);
        }
      new_tp = NormalizeDouble(new_tp, digits);

      //--- Build modify request
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action       = TRADE_ACTION_MODIFY;
      req.order        = ticket;
      req.price        = new_price;
      req.sl           = new_sl;
      req.tp           = new_tp;
      req.type_time    = ORDER_TIME_GTC;

      //--- Expiration if specified
      if(task.pending_order.has_expiration_hours && task.pending_order.expiration_hours > 0)
        {
         req.type_time  = ORDER_TIME_SPECIFIED;
         req.expiration = TimeCurrent() + (int)(task.pending_order.expiration_hours * 3600);
        }

      if(OrderSend(req, res))
        {
         modified++;
         string olabel = EnumToString(otype);
         log_str += nl + "  #" + IntegerToString((long)ticket) + " " + symbol + " " + olabel;
         log_str += nl + "    Price=" + DoubleToString(new_price, digits)
                    + " SL=" + DoubleToString(new_sl, digits)
                    + " TP=" + DoubleToString(new_tp, digits);
         Print("[Exec] Modified order #", ticket, " price=", new_price,
               " SL=", new_sl, " TP=", new_tp);
        }
      else
        {
         failed++;
         Print("[Exec] Modify order FAILED #", ticket,
               " retcode=", res.retcode, " comment=", res.comment);
         log_str += nl + "  #" + IntegerToString((long)ticket)
                    + " FAILED retcode=" + IntegerToString(res.retcode);
        }
     }

   if(modified == 0 && failed == 0)
     {
      r.success = true;
      r.summary = "MODIFY ORDER: no pending orders matched filters";
      return true;
     }

   r.success = (failed == 0);
   r.summary  = "MODIFY ORDER RESULT" + nl;
   r.summary += "Modified: " + IntegerToString(modified);
   if(failed > 0) r.summary += "  Failed: " + IntegerToString(failed);
   r.summary += log_str;
   return r.success;
  }

//+------------------------------------------------------------------+
bool CExecutor::Execute_TrailStop(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";

   if(!task.modifications.has_trail_pips || task.modifications.trail_pips <= 0)
     {
      r.summary = "TRAIL STOP FAILED: no trail_pips specified";
      return false;
     }

   double trail_pips = task.modifications.trail_pips;
   int    trailed    = 0;
   int    unchanged  = 0;
   string log_str    = "";

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionMatchesFilters(ticket, task.filters)) continue;

      string symbol = PositionGetString(POSITION_SYMBOL);
      int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double current_sl = PositionGetDouble(POSITION_SL);
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      double trail_dist = PipsToPrice(symbol, trail_pips);
      double ideal_sl = 0;

      if(pos_type == POSITION_TYPE_BUY)
        {
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         ideal_sl = bid - trail_dist;
         //--- Only move SL up, never down
         if(ideal_sl <= current_sl && current_sl > 0)
           { unchanged++; continue; }
        }
      else
        {
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         ideal_sl = ask + trail_dist;
         //--- Only move SL down, never up
         if(ideal_sl >= current_sl && current_sl > 0)
           { unchanged++; continue; }
        }

      ideal_sl = NormalizeDouble(ideal_sl, digits);

      //--- Modify SL via TRADE_ACTION_SLTP
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = symbol;
      req.sl       = ideal_sl;
      req.tp       = PositionGetDouble(POSITION_TP);

      if(OrderSend(req, res))
        {
         trailed++;
         string dir = (pos_type == POSITION_TYPE_BUY) ? "BUY" : "SELL";
         log_str += nl + "  #" + IntegerToString((long)ticket)
                    + " " + symbol + " " + dir
                    + " SL " + DoubleToString(current_sl, digits)
                    + " -> " + DoubleToString(ideal_sl, digits);
         Print("[Exec] Trailed #", ticket, " SL=", ideal_sl);
        }
      else
        {
         Print("[Exec] Trail FAILED #", ticket,
               " retcode=", res.retcode, " comment=", res.comment);
        }
     }

   if(trailed == 0 && unchanged == 0)
     {
      r.success = true;
      r.silent  = true;
      r.summary = "TRAIL STOP: no positions matched filters";
      return true;
     }

   r.success = true;
   if(trailed > 0)
     {
      r.silent   = false;  // SL moved -- notify operator
      r.summary  = "TRAIL STOP (" + DoubleToString(trail_pips, 1) + " pips)" + nl;
      r.summary += "Trailed: " + IntegerToString(trailed);
      if(unchanged > 0) r.summary += "  Unchanged: " + IntegerToString(unchanged);
      r.summary += log_str;
     }
   else
     {
      r.silent   = true;   // nothing changed -- stay quiet
      r.summary  = "TRAIL STOP: all " + IntegerToString(unchanged)
                   + " positions already within trail distance";
     }
   return true;
  }

//+------------------------------------------------------------------+
bool CExecutor::Execute_CloseBy(STask &task, SExecResult &r)
  {
   r.Clear();
   string nl = "\n";

   //--- Require symbol filter so we know which symbol to close by
   if(!task.filters.has_symbol || task.filters.symbol == "")
     {
      r.summary = "CLOSE BY FAILED: no symbol specified";
      return false;
     }

   string symbol = task.filters.symbol;
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   //--- Collect BUY and SELL tickets for the symbol
   ulong buy_tickets[];
   ulong sell_tickets[];
   int   buy_count  = 0;
   int   sell_count = 0;

   for(int i = 0; i < PositionsTotal(); i++)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionMatchesFilters(ticket, task.filters)) continue;

      ENUM_POSITION_TYPE pt = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      if(pt == POSITION_TYPE_BUY)
        {
         ArrayResize(buy_tickets, buy_count + 1);
         buy_tickets[buy_count++] = ticket;
        }
      else
        {
         ArrayResize(sell_tickets, sell_count + 1);
         sell_tickets[sell_count++] = ticket;
        }
     }

   if(buy_count == 0 || sell_count == 0)
     {
      r.success = true;
      r.summary = "CLOSE BY: no opposite position pairs found on " + symbol
                  + nl + "BUY: " + IntegerToString(buy_count)
                  + "  SELL: " + IntegerToString(sell_count);
      return true;
     }

   //--- Pair and close: take min(buy_count, sell_count) pairs
   int    pairs  = MathMin(buy_count, sell_count);
   int    closed = 0;
   int    failed = 0;
   string log_str = "";

   for(int p = 0; p < pairs; p++)
     {
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action      = TRADE_ACTION_CLOSE_BY;
      req.position    = buy_tickets[p];
      req.position_by = sell_tickets[p];

      if(OrderSend(req, res))
        {
         closed++;
         log_str += nl + "  BUY #" + IntegerToString((long)buy_tickets[p])
                    + " <-> SELL #" + IntegerToString((long)sell_tickets[p]) + " closed";
         Print("[Exec] CloseBy #", buy_tickets[p], " <-> #", sell_tickets[p]);
        }
      else
        {
         failed++;
         Print("[Exec] CloseBy FAILED #", buy_tickets[p], " <-> #", sell_tickets[p],
               " retcode=", res.retcode, " comment=", res.comment);
         log_str += nl + "  BUY #" + IntegerToString((long)buy_tickets[p])
                    + " <-> SELL #" + IntegerToString((long)sell_tickets[p])
                    + " FAILED retcode=" + IntegerToString(res.retcode);
        }
     }

   r.success = (failed == 0);
   r.summary  = "CLOSE BY RESULT (" + symbol + ")" + nl;
   r.summary += "Pairs closed: " + IntegerToString(closed);
   if(failed > 0) r.summary += "  Failed: " + IntegerToString(failed);
   int remaining = (buy_count + sell_count) - (pairs * 2);
   if(remaining > 0)
      r.summary += nl + "Remaining unmatched: " + IntegerToString(remaining);
   r.summary += log_str;
   return r.success;
  }

#endif // NL_EA_EXECUTOR_MQH
