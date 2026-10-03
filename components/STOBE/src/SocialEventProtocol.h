#pragma once
#include <map>
#include <string>
#include <vector>
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
        const EntityInfo* actor, const EntityInfo* target, const std::string& factsBody,
        const std::string& witnessesJson = "[]");
    // One witness entry: entity + explicit sensing (REL phase 6). Unknown consciousness = no entry.
    std::string WitnessJson(const EntityInfo& who, const std::string& session, unsigned long epoch,
        bool conscious, bool perceived, int seesActor, int seesTarget, int hearsActor, int task = -1, int prone = -1);
}

// Game-side runtime (Utils.cpp): one capture switch and one sequence for every social post.
bool SocialCaptureEnabled();
void SocialPostStructured(const std::string& kind, const StobeSocial::EntityInfo* actor,
                          const StobeSocial::EntityInfo* target, const std::string& factsBody);
// Same, with witness entries built by the caller (each from StobeSocial::WitnessJson).
void SocialPostStructuredW(const std::string& kind, const StobeSocial::EntityInfo* actor,
                           const StobeSocial::EntityInfo* target, const std::string& factsBody,
                           const std::vector<StobeSocial::EntityInfo>& witnessWho,
                           const std::vector<int>& witnessSense);
#include <vector>
void SocialFocusTouch(unsigned int serial);
void SocialFocusSerials(std::vector<unsigned int>& out, size_t cap);
void SocialFocusReport(size_t focus, size_t resolved, const std::string& unresolved);
// The last character the attack hook saw attacking this victim within maxAgeMs (0 = none).
unsigned int SocialRecentAttacker(unsigned int victimSerial, unsigned long maxAgeMs);
void SocialNoteAttack(unsigned int attackerSerial, unsigned int victimSerial);
