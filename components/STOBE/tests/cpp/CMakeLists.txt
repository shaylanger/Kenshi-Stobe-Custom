cmake_minimum_required(VERSION 3.20)
project(StobePortableTests LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_executable(stobe_portable_tests
  stobe_text_tests.cpp
  ../../src/AutonomyMonitor.cpp
  ../../src/AutonomyProtocol.cpp
  ../../src/AutonomySafetyProbePolicy.cpp
  ../../src/StobeChatMode.cpp
  ../../src/StobeIdentityRename.cpp
  ../../src/StobeText.cpp
  ../../src/StobeTiming.cpp
  ../../src/StobeEventPolicy.cpp
)

target_include_directories(stobe_portable_tests PRIVATE
  ../../src
)

enable_testing()
add_test(NAME stobe_portable_tests COMMAND stobe_portable_tests)

add_executable(social_protocol_tests social_protocol_tests.cpp ../../src/SocialEventProtocol.cpp)
target_include_directories(social_protocol_tests PRIVATE ../../src)
add_test(NAME social_protocol_tests COMMAND social_protocol_tests)

add_executable(shop_pricing_tests shop_pricing_tests.cpp ../../src/ShopPricing.cpp)
target_include_directories(shop_pricing_tests PRIVATE ../../src)
add_test(NAME shop_pricing_tests COMMAND shop_pricing_tests)

add_executable(drawn_weapon_policy_tests drawn_weapon_policy_tests.cpp)
target_include_directories(drawn_weapon_policy_tests PRIVATE ../../src)
add_test(NAME drawn_weapon_policy_tests COMMAND drawn_weapon_policy_tests)

add_executable(chat_interrupt_policy_tests chat_interrupt_policy_tests.cpp)
target_include_directories(chat_interrupt_policy_tests PRIVATE ../../src)
add_test(NAME chat_interrupt_policy_tests COMMAND chat_interrupt_policy_tests)

add_executable(chat_hotkey_policy_tests chat_hotkey_policy_tests.cpp)
target_include_directories(chat_hotkey_policy_tests PRIVATE ../../src)
add_test(NAME chat_hotkey_policy_tests COMMAND chat_hotkey_policy_tests)

add_executable(activity_candidate_policy_tests activity_candidate_policy_tests.cpp)
target_include_directories(activity_candidate_policy_tests PRIVATE ../../src)
add_test(NAME activity_candidate_policy_tests COMMAND activity_candidate_policy_tests)

add_executable(activity_goal_tests activity_goal_tests.cpp ../../src/ActivityGoals.cpp)
target_include_directories(activity_goal_tests PRIVATE ../../src)
add_test(NAME activity_goal_tests COMMAND activity_goal_tests)

add_executable(npc_panel_request_policy_tests npc_panel_request_policy_tests.cpp)
target_include_directories(npc_panel_request_policy_tests PRIVATE ../../src)
add_test(NAME npc_panel_request_policy_tests COMMAND npc_panel_request_policy_tests)

add_executable(test_inbox_target_ref_tests test_inbox_target_ref_tests.cpp)
target_include_directories(test_inbox_target_ref_tests PRIVATE ../../src)
add_test(NAME test_inbox_target_ref_tests COMMAND test_inbox_target_ref_tests)

add_executable(portrait_fault_injection_tests portrait_fault_injection_tests.cpp)
target_include_directories(portrait_fault_injection_tests PRIVATE ../../src)
add_test(NAME portrait_fault_injection_tests COMMAND portrait_fault_injection_tests)

add_executable(native_travel_receipt_tests native_travel_receipt_tests.cpp)
target_include_directories(native_travel_receipt_tests PRIVATE ../../src)
add_test(NAME native_travel_receipt_tests COMMAND native_travel_receipt_tests)
