//+------------------------------------------------------------------+
//| State.mqh  --  EA mode + conversation state machine             |
//| World Tech Edge  --  MT5 NL-EA  --  Step 4                      |
//+------------------------------------------------------------------+
#ifndef NL_EA_STATE_MQH
#define NL_EA_STATE_MQH

enum ENUM_EA_MODE
  {
   EA_MODE_TRAINING = 0,
   EA_MODE_LIVE     = 1
  };

enum ENUM_CONV_STATE
  {
   STATE_IDLE            = 0,
   STATE_PENDING_REVIEW  = 1,
   STATE_PENDING_CLARIFY = 2
  };

class CState
  {
private:
   ENUM_EA_MODE      m_mode;
   ENUM_CONV_STATE   m_state;
   string            m_pending_instruction;
   string            m_pending_task_json;
   int               m_pending_task_id;

public:
                     CState();

   ENUM_EA_MODE      Mode()           { return m_mode;  }
   void              SetLive()        { m_mode = EA_MODE_LIVE;     Print("[State] Mode -> LIVE");     }
   void              SetTraining()    { m_mode = EA_MODE_TRAINING; Print("[State] Mode -> TRAINING"); }
   bool              IsLive()         { return m_mode == EA_MODE_LIVE;     }
   bool              IsTraining()     { return m_mode == EA_MODE_TRAINING; }
   string            ModeLabel()      { return m_mode == EA_MODE_LIVE ? "LIVE" : "TRAINING"; }

   ENUM_CONV_STATE   ConvState()      { return m_state; }
   void              SetIdle()
     {
      m_state = STATE_IDLE;
      m_pending_task_json = "";
      m_pending_task_id = -1;
      Print("[State] -> IDLE");
     }
   void              SetPendingReview(string task_json, int task_id)
     {
      m_state             = STATE_PENDING_REVIEW;
      m_pending_task_json = task_json;
      m_pending_task_id   = task_id;
      Print("[State] -> PENDING_REVIEW task #", task_id);
     }
   void              SetPendingClarify(string original)
     {
      m_state               = STATE_PENDING_CLARIFY;
      m_pending_instruction = original;
      Print("[State] -> PENDING_CLARIFY");
     }

   bool              IsIdle()           { return m_state == STATE_IDLE;            }
   bool              IsPendingReview()  { return m_state == STATE_PENDING_REVIEW;  }
   bool              IsPendingClarify() { return m_state == STATE_PENDING_CLARIFY; }

   string            PendingTaskJson()    { return m_pending_task_json;  }
   int               PendingTaskId()      { return m_pending_task_id;    }
   string            PendingInstruction() { return m_pending_instruction;}

   bool              IsApproval(string text);
   bool              IsFlag(string text);
  };

//+------------------------------------------------------------------+
CState::CState()
  {
   m_mode              = EA_MODE_TRAINING;
   m_state             = STATE_IDLE;
   m_pending_task_json = "";
   m_pending_task_id   = -1;
   m_pending_instruction = "";
  }

//+------------------------------------------------------------------+
bool CState::IsApproval(string text)
  {
   string t = text;
   StringToLower(t);
   StringTrimLeft(t);
   StringTrimRight(t);
   return (t == "yes" || t == "ok" || t == "correct" || t == "approved" ||
           t == "go"  || t == "execute" || t == "confirm" || t == "do it");
  }

//+------------------------------------------------------------------+
bool CState::IsFlag(string text)
  {
   string t = text;
   StringToLower(t);
   StringTrimLeft(t);
   StringTrimRight(t);
   return (t == "wrong" || t == "flag" || t == "incorrect" || t == "no" ||
           t == "bad"   || t == "skip" || t == "discard"   || t == "cancel");
  }

#endif // NL_EA_STATE_MQH
