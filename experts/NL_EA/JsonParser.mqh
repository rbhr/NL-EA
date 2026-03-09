//+------------------------------------------------------------------+
//| JsonParser.mqh  --  Claude JSON response -> STask                |
//| World Tech Edge  --  MT5 NL-EA  --  Step 4                      |
//| Requires JAson.mqh in MQL5/Include/                              |
//+------------------------------------------------------------------+
#ifndef NL_EA_JSONPARSER_MQH
#define NL_EA_JSONPARSER_MQH

#include <JAson.mqh>
#include "TaskQueue.mqh"

class CJsonParser
  {
public:
   bool ParseEnvelope(string json, string &outcome, string &reason,
                      string &clarification, string &schema_notes, string &prompt_ver);
   bool ParseTask(string task_json, STask &task);
   bool ExtractTaskJson(string envelope_json, string &task_json);

private:
   void ParseFilters(CJAVal &node, STaskFilters &f);
   void ParseTrigger(CJAVal &node, STaskTrigger &t);
   void ParseModifications(CJAVal &node, STaskModifications &m);
   void ParsePendingOrder(CJAVal &node, STaskPendingOrder &o);
   void ParseQueryOp(CJAVal &node, STaskQuery &q);
   void ParseNotification(CJAVal &node, STaskNotification &n);
   void ParseCancelCond(CJAVal &node, STaskCancelCond &c);
   void ParseMarketOrder(CJAVal &node, STaskMarketOrder &o);

   ENUM_TASK_VERB    VerbFromStr(string s);
   ENUM_TASK_NOUN    NounFromStr(string s);
   ENUM_TRIGGER_TYPE TriggerFromStr(string s);
   ENUM_CANCEL_COND  CancelFromStr(string s);
   ENUM_MOD_TYPE     ModFromStr(string s);
   ENUM_QUERY_AGG    AggFromStr(string s);
   ENUM_QUERY_FIELD  FieldFromStr(string s);
   ENUM_PENDING_TYPE PendingFromStr(string s);
  };

//+------------------------------------------------------------------+
bool CJsonParser::ParseEnvelope(string json, string &outcome, string &reason,
                                 string &clarification, string &schema_notes, string &prompt_ver)
  {
   CJAVal root;
   if(!root.Deserialize(json)) { Print("[Parser] Bad envelope JSON"); return false; }
   outcome       = root["outcome"].ToStr();
   reason        = root["outcome_reason"].ToStr();
   clarification = root["clarification_needed"].ToStr();
   schema_notes  = root["schema_notes"].ToStr();
   prompt_ver    = root["prompt_version"].ToStr();
   if(outcome == "") { Print("[Parser] Missing outcome field"); return false; }
   return true;
  }

//+------------------------------------------------------------------+
bool CJsonParser::ExtractTaskJson(string envelope_json, string &task_json)
  {
   CJAVal root;
   if(!root.Deserialize(envelope_json)) return false;
   if(root["task"].m_type == jtNULL || root["task"].m_type == jtUNDEF)
     { task_json = ""; return false; }
   task_json = root["task"].Serialize();
   return true;
  }

//+------------------------------------------------------------------+
bool CJsonParser::ParseTask(string task_json, STask &task)
  {
   task.Clear();
   CJAVal root;
   if(!root.Deserialize(task_json)) { Print("[Parser] Bad task JSON"); return false; }

   task.verb = VerbFromStr(root["verb"].ToStr());
   task.noun = NounFromStr(root["noun"].ToStr());
   task.is_conditional       = (bool)root["is_conditional"].ToBool();
   task.is_persistent        = (bool)root["is_persistent"].ToBool();
   task.requires_confirmation= (bool)root["requires_confirmation"].ToBool();

   if(root["filters"].m_type != jtNULL && root["filters"].m_type != jtUNDEF)
      ParseFilters(root["filters"], task.filters);
   if(root["trigger"].m_type != jtNULL && root["trigger"].m_type != jtUNDEF)
      ParseTrigger(root["trigger"], task.trigger);
   if(root["modifications"].m_type != jtNULL && root["modifications"].m_type != jtUNDEF)
      ParseModifications(root["modifications"], task.modifications);
   if(root["pending_order"].m_type != jtNULL && root["pending_order"].m_type != jtUNDEF)
      ParsePendingOrder(root["pending_order"], task.pending_order);
   if(root["market_order"].m_type != jtNULL && root["market_order"].m_type != jtUNDEF)
      ParseMarketOrder(root["market_order"], task.market_order);
   if(root["query_operation"].m_type != jtNULL && root["query_operation"].m_type != jtUNDEF)
      ParseQueryOp(root["query_operation"], task.query_op);
   if(root["notification"].m_type != jtNULL && root["notification"].m_type != jtUNDEF)
      ParseNotification(root["notification"], task.notification);
   if(root["cancel_condition"].m_type != jtNULL && root["cancel_condition"].m_type != jtUNDEF)
      ParseCancelCond(root["cancel_condition"], task.cancel_cond);

   if(root["on_trigger"].m_type != jtNULL && root["on_trigger"].m_type != jtUNDEF
      && root["on_trigger"].Size() > 0)
     {
      task.has_on_trigger  = true;
      task.on_trigger_json = root["on_trigger"].Serialize();
     }

   task.raw_json = task_json;
   return true;
  }

//+------------------------------------------------------------------+
void CJsonParser::ParseFilters(CJAVal &n, STaskFilters &f)
  {
   f.Clear();
   if(n["magic"].m_type  != jtUNDEF && n["magic"].m_type  != jtNULL) { f.has_magic=true;  f.magic=(long)n["magic"].ToInt(); }
   if(n["symbol"].m_type != jtUNDEF && n["symbol"].m_type != jtNULL) { f.has_symbol=true; f.symbol=n["symbol"].ToStr(); }
   if(n["ticket"].m_type != jtUNDEF && n["ticket"].m_type != jtNULL) { f.has_ticket=true; f.ticket=(ulong)n["ticket"].ToInt(); }
   if(n["profit_lt"].m_type  != jtUNDEF && n["profit_lt"].m_type  != jtNULL) { f.has_profit_lt=true;  f.profit_lt=n["profit_lt"].ToDbl(); }
   if(n["profit_gte"].m_type != jtUNDEF && n["profit_gte"].m_type != jtNULL) { f.has_profit_gte=true; f.profit_gte=n["profit_gte"].ToDbl(); }
   if(n["type"].m_type    != jtUNDEF && n["type"].m_type    != jtNULL) { f.has_type=true;    f.type=n["type"].ToStr(); }
   if(n["comment"].m_type != jtUNDEF && n["comment"].m_type != jtNULL) { f.has_comment=true; f.comment=n["comment"].ToStr(); }
   if(n["time_after"].m_type != jtUNDEF && n["time_after"].m_type != jtNULL)
     { f.has_time_after=true; f.time_after=StringToTime(n["time_after"].ToStr()); }
  }

//+------------------------------------------------------------------+
void CJsonParser::ParseTrigger(CJAVal &n, STaskTrigger &t)
  {
   t.Clear();
   t.type = TriggerFromStr(n["type"].ToStr());
   if(n["value"].m_type  != jtUNDEF) t.value = n["value"].ToDbl();
   if(n["ticket"].m_type != jtUNDEF && n["ticket"].m_type != jtNULL) { t.has_ticket=true; t.ticket=(ulong)n["ticket"].ToInt(); }
   if(n["magic"].m_type  != jtUNDEF && n["magic"].m_type  != jtNULL) { t.has_magic=true;  t.magic=(long)n["magic"].ToInt(); }
  }

//+------------------------------------------------------------------+
void CJsonParser::ParseModifications(CJAVal &n, STaskModifications &m)
  {
   m.Clear();
   if(n["sl_type"].m_type != jtUNDEF) m.sl_type = ModFromStr(n["sl_type"].ToStr());
   if(n["sl_value"].m_type!= jtUNDEF) m.sl_value = n["sl_value"].ToDbl();
   if(n["tp_type"].m_type != jtUNDEF) m.tp_type = ModFromStr(n["tp_type"].ToStr());
   if(n["tp_value"].m_type!= jtUNDEF) m.tp_value = n["tp_value"].ToDbl();
   if(n["reduce_volume_pct"].m_type != jtUNDEF && n["reduce_volume_pct"].m_type != jtNULL)
     { m.has_reduce_volume_pct=true; m.reduce_volume_pct=n["reduce_volume_pct"].ToDbl(); }
   if(n["trail_pips"].m_type != jtUNDEF && n["trail_pips"].m_type != jtNULL)
     { m.has_trail_pips=true; m.trail_pips=n["trail_pips"].ToDbl(); }
  }

//+------------------------------------------------------------------+
void CJsonParser::ParsePendingOrder(CJAVal &n, STaskPendingOrder &o)
  {
   o.Clear();
   o.type = PendingFromStr(n["type"].ToStr());
   if(n["entry_offset_pips"].m_type != jtUNDEF && n["entry_offset_pips"].m_type != jtNULL) { o.has_entry_offset_pips=true; o.entry_offset_pips=n["entry_offset_pips"].ToDbl(); }
   if(n["entry_price"].m_type != jtUNDEF && n["entry_price"].m_type != jtNULL) { o.has_entry_price=true; o.entry_price=n["entry_price"].ToDbl(); }
   if(n["sl_pips"].m_type != jtUNDEF && n["sl_pips"].m_type != jtNULL) { o.has_sl_pips=true; o.sl_pips=n["sl_pips"].ToDbl(); }
   if(n["tp_pips"].m_type != jtUNDEF && n["tp_pips"].m_type != jtNULL) { o.has_tp_pips=true; o.tp_pips=n["tp_pips"].ToDbl(); }
   if(n["volume"].m_type  != jtUNDEF && n["volume"].m_type  != jtNULL) { o.has_volume=true;  o.volume=n["volume"].ToDbl(); }
   if(n["expiration_hours"].m_type != jtUNDEF && n["expiration_hours"].m_type != jtNULL) { o.has_expiration_hours=true; o.expiration_hours=n["expiration_hours"].ToDbl(); }
  }

//+------------------------------------------------------------------+
void CJsonParser::ParseQueryOp(CJAVal &n, STaskQuery &q)
  {
   q.Clear();
   q.aggregate = AggFromStr(n["aggregate"].ToStr());
   q.field     = FieldFromStr(n["field"].ToStr());
  }

//+------------------------------------------------------------------+
void CJsonParser::ParseNotification(CJAVal &n, STaskNotification &notif)
  {
   notif.Clear();
   notif.enabled          = true;
   notif.message_template = n["message_template"].ToStr();
  }

//+------------------------------------------------------------------+
void CJsonParser::ParseCancelCond(CJAVal &n, STaskCancelCond &c)
  {
   c.Clear();
   c.type       = CancelFromStr(n["type"].ToStr());
   c.value      = n["value"].ToDbl();
   c.created_at = TimeCurrent();
  }

//+------------------------------------------------------------------+
ENUM_TASK_VERB CJsonParser::VerbFromStr(string s)
  {
   if(s=="close_positions") return VERB_CLOSE_POSITIONS;
   if(s=="modify_position") return VERB_MODIFY_POSITION;
   if(s=="place_pending")   return VERB_PLACE_PENDING;
   if(s=="cancel_order")    return VERB_CANCEL_ORDER;
   if(s=="partial_close")   return VERB_PARTIAL_CLOSE;
   if(s=="query")           return VERB_QUERY;
   if(s=="watch")           return VERB_WATCH;
   if(s=="cancel_task")     return VERB_CANCEL_TASK;
   if(s=="place_market")    return VERB_PLACE_MARKET;
   if(s=="modify_order")    return VERB_MODIFY_ORDER;
   if(s=="trail_stop")      return VERB_TRAIL_STOP;
   if(s=="close_by")        return VERB_CLOSE_BY;
   Print("[Parser] Unknown verb: ", s);
   return VERB_UNKNOWN;
  }

ENUM_TASK_NOUN CJsonParser::NounFromStr(string s)
  {
   if(s=="positions") return NOUN_POSITIONS;
   if(s=="orders")    return NOUN_ORDERS;
   if(s=="history")   return NOUN_HISTORY;
   if(s=="account")   return NOUN_ACCOUNT;
   if(s=="task")      return NOUN_TASK;
   return NOUN_UNKNOWN;
  }

ENUM_TRIGGER_TYPE CJsonParser::TriggerFromStr(string s)
  {
   if(s=="profit_gte")          return TRIGGER_PROFIT_GTE;
   if(s=="profit_lt")           return TRIGGER_PROFIT_LT;
   if(s=="price_crosses")       return TRIGGER_PRICE_CROSSES;
   if(s=="new_position_opened") return TRIGGER_NEW_POS_OPENED;
   if(s=="tick")                return TRIGGER_TICK;
   return TRIGGER_NONE;
  }

ENUM_CANCEL_COND CJsonParser::CancelFromStr(string s)
  {
   if(s=="price_below_entry") return CANCEL_PRICE_BELOW_ENTRY;
   if(s=="price_above_entry") return CANCEL_PRICE_ABOVE_ENTRY;
   if(s=="time_elapsed")      return CANCEL_TIME_ELAPSED;
   return CANCEL_NONE;
  }

ENUM_MOD_TYPE CJsonParser::ModFromStr(string s)
  {
   if(s=="breakeven") return MOD_BREAKEVEN;
   if(s=="price")     return MOD_PRICE;
   if(s=="pips")      return MOD_PIPS;
   return MOD_NONE;
  }

ENUM_QUERY_AGG CJsonParser::AggFromStr(string s)
  {
   if(s=="sum")   return AGG_SUM;
   if(s=="count") return AGG_COUNT;
   if(s=="avg")   return AGG_AVG;
   if(s=="list")  return AGG_LIST;
   return AGG_NONE;
  }

ENUM_QUERY_FIELD CJsonParser::FieldFromStr(string s)
  {
   if(s=="profit") return FIELD_PROFIT;
   if(s=="volume") return FIELD_VOLUME;
   if(s=="symbol") return FIELD_SYMBOL;
   if(s=="ticket") return FIELD_TICKET;
   if(s=="type")   return FIELD_TYPE;
   if(s=="swap")   return FIELD_SWAP;
   return FIELD_NONE;
  }

ENUM_PENDING_TYPE CJsonParser::PendingFromStr(string s)
  {
   if(s=="buy_limit")  return PENDING_BUY_LIMIT;
   if(s=="sell_limit") return PENDING_SELL_LIMIT;
   if(s=="buy_stop")   return PENDING_BUY_STOP;
   if(s=="sell_stop")  return PENDING_SELL_STOP;
   return PENDING_NONE;
  }


//+------------------------------------------------------------------+
void CJsonParser::ParseMarketOrder(CJAVal &n, STaskMarketOrder &o)
  {
   o.Clear();
   o.direction = n["direction"].ToStr();
   if(n["volume"].m_type  != jtUNDEF && n["volume"].m_type  != jtNULL) { o.has_volume=true;  o.volume=n["volume"].ToDbl(); }
   if(n["sl_pips"].m_type != jtUNDEF && n["sl_pips"].m_type != jtNULL) { o.has_sl_pips=true; o.sl_pips=n["sl_pips"].ToDbl(); }
   if(n["tp_pips"].m_type != jtUNDEF && n["tp_pips"].m_type != jtNULL) { o.has_tp_pips=true; o.tp_pips=n["tp_pips"].ToDbl(); }
  }

#endif // NL_EA_JSONPARSER_MQH
