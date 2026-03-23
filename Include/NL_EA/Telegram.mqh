//+------------------------------------------------------------------+
//| Telegram.mqh  --  Telegram Bot API: poll and send               |
//| World Tech Edge  --  MT5 NL-EA  --  Step 4                      |
//+------------------------------------------------------------------+
#ifndef NL_EA_TELEGRAM_MQH
#define NL_EA_TELEGRAM_MQH

#include <JAson.mqh>

#define TG_BASE_URL "https://api.telegram.org/bot"
#define TG_TIMEOUT  5000

struct STgMessage
  {
   long     update_id;
   long     chat_id;
   string   text;
   datetime date;
   bool     is_callback;        // true if from inline button press
   string   callback_data;      // e.g. "approve", "flag", "focus_on", "focus_off"
   string   callback_query_id;  // needed to dismiss spinner via AnswerCallbackQuery
   void Clear() { update_id=0; chat_id=0; text=""; date=0;
                   is_callback=false; callback_data=""; callback_query_id=""; }
  };

class CTelegram
  {
private:
   string m_token;
   long   m_chat_id;
   long   m_last_update_id;
   long   m_lock_msg_id;          // message ID of the pinned lock message

   bool   HttpGet(string url, string &resp);
   bool   HttpPost(string url, string body, string &resp);
   string EscapeJson(string s);

public:
          CTelegram() : m_token(""), m_chat_id(0), m_last_update_id(0), m_lock_msg_id(0) {}

   void   Init(string token, long chat_id)
     {
      m_token          = token;
      m_chat_id        = chat_id;
      m_last_update_id = 0;
      m_lock_msg_id    = 0;
      Print("[Telegram] Init chat_id=", chat_id);
     }

   int    Poll(STgMessage &out[]);
   bool   Send(string text);
   long   SendAndGetId(string text);
   bool   SendWithMode(string text, string mode_label);
   bool   SendWithButtons(string text, const string &buttons[][2], int num_buttons);
   bool   AnswerCallbackQuery(string query_id);

   // ── Account lock via Telegram pinned message ──
   bool   GetPinnedLockAccount(long &locked_account, long &pinned_msg_id);
   bool   PinMessage(long message_id);
   bool   UnpinMessage(long message_id);
   long   LockMsgId() const { return m_lock_msg_id; }
   void   SetLockMsgId(long id) { m_lock_msg_id = id; }
  };

//+------------------------------------------------------------------+
int CTelegram::Poll(STgMessage &out[])
  {
   ArrayResize(out, 0);
   string url = TG_BASE_URL + m_token + "/getUpdates"
                + "?timeout=0&offset=" + IntegerToString(m_last_update_id + 1)
                + "&allowed_updates=[\"message\",\"callback_query\"]";
   string resp;
   if(!HttpGet(url, resp)) return 0;

   CJAVal root;
   if(!root.Deserialize(resp)) { Print("[Telegram] Poll parse fail"); return 0; }
   if(!root["ok"].ToBool())    { Print("[Telegram] Poll API err: ", root["description"].ToStr()); return 0; }

   CJAVal *results = root.FindKey("result");
   if(results == NULL) return 0;

   int count = 0;
   int n     = results.Size();
   for(int i = 0; i < n; i++)
     {
      long uid = results[i]["update_id"].ToInt();
      if(uid > m_last_update_id) m_last_update_id = uid;

      //── Path A: regular text message ─────────────────
      string txt = results[i]["message"]["text"].ToStr();
      if(txt != "")
        {
         long cid = results[i]["message"]["chat"]["id"].ToInt();
         if(m_chat_id != 0 && cid != m_chat_id)
           { Print("[Telegram] Ignoring unauthorised chat_id=", cid); continue; }

         ArrayResize(out, count + 1);
         out[count].Clear();
         out[count].update_id = uid;
         out[count].chat_id   = cid;
         out[count].text      = txt;
         out[count].date      = (datetime)results[i]["message"]["date"].ToInt();
         count++;
         continue;
        }

      //── Path B: inline keyboard callback ─────────────
      string cb_id = results[i]["callback_query"]["id"].ToStr();
      if(cb_id != "")
        {
         long cid = results[i]["callback_query"]["message"]["chat"]["id"].ToInt();
         if(m_chat_id != 0 && cid != m_chat_id)
           { Print("[Telegram] Ignoring unauthorised callback chat_id=", cid); continue; }

         string cb_data = results[i]["callback_query"]["data"].ToStr();
         ArrayResize(out, count + 1);
         out[count].Clear();
         out[count].update_id          = uid;
         out[count].chat_id            = cid;
         out[count].text               = cb_data;
         out[count].date               = (datetime)TimeCurrent();
         out[count].is_callback        = true;
         out[count].callback_data      = cb_data;
         out[count].callback_query_id  = cb_id;
         count++;
        }
     }
   return count;
  }

//+------------------------------------------------------------------+
bool CTelegram::Send(string text)
  {
   if(m_chat_id == 0) { Print("[Telegram] No chat_id set"); return false; }
   string url  = TG_BASE_URL + m_token + "/sendMessage";
   string body = "{\"chat_id\":" + IntegerToString(m_chat_id) +
                 ",\"text\":\"" + EscapeJson(text) + "\"}";
   string resp;
   if(!HttpPost(url, body, resp)) return false;

   CJAVal root;
   if(!root.Deserialize(resp)) return false;
   if(!root["ok"].ToBool()) { Print("[Telegram] Send err: ", root["description"].ToStr()); return false; }
   return true;
  }

//+------------------------------------------------------------------+
bool CTelegram::SendWithMode(string text, string mode_label)
  {
   return Send("[" + mode_label + "]\n" + text);
  }

//+------------------------------------------------------------------+
bool CTelegram::SendWithButtons(string text, const string &buttons[][2], int num_buttons)
  {
   if(m_chat_id == 0) { Print("[Telegram] No chat_id set"); return false; }

   // Build inline_keyboard JSON: one row, all buttons side by side
   string kb = "[[";
   for(int i = 0; i < num_buttons; i++)
     {
      if(i > 0) kb += ",";
      kb += "{\"text\":\"" + EscapeJson(buttons[i][0]) + "\","
          + "\"callback_data\":\"" + EscapeJson(buttons[i][1]) + "\"}";
     }
   kb += "]]";

   string url  = TG_BASE_URL + m_token + "/sendMessage";
   string body = "{\"chat_id\":" + IntegerToString(m_chat_id)
               + ",\"text\":\"" + EscapeJson(text) + "\""
               + ",\"reply_markup\":{\"inline_keyboard\":" + kb + "}}";
   string resp;
   if(!HttpPost(url, body, resp)) return false;

   CJAVal root;
   if(!root.Deserialize(resp)) return false;
   if(!root["ok"].ToBool()) { Print("[Telegram] SendWithButtons err: ", root["description"].ToStr()); return false; }
   return true;
  }

//+------------------------------------------------------------------+
bool CTelegram::AnswerCallbackQuery(string query_id)
  {
   string url  = TG_BASE_URL + m_token + "/answerCallbackQuery";
   string body = "{\"callback_query_id\":\"" + query_id + "\"}";
   string resp;
   if(!HttpPost(url, body, resp)) return false;
   return true;
  }

//+------------------------------------------------------------------+
bool CTelegram::HttpGet(string url, string &resp)
  {
   char req[], res[]; string hdrs;
   ArrayResize(req, 0);
   int code = WebRequest("GET", url, "", TG_TIMEOUT, req, res, hdrs);
   if(code == -1)
     {
      Print("[Telegram] GET failed err=", GetLastError(),
            " -- add ", TG_BASE_URL, " to allowed URLs");
      return false;
     }
   resp = CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
  }

//+------------------------------------------------------------------+
bool CTelegram::HttpPost(string url, string body, string &resp)
  {
   char req[], res[];
   string hdrs = "Content-Type: application/json\r\n";
   StringToCharArray(body, req, 0, StringLen(body), CP_UTF8);
   int code = WebRequest("POST", url, hdrs, TG_TIMEOUT, req, res, hdrs);
   if(code == -1)
     {
      Print("[Telegram] POST failed err=", GetLastError());
      return false;
     }
   resp = CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
  }

//+------------------------------------------------------------------+
string CTelegram::EscapeJson(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   StringReplace(s, "\t", "\\t");
   return s;
  }

//+------------------------------------------------------------------+
long CTelegram::SendAndGetId(string text)
  {
   if(m_chat_id == 0) { Print("[Telegram] No chat_id set"); return 0; }
   string url  = TG_BASE_URL + m_token + "/sendMessage";
   string body = "{\"chat_id\":" + IntegerToString(m_chat_id) +
                 ",\"text\":\"" + EscapeJson(text) + "\"}";
   string resp;
   if(!HttpPost(url, body, resp)) return 0;

   CJAVal root;
   if(!root.Deserialize(resp)) return 0;
   if(!root["ok"].ToBool()) { Print("[Telegram] Send err: ", root["description"].ToStr()); return 0; }
   return root["result"]["message_id"].ToInt();
  }

//+------------------------------------------------------------------+
//| GetPinnedLockAccount -- reads pinned message via getChat.        |
//| Returns true if a valid NL_EA_LOCK pin was found.                |
//| Sets locked_account and pinned_msg_id from the lock message.     |
//+------------------------------------------------------------------+
bool CTelegram::GetPinnedLockAccount(long &locked_account, long &pinned_msg_id)
  {
   locked_account = 0;
   pinned_msg_id  = 0;
   string url = TG_BASE_URL + m_token + "/getChat"
                + "?chat_id=" + IntegerToString(m_chat_id);
   string resp;
   if(!HttpGet(url, resp)) return false;

   CJAVal root;
   if(!root.Deserialize(resp)) return false;
   if(!root["ok"].ToBool()) return false;

   // Check for pinned_message
   string pinned_text = root["result"]["pinned_message"]["text"].ToStr();
   if(pinned_text == "") return false;

   pinned_msg_id = root["result"]["pinned_message"]["message_id"].ToInt();

   // Look for our lock marker: "NL_EA_LOCK:12345678"
   int pos = StringFind(pinned_text, "NL_EA_LOCK:");
   if(pos < 0) return false;

   string after = StringSubstr(pinned_text, pos + 11);  // skip "NL_EA_LOCK:"
   // Extract account number (digits until non-digit)
   string acct_str = "";
   for(int i = 0; i < StringLen(after); i++)
     {
      ushort ch = StringGetCharacter(after, i);
      if(ch >= '0' && ch <= '9') acct_str += ShortToString(ch);
      else break;
     }
   if(acct_str == "") return false;
   locked_account = StringToInteger(acct_str);
   return true;
  }

//+------------------------------------------------------------------+
bool CTelegram::PinMessage(long message_id)
  {
   string url  = TG_BASE_URL + m_token + "/pinChatMessage";
   string body = "{\"chat_id\":" + IntegerToString(m_chat_id) +
                 ",\"message_id\":" + IntegerToString(message_id) +
                 ",\"disable_notification\":true}";
   string resp;
   if(!HttpPost(url, body, resp)) { Print("[Telegram] Pin failed"); return false; }

   CJAVal root;
   if(!root.Deserialize(resp)) return false;
   if(!root["ok"].ToBool()) { Print("[Telegram] Pin err: ", root["description"].ToStr()); return false; }
   return true;
  }

//+------------------------------------------------------------------+
bool CTelegram::UnpinMessage(long message_id)
  {
   string url  = TG_BASE_URL + m_token + "/unpinChatMessage";
   string body = "{\"chat_id\":" + IntegerToString(m_chat_id) +
                 ",\"message_id\":" + IntegerToString(message_id) + "}";
   string resp;
   if(!HttpPost(url, body, resp)) { Print("[Telegram] Unpin failed"); return false; }

   CJAVal root;
   if(!root.Deserialize(resp)) return false;
   if(!root["ok"].ToBool()) { Print("[Telegram] Unpin err: ", root["description"].ToStr()); return false; }
   return true;
  }

#endif // NL_EA_TELEGRAM_MQH
