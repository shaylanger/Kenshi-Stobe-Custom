#pragma once
#include <map>
#include <string>
namespace StobeSocial {
    bool SupportedKind(const std::string& kind);
    // Pure, portable serializer. Unknown knowledge is deliberately absent.
    std::string Envelope(const std::string& campaign, const std::string& session,
        unsigned long epoch, unsigned long sequence, long long gameTs,
        const std::string& kind, unsigned int actorSerial, const std::string& actorName,
        unsigned int targetSerial, const std::string& targetName, const std::string& message);

    // Structured facts (REL phase 2+): explicit roles, actor = who did it, target = who it was done to.
    // Tri-state fields: -1 unknown (sent as null), 0 false, 1 true. Never guessed.
    struct EntityInfo {
        unsigned int serial;
        std::string name, storageId, faction;
        int inPlayerFaction;
        int conscious;
        EntityInfo() : serial(0), inPlayerFaction(-1), conscious(-1) {}
    };
    bool StructuredKind(const std::string& kind);
    std::string JsonString(const std::string& value);           // quoted + escaped
    std::string JsonBool(int triState);                          // true/false/null
    std::string JsonCountMap(const std::map<std::string, int>& counts, size_t cap); // {"key":n,...}, positive counts only
    // factsBody: comma-separated "key":value pairs (may be empty); "source":"structured" is added here.
    std::string StructuredEnvelope(const std::string& campaign, const std::string& session,
        unsigned long epoch, unsigned long sequence, long long gameTs, const std::string& kind,
        const EntityInfo* actor, const EntityInfo* target, const std::string& factsBody);
}

// Game-side runtime (Utils.cpp): one capture switch and one sequence for every social post.
bool SocialCaptureEnabled();
void SocialPostStructured(const std::string& kind, const StobeSocial::EntityInfo* actor,
                          const StobeSocial::EntityInfo* target, const std::string& factsBody);
