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
   void Clear() { update_id=0; chat_id=0; text=""; date=0; }
  };

class CTelegram
  {
private:
   string m_token;
   long   m_chat_id;
   long   m_last_update_id;

   bool   HttpGet(string url, string &resp);
   bool   HttpPost(string url, string body, string &resp);
   string EscapeJson(string s);

public:
          CTelegram() : m_token(""), m_chat_id(0), m_last_update_id(0) {}

   void   Init(string token, long chat_id)
     {
      m_token          = token;
      m_chat_id        = chat_id;
      m_last_update_id = 0;
      Print("[Telegram] Init chat_id=", chat_id);
     }

   int    Poll(STgMessage &out[]);
   bool   Send(string text);
   bool   SendWithMode(string text, string mode_label);
  };

//+------------------------------------------------------------------+
int CTelegram::Poll(STgMessage &out[])
  {
   ArrayResize(out, 0);
   string url = TG_BASE_URL + m_token + "/getUpdates"
                + "?timeout=0&offset=" + IntegerToString(m_last_update_id + 1)
                + "&allowed_updates=[\"message\"]";
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

      string txt = results[i]["message"]["text"].ToStr();
      if(txt == "") continue;

      long cid = results[i]["message"]["chat"]["id"].ToInt();
      if(m_chat_id != 0 && cid != m_chat_id)
        { Print("[Telegram] Ignoring unauthorised chat_id=", cid); continue; }

      ArrayResize(out, count + 1);
      out[count].update_id = uid;
      out[count].chat_id   = cid;
      out[count].text      = txt;
      out[count].date      = (datetime)results[i]["message"]["date"].ToInt();
      count++;
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

#endif // NL_EA_TELEGRAM_MQH
