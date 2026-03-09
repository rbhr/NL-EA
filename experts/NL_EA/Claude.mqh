//+------------------------------------------------------------------+
//| Claude.mqh  --  Claude API: POST instruction, parse response    |
//| World Tech Edge  --  MT5 NL-EA  --  Step 4                      |
//+------------------------------------------------------------------+
#ifndef NL_EA_CLAUDE_MQH
#define NL_EA_CLAUDE_MQH

#include <JAson.mqh>
#include "TaskQueue.mqh"
#include "JsonParser.mqh"

#define CLAUDE_URL     "https://api.anthropic.com/v1/messages"
#define CLAUDE_MODEL   "claude-sonnet-4-20250514"
#define CLAUDE_MAXTOK  2000
#define CLAUDE_TIMEOUT 30000

struct SClaudeResponse
  {
   bool   success;
   string outcome;
   string outcome_reason;
   string clarification;
   string schema_notes;
   string prompt_version;
   string task_json;
   STask  task;
   bool   task_parsed;
   string raw_response;

   void Clear()
     {
      success=false; outcome=""; outcome_reason=""; clarification="";
      schema_notes=""; prompt_version=""; task_json=""; task_parsed=false;
      raw_response=""; task.Clear();
     }
  };

class CClaude
  {
private:
   string      m_api_key;
   string      m_system_prompt;
   CJsonParser m_parser;

   bool   HttpPost(string body, string &resp);
   string BuildBody(string instruction);
   string EscapeJson(string s);

public:
          CClaude() : m_api_key(""), m_system_prompt("") {}

   void   Init(string api_key, string system_prompt)
     {
      m_api_key       = api_key;
      m_system_prompt = system_prompt;
      Print("[Claude] Init model=", CLAUDE_MODEL);
     }

   bool   Ask(string instruction, SClaudeResponse &resp);
  };

//+------------------------------------------------------------------+
bool CClaude::Ask(string instruction, SClaudeResponse &resp)
  {
   resp.Clear();
   Print("[Claude] Asking: ", StringSubstr(instruction, 0, 80));

   string body = BuildBody(instruction);
   string response = "";
   bool ok = false;

   for(int attempt = 1; attempt <= 2; attempt++)
     {
      if(HttpPost(body, response)) { ok = true; break; }
      if(attempt == 1) { Print("[Claude] Retry in 2s..."); Sleep(2000); }
     }

   if(!ok) { Print("[Claude] All attempts failed"); return false; }

   resp.raw_response = response;

   // Anthropic API wraps Claude's reply in {"content":[{"type":"text","text":"..."}]}
   // Extract content[0].text before parsing Claude's JSON
   CJAVal api_root;
   if(!api_root.Deserialize(response))
     {
      Print("[Claude] Failed to parse API wrapper: ", StringSubstr(response, 0, 300));
      return false;
     }
   if(api_root["type"].ToStr() == "error")
     {
      Print("[Claude] API error: ", api_root["error"]["message"].ToStr());
      return false;
     }
   if(api_root["content"].Size() == 0)
     {
      Print("[Claude] Empty content array: ", StringSubstr(response, 0, 300));
      return false;
     }
   string claude_text = api_root["content"][0]["text"].ToStr();
   if(claude_text == "")
     {
      Print("[Claude] Empty text in content[0]: ", StringSubstr(response, 0, 300));
      return false;
     }
   Print("[Claude] Reply: ", StringSubstr(claude_text, 0, 120));

   if(!m_parser.ParseEnvelope(claude_text, resp.outcome, resp.outcome_reason,
                               resp.clarification, resp.schema_notes, resp.prompt_version))
     {
      Print("[Claude] JSON parse failed. Claude said: ", StringSubstr(claude_text, 0, 300));
      return false;
     }

   Print("[Claude] outcome=", resp.outcome, " ver=", resp.prompt_version);

   if(resp.outcome == "ACT")
     {
      if(m_parser.ExtractTaskJson(claude_text, resp.task_json))
         resp.task_parsed = m_parser.ParseTask(resp.task_json, resp.task);
      else
         Print("[Claude] WARNING: ACT but no task object");
     }

   resp.success = true;
   return true;
  }

//+------------------------------------------------------------------+
bool CClaude::HttpPost(string body, string &resp)
  {
   char req[], res[];
   string hdrs = "Content-Type: application/json\r\n"
                 "x-api-key: " + m_api_key + "\r\n"
                 "anthropic-version: 2023-06-01\r\n";

   StringToCharArray(body, req, 0, StringLen(body), CP_UTF8);
   int code = WebRequest("POST", CLAUDE_URL, hdrs, CLAUDE_TIMEOUT, req, res, hdrs);

   if(code == -1)
     {
      Print("[Claude] WebRequest err=", GetLastError(),
            " -- add ", CLAUDE_URL, " to allowed URLs");
      return false;
     }
   if(code != 200)
     {
      resp = CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
      Print("[Claude] HTTP ", code, ": ", resp);
      return false;
     }
   resp = CharArrayToString(res, 0, WHOLE_ARRAY, CP_UTF8);
   return true;
  }

//+------------------------------------------------------------------+
string CClaude::BuildBody(string instruction)
  {
   return "{\"model\":\"" + CLAUDE_MODEL + "\","
          "\"max_tokens\":" + IntegerToString(CLAUDE_MAXTOK) + ","
          "\"system\":\"" + EscapeJson(m_system_prompt) + "\","
          "\"messages\":[{\"role\":\"user\",\"content\":\""
          + EscapeJson(instruction) + "\"}]}";
  }

//+------------------------------------------------------------------+
string CClaude::EscapeJson(string s)
  {
   StringReplace(s, "\\", "\\\\");
   StringReplace(s, "\"", "\\\"");
   StringReplace(s, "\n", "\\n");
   StringReplace(s, "\r", "\\r");
   StringReplace(s, "\t", "\\t");
   return s;
  }

#endif // NL_EA_CLAUDE_MQH
