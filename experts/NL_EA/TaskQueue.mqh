//+------------------------------------------------------------------+
//| TaskQueue.mqh  --  Task struct, queue, trigger evaluation        |
//| World Tech Edge  --  MT5 NL-EA  --  Step 4                      |
//+------------------------------------------------------------------+
#ifndef NL_EA_TASKQUEUE_MQH
#define NL_EA_TASKQUEUE_MQH

#define MAX_TASKS 64

enum ENUM_TASK_VERB
  {
   VERB_UNKNOWN          = 0,
   VERB_CLOSE_POSITIONS  = 1,
   VERB_MODIFY_POSITION  = 2,
   VERB_PLACE_PENDING    = 3,
   VERB_CANCEL_ORDER     = 4,
   VERB_PARTIAL_CLOSE    = 5,
   VERB_QUERY            = 6,
   VERB_WATCH            = 7,
   VERB_CANCEL_TASK      = 8,
   VERB_PLACE_MARKET     = 9,
   VERB_MODIFY_ORDER     = 10,
   VERB_TRAIL_STOP       = 11,
   VERB_CLOSE_BY         = 12
  };

enum ENUM_TASK_NOUN
  {
   NOUN_UNKNOWN   = 0,
   NOUN_POSITIONS = 1,
   NOUN_ORDERS    = 2,
   NOUN_HISTORY   = 3,
   NOUN_ACCOUNT   = 4,
   NOUN_TASK      = 5
  };

enum ENUM_TRIGGER_TYPE
  {
   TRIGGER_NONE               = 0,
   TRIGGER_PROFIT_GTE         = 1,
   TRIGGER_PROFIT_LT          = 2,
   TRIGGER_PRICE_CROSSES      = 3,
   TRIGGER_NEW_POS_OPENED     = 4,
   TRIGGER_TICK               = 5
  };

enum ENUM_CANCEL_COND
  {
   CANCEL_NONE              = 0,
   CANCEL_PRICE_BELOW_ENTRY = 1,
   CANCEL_PRICE_ABOVE_ENTRY = 2,
   CANCEL_TIME_ELAPSED      = 3
  };

enum ENUM_MOD_TYPE
  {
   MOD_NONE      = 0,
   MOD_BREAKEVEN = 1,
   MOD_PRICE     = 2,
   MOD_PIPS      = 3
  };

enum ENUM_QUERY_AGG
  {
   AGG_NONE  = 0,
   AGG_SUM   = 1,
   AGG_COUNT = 2,
   AGG_AVG   = 3,
   AGG_LIST  = 4
  };

enum ENUM_QUERY_FIELD
  {
   FIELD_NONE   = 0,
   FIELD_PROFIT = 1,
   FIELD_VOLUME = 2,
   FIELD_SYMBOL = 3,
   FIELD_TICKET = 4,
   FIELD_TYPE   = 5,
   FIELD_SWAP   = 6
  };

enum ENUM_PENDING_TYPE
  {
   PENDING_NONE       = 0,
   PENDING_BUY_LIMIT  = 1,
   PENDING_SELL_LIMIT = 2,
   PENDING_BUY_STOP   = 3,
   PENDING_SELL_STOP  = 4
  };

//+------------------------------------------------------------------+
struct STaskFilters
  {
   bool     has_magic;      long     magic;
   bool     has_symbol;     string   symbol;
   bool     has_ticket;     ulong    ticket;
   bool     has_profit_lt;  double   profit_lt;
   bool     has_profit_gte; double   profit_gte;
   bool     has_type;       string   type;
   bool     has_comment;    string   comment;
   bool     has_time_after; datetime time_after;

   void Clear()
     {
      has_magic=false; magic=0; has_symbol=false; symbol="";
      has_ticket=false; ticket=0; has_profit_lt=false; profit_lt=0;
      has_profit_gte=false; profit_gte=0; has_type=false; type="";
      has_comment=false; comment=""; has_time_after=false; time_after=0;
     }
  };

struct STaskTrigger
  {
   ENUM_TRIGGER_TYPE type;
   double            value;
   bool              has_ticket; ulong ticket;
   bool              has_magic;  long  magic;

   void Clear()
     {
      type=TRIGGER_NONE; value=0;
      has_ticket=false; ticket=0; has_magic=false; magic=0;
     }
  };

struct STaskModifications
  {
   ENUM_MOD_TYPE sl_type; double sl_value;
   ENUM_MOD_TYPE tp_type; double tp_value;
   bool          has_reduce_volume_pct; double reduce_volume_pct;
   bool          has_trail_pips;        double trail_pips;

   void Clear()
     {
      sl_type=MOD_NONE; sl_value=0; tp_type=MOD_NONE; tp_value=0;
      has_reduce_volume_pct=false; reduce_volume_pct=0;
      has_trail_pips=false; trail_pips=0;
     }
  };

struct STaskPendingOrder
  {
   ENUM_PENDING_TYPE type;
   bool   has_entry_offset_pips; double entry_offset_pips;
   bool   has_entry_price;       double entry_price;
   bool   has_sl_pips;           double sl_pips;
   bool   has_tp_pips;           double tp_pips;
   bool   has_volume;            double volume;
   bool   has_expiration_hours;  double expiration_hours;

   void Clear()
     {
      type=PENDING_NONE;
      has_entry_offset_pips=false; entry_offset_pips=0;
      has_entry_price=false; entry_price=0;
      has_sl_pips=false; sl_pips=0;
      has_tp_pips=false; tp_pips=0;
      has_volume=false; volume=0;
      has_expiration_hours=false; expiration_hours=0;
     }
  };


struct STaskMarketOrder
  {
   string   direction;      // "buy" or "sell"
   bool     has_volume;     double volume;
   bool     has_sl_pips;    double sl_pips;
   bool     has_tp_pips;    double tp_pips;

   void Clear()
     {
      direction=""; has_volume=false; volume=0;
      has_sl_pips=false; sl_pips=0; has_tp_pips=false; tp_pips=0;
     }
  };

struct STaskQuery
  {
   ENUM_QUERY_AGG   aggregate;
   ENUM_QUERY_FIELD field;
   void Clear() { aggregate=AGG_NONE; field=FIELD_NONE; }
  };

struct STaskNotification
  {
   bool   enabled;
   string message_template;
   void Clear() { enabled=false; message_template=""; }
  };

struct STaskCancelCond
  {
   ENUM_CANCEL_COND type;
   double           value;
   datetime         created_at;
   void Clear() { type=CANCEL_NONE; value=0; created_at=0; }
  };

//+------------------------------------------------------------------+
struct STask
  {
   int               id;
   bool              active;
   ENUM_TASK_VERB    verb;
   ENUM_TASK_NOUN    noun;
   STaskFilters      filters;
   bool              is_conditional;
   bool              is_persistent;
   bool              requires_confirmation;
   STaskTrigger      trigger;
   STaskModifications modifications;
   STaskPendingOrder pending_order;
   STaskMarketOrder  market_order;
   STaskQuery        query_op;
   STaskNotification notification;
   STaskCancelCond   cancel_cond;
   bool              has_on_trigger;
   string            on_trigger_json;
   string            raw_json;
   datetime          created_at;
   datetime          triggered_at;

   void Clear()
     {
      id=-1; active=false; verb=VERB_UNKNOWN; noun=NOUN_UNKNOWN;
      filters.Clear(); is_conditional=false; is_persistent=false;
      requires_confirmation=false; trigger.Clear(); modifications.Clear();
      pending_order.Clear(); market_order.Clear(); query_op.Clear(); notification.Clear();
      cancel_cond.Clear(); has_on_trigger=false; on_trigger_json="";
      raw_json=""; created_at=0; triggered_at=0;
     }
  };

//+------------------------------------------------------------------+
class CTaskQueue
  {
private:
   STask  m_tasks[MAX_TASKS];
   int    m_next_id;
   int    m_count;

   int    FindSlot();
   string VerbLabel(ENUM_TASK_VERB v);
   string TriggerLabel(STaskTrigger &t);

public:
                     CTaskQueue();
   int               Add(STask &task);
   bool              Remove(int task_id);
   void              RemoveAll();
   int               Count()  { return m_count; }
   bool              GetById(int id, STask &out);
   int               GetActiveIds(int &ids[]);
   string            SummaryText();
   int               EvaluateTriggers(int &fired_ids[]);
  };

//+------------------------------------------------------------------+
CTaskQueue::CTaskQueue()
  {
   m_next_id = 1;
   m_count   = 0;
   for(int i = 0; i < MAX_TASKS; i++) m_tasks[i].Clear();
  }

//+------------------------------------------------------------------+
int CTaskQueue::Add(STask &task)
  {
   int slot = FindSlot();
   if(slot < 0) { Print("[Queue] Full"); return -1; }
   task.id       = m_next_id++;
   task.active   = true;
   task.created_at = TimeCurrent();
   m_tasks[slot] = task;
   m_count++;
   Print("[Queue] Added Task #", task.id, " verb=", VerbLabel(task.verb));
   return task.id;
  }

//+------------------------------------------------------------------+
bool CTaskQueue::Remove(int task_id)
  {
   for(int i = 0; i < MAX_TASKS; i++)
      if(m_tasks[i].active && m_tasks[i].id == task_id)
        {
         m_tasks[i].active = false;
         m_count--;
         Print("[Queue] Removed Task #", task_id);
         return true;
        }
   Print("[Queue] Task #", task_id, " not found");
   return false;
  }

//+------------------------------------------------------------------+
void CTaskQueue::RemoveAll()
  {
   int n = 0;
   for(int i = 0; i < MAX_TASKS; i++)
      if(m_tasks[i].active) { m_tasks[i].active = false; n++; }
   m_count = 0;
   Print("[Queue] Removed all (", n, ")");
  }

//+------------------------------------------------------------------+
bool CTaskQueue::GetById(int id, STask &out)
  {
   for(int i = 0; i < MAX_TASKS; i++)
      if(m_tasks[i].active && m_tasks[i].id == id) { out = m_tasks[i]; return true; }
   return false;
  }

//+------------------------------------------------------------------+
int CTaskQueue::GetActiveIds(int &ids[])
  {
   ArrayResize(ids, m_count);
   int n = 0;
   for(int i = 0; i < MAX_TASKS; i++)
      if(m_tasks[i].active) ids[n++] = m_tasks[i].id;
   return n;
  }

//+------------------------------------------------------------------+
string CTaskQueue::SummaryText()
  {
   if(m_count == 0) return "[TASKS] No active tasks";

   string out = "[TASKS] Active: " + IntegerToString(m_count) + "\n";
   for(int i = 0; i < MAX_TASKS; i++)
     {
      if(!m_tasks[i].active) continue;
      out += "\nTask #" + IntegerToString(m_tasks[i].id) + " " + VerbLabel(m_tasks[i].verb);
      if(m_tasks[i].filters.has_symbol) out += " [" + m_tasks[i].filters.symbol + "]";
      if(m_tasks[i].filters.has_ticket) out += " ticket=" + IntegerToString((long)m_tasks[i].filters.ticket);
      if(m_tasks[i].filters.has_magic)  out += " magic="  + IntegerToString(m_tasks[i].filters.magic);
      if(m_tasks[i].trigger.type != TRIGGER_NONE) out += "\n  Trigger: " + TriggerLabel(m_tasks[i].trigger);
      if(m_tasks[i].is_persistent)  out += "\n  Persistent: yes";
      if(m_tasks[i].has_on_trigger) out += "\n  Compound: yes";
     }
   return out;
  }

//+------------------------------------------------------------------+
int CTaskQueue::EvaluateTriggers(int &fired_ids[])
  {
   ArrayResize(fired_ids, 0);
   int count = 0;

   for(int i = 0; i < MAX_TASKS; i++)
     {
      if(!m_tasks[i].active) continue;
      if(!m_tasks[i].is_conditional || m_tasks[i].trigger.type == TRIGGER_NONE) continue;

      bool fired = false;

      switch(m_tasks[i].trigger.type)
        {
         case TRIGGER_PROFIT_GTE:
           {
            double profit = 0;
            for(int p = 0; p < PositionsTotal(); p++)
              {
               ulong tk = PositionGetTicket(p);
               if(tk == 0) continue;
               if(m_tasks[i].trigger.has_ticket && (ulong)m_tasks[i].trigger.ticket != tk) continue;
               if(m_tasks[i].filters.has_magic  && PositionGetInteger(POSITION_MAGIC) != m_tasks[i].filters.magic) continue;
               if(m_tasks[i].filters.has_symbol && PositionGetString(POSITION_SYMBOL) != m_tasks[i].filters.symbol) continue;
               profit += PositionGetDouble(POSITION_PROFIT);
              }
            fired = (profit >= m_tasks[i].trigger.value);
            break;
           }

         case TRIGGER_PROFIT_LT:
           {
            double profit = 0;
            for(int p = 0; p < PositionsTotal(); p++)
              {
               ulong tk = PositionGetTicket(p);
               if(tk == 0) continue;
               if(m_tasks[i].trigger.has_ticket && (ulong)m_tasks[i].trigger.ticket != tk) continue;
               if(m_tasks[i].filters.has_magic  && PositionGetInteger(POSITION_MAGIC) != m_tasks[i].filters.magic) continue;
               if(m_tasks[i].filters.has_symbol && PositionGetString(POSITION_SYMBOL) != m_tasks[i].filters.symbol) continue;
               profit += PositionGetDouble(POSITION_PROFIT);
              }
            fired = (profit < m_tasks[i].trigger.value);
            break;
           }

         case TRIGGER_NEW_POS_OPENED:
            fired = false; // stub -- implemented in Step 5
            break;

         case TRIGGER_PRICE_CROSSES:
            fired = false; // stub -- implemented in Step 5
            break;

         case TRIGGER_TICK:
            fired = true;
            break;
        }

      if(fired)
        {
         ArrayResize(fired_ids, count + 1);
         fired_ids[count++] = m_tasks[i].id;
         m_tasks[i].triggered_at = TimeCurrent();
         if(!m_tasks[i].is_persistent) m_tasks[i].active = false;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
int CTaskQueue::FindSlot()
  {
   for(int i = 0; i < MAX_TASKS; i++)
      if(!m_tasks[i].active) return i;
   return -1;
  }

//+------------------------------------------------------------------+
string CTaskQueue::VerbLabel(ENUM_TASK_VERB v)
  {
   switch(v)
     {
      case VERB_CLOSE_POSITIONS: return "close_positions";
      case VERB_MODIFY_POSITION: return "modify_position";
      case VERB_PLACE_PENDING:   return "place_pending";
      case VERB_CANCEL_ORDER:    return "cancel_order";
      case VERB_PARTIAL_CLOSE:   return "partial_close";
      case VERB_QUERY:           return "query";
      case VERB_WATCH:           return "watch";
      case VERB_CANCEL_TASK:     return "cancel_task";
      case VERB_PLACE_MARKET:    return "place_market";
      case VERB_MODIFY_ORDER:    return "modify_order";
      case VERB_TRAIL_STOP:      return "trail_stop";
      case VERB_CLOSE_BY:        return "close_by";
      default:                   return "unknown";
     }
  }

//+------------------------------------------------------------------+
string CTaskQueue::TriggerLabel(STaskTrigger &t)
  {
   switch(t.type)
     {
      case TRIGGER_PROFIT_GTE:     return "profit >= $" + DoubleToString(t.value, 2);
      case TRIGGER_PROFIT_LT:      return "profit < $"  + DoubleToString(t.value, 2);
      case TRIGGER_PRICE_CROSSES:  return "price crosses " + DoubleToString(t.value, 5);
      case TRIGGER_NEW_POS_OPENED: return "new position opened";
      case TRIGGER_TICK:           return "every tick";
      default:                     return "none";
     }
  }

#endif // NL_EA_TASKQUEUE_MQH
