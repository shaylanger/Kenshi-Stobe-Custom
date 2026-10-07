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
