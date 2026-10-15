#pragma once
// Pure JSON builders for the native_ai additions (player_orders, active_job, active_package).
// Facts only; each block carries "observed" so the server can tell "none" from "could not read".
#include <string>
#include <vector>
namespace Stobe { namespace NativeAiOrdersJson {

struct Subject { unsigned serial; std::string name; Subject() : serial(0) {} };
struct OrderRow { std::string type; Subject target; };

inline std::string Esc(const std::string& in, size_t max = 120) {
 std::string o;
 for (size_t i = 0; i < in.size() && o.size() < max; ++i) {
  const unsigned char c = static_cast<unsigned char>(in[i]);
  if (c == '"' || c == '\\') { o += '\\'; o += static_cast<char>(c); }
  else if (c < 0x20 || c == 0x7f) o += ' ';
  else o += static_cast<char>(c);
 }
 return o;
}
inline std::string Num(unsigned n) { char b[16]; int k = 0; if (!n) b[k++] = '0'; char t[16]; int m = 0; while (n) { t[m++] = char('0' + n % 10); n /= 10; } while (m) b[k++] = t[--m]; b[k] = 0; return std::string(b); }
inline std::string SubjectJson(const Subject& s) {
 if (!s.serial) return "null";
 std::string o = "{\"serial\":" + Num(s.serial);
 if (!s.name.empty()) o += ",\"name\":\"" + Esc(s.name, 80) + "\"";
 return o + "}";
}
// player_orders: plain array (server reads $native['player_orders'][]['type']); only the order types the server
// understands are emitted: Follow|Patrol|Guard|Hold. null = could not read, [] = observed, none. Max 4.
inline std::string PlayerOrdersJson(bool observed, const std::vector<OrderRow>& rows) {
 if (!observed) return "null";
 std::string o = "[";
 size_t n = 0;
 for (size_t i = 0; i < rows.size() && n < 4; ++i) {
  const std::string& t = rows[i].type;
  if (t != "Follow" && t != "Patrol" && t != "Guard" && t != "Hold") continue;
  if (n++) o += ",";
  o += "{\"type\":\"" + t + "\",\"target\":" + SubjectJson(rows[i].target) + "}";
 }
 return o + "]";
}
// active_job: the job (permajob/work package) the NPC is currently running, if any.
inline std::string ActiveJobJson(bool observed, const std::string& name) {
 if (!observed) return "{\"observed\":false}";
 if (name.empty()) return "{\"observed\":true,\"name\":null}";
 return "{\"observed\":true,\"name\":\"" + Esc(name, 120) + "\"}";
}
} }
