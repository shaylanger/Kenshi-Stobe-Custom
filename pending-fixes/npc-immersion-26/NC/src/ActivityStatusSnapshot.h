#pragma once

#include <sstream>
#include <string>
#include <vector>

// Read-only, bounded serialization for the Harness activity-status probe.
// Kept header-only so the frozen 57-TU native project gains no new translation
// unit. This deliberately describes only fields owned by ActivityController.
namespace Stobe { namespace ActivityStatusSnapshot {

static const size_t kMaxIdBytes = 96;
static const size_t kMaxWorldBytes = 96;
static const size_t kMaxSourceBytes = 128;
static const size_t kMaxResourceBytes = 128;
static const size_t kMaxReasonBytes = 256;
static const size_t kMaxTargets = 64;
static const size_t kMaxRows = 3;
static const size_t kMaxIndexedRows = 256;
static const size_t kMaxSnapshotBytes = 16384;
static const unsigned long kMaxSnapshotAgeMs = 2000;

struct Row {
  std::string id, worldId, kind, sourceId, resourceId, phase, reason;
  std::string campZoneCandidateId, campZoneDigest;
  std::string routeCandidateId, routeWorldId, routeKind, routeLabel;
  std::string currentCandidateId, pendingCommand, pendingRequestId;
  std::string nativeReceiptStatus, nativeReceiptReason, nativeTaskName, nativeActionName, mineItem;
  unsigned int actor, requester, quantity, revision, routeActor, currentTarget, delivered;
  unsigned long scopeVersion;
  unsigned int nativeTarget, nativeTaskSubject, nativeActionSubject;
  unsigned int mineActor, mineBuilding, mineOutputBaseline, mineOutputExpected, mineOutputCount, mineCreditedOutput;
  int nativeTaskKey, nativeActionKey;
  unsigned long long gameTs;
  bool cleanupComplete, goalStateAvailable, hasTarget, hasPendingAction, terminal;
  bool nativeEvidenceAvailable, operationTracked, ownedTaskMatches, currentActionMatchesTarget;
  bool targetInFixedSetKnown, targetInFixedSet, targetHostilityKnown, currentTargetHostile;
  bool mineAttributionAvailable, mineLeaseIdentityMatches, mineOutputCountConsistent, mineContributionObserved;
  bool campQualified, campLiveProofValid;
  std::vector<unsigned int> agreedTargets, completedTargets, confirmedDeadTargets;
  Row() : actor(0), requester(0), quantity(0), revision(0), gameTs(0),
          scopeVersion(1),
          routeActor(0), currentTarget(0), delivered(0), cleanupComplete(false),
          goalStateAvailable(false), hasTarget(false), hasPendingAction(false), terminal(false),
          nativeTarget(0), nativeTaskSubject(0), nativeActionSubject(0), mineActor(0), mineBuilding(0),
          mineOutputBaseline(0), mineOutputExpected(0), mineOutputCount(0), mineCreditedOutput(0), nativeTaskKey(-1), nativeActionKey(-1),
          nativeEvidenceAvailable(false), operationTracked(false), ownedTaskMatches(false),
          currentActionMatchesTarget(false), targetInFixedSetKnown(false), targetInFixedSet(false),
          targetHostilityKnown(false), currentTargetHostile(false), mineAttributionAvailable(false),
          mineLeaseIdentityMatches(false), mineOutputCountConsistent(false), mineContributionObserved(false),
          campQualified(false), campLiveProofValid(false) {}
};

inline bool ValidId(const std::string& id) {
  if (id.empty() || id.size() > kMaxIdBytes) return false;
  for (size_t i = 0; i < id.size(); ++i) {
    const unsigned char c = static_cast<unsigned char>(id[i]);
    if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') || c == '_' || c == '-' || c == '.' || c == ':'))
      return false;
  }
  return true;
}

inline bool AppendJsonString(std::ostringstream& out, const std::string& value,
                             size_t maxBytes) {
  if (value.size() > maxBytes) return false;
  static const char hex[] = "0123456789abcdef";
  out << '"';
  for (size_t i = 0; i < value.size(); ++i) {
    const unsigned char c = static_cast<unsigned char>(value[i]);
    if (c == '"' || c == '\\') out << '\\' << static_cast<char>(c);
    else if (c == '\b') out << "\\b";
    else if (c == '\f') out << "\\f";
    else if (c == '\n') out << "\\n";
    else if (c == '\r') out << "\\r";
    else if (c == '\t') out << "\\t";
    else if (c < 0x20) out << "\\u00" << hex[c >> 4] << hex[c & 0x0f];
    else out << static_cast<char>(c);
  }
  out << '"';
  return true;
}

inline bool SerializeRow(const Row& row, std::string& json) {
  if (!ValidId(row.id) || row.worldId.empty() || row.worldId.size() > kMaxWorldBytes ||
      row.kind.empty() || row.kind.size() > 16 || row.sourceId.size() > kMaxSourceBytes ||
      row.resourceId.size() > kMaxResourceBytes || row.phase.empty() || row.phase.size() > 32 ||
      row.reason.size() > kMaxReasonBytes || !row.actor || !row.requester ||
      row.agreedTargets.size() > kMaxTargets || row.routeCandidateId.size() > 96 ||
      row.routeWorldId.size() > kMaxWorldBytes || row.routeKind.size() > 32 ||
      row.routeLabel.size() > 120 || (row.routeActor && row.routeActor != row.actor) ||
      row.routeCandidateId.empty() || row.routeWorldId.empty() || row.routeKind.empty() ||
      row.routeLabel.empty() || row.routeActor != row.actor ||
      row.currentCandidateId.size() > 96 || row.pendingCommand.size() > 32 ||
      row.pendingRequestId.size() > 128 || row.completedTargets.size() > kMaxTargets ||
      row.confirmedDeadTargets.size() > kMaxTargets ||
      (row.campQualified && (row.kind != "ClearGroup" || row.scopeVersion != 3 ||
       row.campZoneCandidateId.size() < 16 || row.campZoneCandidateId.size() > 128 ||
       row.campZoneCandidateId.compare(0,3,"v1:") != 0 || row.campZoneDigest.size() != 64)) ||
      (!row.campQualified && row.scopeVersion != 1) ||
      row.nativeReceiptStatus.size() > 16 || row.nativeReceiptReason.size() > kMaxReasonBytes ||
      row.nativeTaskName.size() > 64 || row.nativeActionName.size() > 64 || row.mineItem.size() > kMaxResourceBytes ||
      (row.hasTarget && (!row.currentTarget || row.currentCandidateId.empty())) ||
      (!row.hasTarget && (row.currentTarget || !row.currentCandidateId.empty())) ||
      (row.hasPendingAction && (row.pendingCommand.empty() || row.pendingRequestId.empty())) ||
      (!row.hasPendingAction && (!row.pendingCommand.empty() || !row.pendingRequestId.empty())))
    return false;
  std::ostringstream out;
  out << "{\"id\":"; if (!AppendJsonString(out, row.id, kMaxIdBytes)) return false;
  out << ",\"worldId\":"; if (!AppendJsonString(out, row.worldId, kMaxWorldBytes)) return false;
  out << ",\"revision\":" << row.revision << ",\"actor\":" << row.actor
      << ",\"requester\":" << row.requester << ",\"kind\":";
  if (!AppendJsonString(out, row.kind, 16)) return false;
  out << ",\"sourceId\":"; if (!AppendJsonString(out, row.sourceId, kMaxSourceBytes)) return false;
  out << ",\"resourceId\":"; if (!AppendJsonString(out, row.resourceId, kMaxResourceBytes)) return false;
  out << ",\"quantity\":" << row.quantity << ",\"scopeVersion\":" << row.scopeVersion;
  if(row.campQualified) {
    out << ",\"campZone\":{\"candidateId\":";
    if(!AppendJsonString(out,row.campZoneCandidateId,128)) return false;
    out << ",\"scopeDigest\":";
    if(!AppendJsonString(out,row.campZoneDigest,64)) return false;
    out << "}";
  }
  out << ",\"campLiveProofValid\":" << (row.campQualified && row.campLiveProofValid ? "true" : "false")
      << ",\"campCompletionMeaning\":";
  if(!AppendJsonString(out,row.campQualified?"fixed_agreed_targets_only":"not_applicable",32)) return false;
  out
      << ",\"agreedTargets\":[";
  for (size_t i = 0; i < row.agreedTargets.size(); ++i) {
    if (!row.agreedTargets[i]) return false;
    if (i) out << ',';
    out << row.agreedTargets[i];
  }
  out << "],\"route\":{\"candidateId\":";
  if (!AppendJsonString(out, row.routeCandidateId, 96)) return false;
  out << ",\"worldId\":"; if (!AppendJsonString(out, row.routeWorldId, kMaxWorldBytes)) return false;
  out << ",\"kind\":"; if (!AppendJsonString(out, row.routeKind, 32)) return false;
  out << ",\"label\":"; if (!AppendJsonString(out, row.routeLabel, 120)) return false;
  out << ",\"actor\":" << row.routeActor << "},\"goalStateAvailable\":"
      << (row.goalStateAvailable ? "true" : "false") << ",\"currentTarget\":";
  if (row.goalStateAvailable && row.hasTarget) {
    out << "{\"serial\":" << row.currentTarget << ",\"candidateId\":";
    if (!AppendJsonString(out, row.currentCandidateId, 96)) return false;
    out << '}';
  } else out << "null";
  out << ",\"pendingAction\":";
  if (row.goalStateAvailable && row.hasPendingAction) {
    out << "{\"command\":"; if (!AppendJsonString(out, row.pendingCommand, 32)) return false;
    out << ",\"requestId\":"; if (!AppendJsonString(out, row.pendingRequestId, 128)) return false;
    out << '}';
  } else out << "null";
  out << ",\"delivered\":";
  if (row.goalStateAvailable) out << row.delivered; else out << "null";
  out << ",\"terminal\":";
  if (row.goalStateAvailable) out << (row.terminal ? "true" : "false"); else out << "null";
  out << ",\"completedTargets\":";
  if (row.goalStateAvailable) {
    out << '[';
    for (size_t i=0;i<row.completedTargets.size();++i) { if(!row.completedTargets[i]) return false; if(i) out << ','; out << row.completedTargets[i]; }
    out << ']';
  } else out << "null";
  out << ",\"confirmedDeadTargets\":";
  if (row.goalStateAvailable) {
    out << '[';
    for (size_t i=0;i<row.confirmedDeadTargets.size();++i) { if(!row.confirmedDeadTargets[i]) return false; if(i) out << ','; out << row.confirmedDeadTargets[i]; }
    out << ']';
  } else out << "null";
  out << ",\"nativeAttribution\":";
  if (!row.goalStateAvailable || !row.nativeEvidenceAvailable || !row.operationTracked) out << "null";
  else {
    out << "{\"requestId\":"; if (!AppendJsonString(out,row.pendingRequestId,128)) return false;
    out << ",\"receipt\":{\"status\":"; if (!AppendJsonString(out,row.nativeReceiptStatus,16)) return false;
    out << ",\"reason\":"; if (!AppendJsonString(out,row.nativeReceiptReason,kMaxReasonBytes)) return false;
    out << "},\"targetSerial\":" << row.nativeTarget << ",\"nativeOrder\":";
    if (row.ownedTaskMatches) {
      out << "{\"task\":"; if (!AppendJsonString(out,row.nativeTaskName,64)) return false;
      out << ",\"taskKey\":" << row.nativeTaskKey << ",\"subjectSerial\":" << row.nativeTaskSubject << '}';
    } else out << "null";
    out << ",\"currentAction\":";
    if (row.nativeActionKey >= 0) {
      out << "{\"task\":"; if (!AppendJsonString(out,row.nativeActionName,64)) return false;
      out << ",\"taskKey\":" << row.nativeActionKey << ",\"subjectSerial\":" << row.nativeActionSubject
          << ",\"matchesTarget\":" << (row.currentActionMatchesTarget ? "true" : "false") << '}';
    } else out << "null";
    out << ",\"clearGroup\":";
    if (row.targetInFixedSetKnown) {
      out << "{\"targetInFixedSet\":" << (row.targetInFixedSet ? "true" : "false") << ",\"hostility\":";
      if (row.targetHostilityKnown) out << (row.currentTargetHostile ? "true" : "false"); else out << "null";
      out << '}';
    } else out << "null";
    out << ",\"mine\":";
    if (!row.mineAttributionAvailable) out << "null";
    else {
      out << "{\"actorSerial\":" << row.mineActor << ",\"buildingSerial\":" << row.mineBuilding
          << ",\"item\":"; if (!AppendJsonString(out,row.mineItem,kMaxResourceBytes)) return false;
      out << ",\"leaseIdentityMatches\":" << (row.mineLeaseIdentityMatches ? "true" : "false")
          << ",\"baselineCount\":" << row.mineOutputBaseline << ",\"expectedCount\":" << row.mineOutputExpected
          << ",\"outputCount\":" << row.mineOutputCount << ",\"outputCountConsistent\":"
          << (row.mineOutputCountConsistent ? "true" : "false") << ",\"creditedOutputAvailable\":";
      if(row.mineLeaseIdentityMatches && row.mineOutputCountConsistent)out << row.mineCreditedOutput;else out << "null";
      out
          << ",\"contributionObservedSinceLastOutput\":" << (row.mineContributionObserved ? "true" : "false") << '}';
    }
    out << '}';
  }
  out << ",\"phase\":"; if (!AppendJsonString(out, row.phase, 32)) return false;
  out << ",\"reason\":"; if (!AppendJsonString(out, row.reason, kMaxReasonBytes)) return false;
  out << ",\"cleanupComplete\":" << (row.cleanupComplete ? "true" : "false")
      << ",\"gameTs\":" << row.gameTs << '}';
  json = out.str();
  return json.size() <= 4096;
}

inline std::string UnsupportedFields() {
  return "[]";
}

inline bool SerializeOne(const Row& row, std::string& json) {
  std::string encoded;
  if (!SerializeRow(row, encoded)) return false;
  std::ostringstream out;
  out << "{\"worldId\":";
  if (!AppendJsonString(out, row.worldId, kMaxWorldBytes)) return false;
  out << ",\"gameTs\":" << row.gameTs << ",\"activity\":" << encoded
      << ",\"unsupported\":" << UnsupportedFields() << '}';
  json = out.str();
  return json.size() <= kMaxSnapshotBytes;
}

inline bool SerializeAll(const std::string& worldId, unsigned long long gameTs,
                         const std::vector<Row>& rows, std::string& json,
                         bool sourceTruncated=false) {
  if (worldId.size() > kMaxWorldBytes || rows.size() > 4096) return false;
  std::ostringstream out;
  out << "{\"worldId\":";
  if (!AppendJsonString(out, worldId, kMaxWorldBytes)) return false;
  out << ",\"gameTs\":" << gameTs << ",\"activities\":[";
  const size_t count = rows.size() < kMaxRows ? rows.size() : kMaxRows;
  for (size_t i = 0; i < count; ++i) {
    std::string encoded;
    if (!SerializeRow(rows[i], encoded)) return false;
    if (i) out << ',';
    out << encoded;
    if (static_cast<size_t>(out.tellp()) > kMaxSnapshotBytes - 256) return false;
  }
  out << "],\"truncated\":" << (sourceTruncated || rows.size() > count ? "true" : "false")
      << ",\"unsupported\":" << UnsupportedFields() << '}';
  json = out.str();
  return json.size() <= kMaxSnapshotBytes;
}

inline std::string Error(const char* reason) {
  std::ostringstream out;
  out << "{\"error\":\"" << reason << "\"}";
  return out.str();
}

inline bool SnapshotAgeValid(unsigned long ageMs) {
  return ageMs <= kMaxSnapshotAgeMs;
}

inline bool AddSnapshotAge(const std::string& json, unsigned long ageMs,
                           std::string& withAge) {
  if (!SnapshotAgeValid(ageMs) || json.empty() || json.size() >= kMaxSnapshotBytes ||
      json[json.size()-1] != '}') return false;
  std::ostringstream out;
  out << json.substr(0, json.size()-1) << ",\"snapshotAgeMs\":" << ageMs << '}';
  withAge=out.str();
  return withAge.size() <= kMaxSnapshotBytes;
}

} }
