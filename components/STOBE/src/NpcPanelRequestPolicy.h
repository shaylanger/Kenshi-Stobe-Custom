#ifndef STOBE_NPC_PANEL_REQUEST_POLICY_H
#define STOBE_NPC_PANEL_REQUEST_POLICY_H

#include <string>

namespace StobeNpcPanelRequestPolicy {

inline bool ShouldRefreshForSelection(bool panelOpen,
                                      unsigned int previousSelectionSerial,
                                      unsigned int selectedSerial,
                                      unsigned int targetSerial) {
  return panelOpen && previousSelectionSerial != 0 && selectedSerial != 0 &&
         selectedSerial != previousSelectionSerial &&
         selectedSerial != targetSerial;
}

inline unsigned int SelectionBaselineAfterRequest(bool requestSucceeded,
                                                   unsigned int selectedSerial,
                                                   unsigned int previousSerial) {
  return requestSucceeded ? selectedSerial : previousSerial;
}

inline unsigned int SelectionBaselineAfterTick(bool refreshNeeded,
                                                bool refreshSucceeded,
                                                unsigned int selectedSerial,
                                                unsigned int previousSerial) {
  return refreshNeeded && !refreshSucceeded ? previousSerial : selectedSerial;
}

inline bool ReplyMatches(long replyGeneration, long currentGeneration,
                         const std::string &replyKey,
                         const std::string &currentKey) {
  return replyGeneration == currentGeneration && replyKey == currentKey;
}

} // namespace StobeNpcPanelRequestPolicy

#endif
