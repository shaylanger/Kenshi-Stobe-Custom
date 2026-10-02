cmake_minimum_required(VERSION 3.20)
project(ProfessionGearProgression VERSION 0.1.0 LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
option(PGP_BUILD_PLUGIN "Build the RE_Kenshi plugin DLL" ON)
option(PGP_BUILD_TESTS "Build SDK-independent tests" ON)

add_library(ProfessionGearCore STATIC src/ProfessionGearCore.cpp)
target_include_directories(ProfessionGearCore PUBLIC "\${CMAKE_CURRENT_SOURCE_DIR}/src")

if(PGP_BUILD_PLUGIN)
  if(NOT KENSHI_LIB_INCLUDE_DIR)
    message(FATAL_ERROR "KENSHI_LIB_INCLUDE_DIR is required when PGP_BUILD_PLUGIN=ON.")
  endif()
  if(NOT KENSHI_LIB_LIBRARY)
    message(FATAL_ERROR "KENSHI_LIB_LIBRARY is required when PGP_BUILD_PLUGIN=ON.")
  endif()
  if(NOT BOOST_INCLUDE_DIR)
    message(FATAL_ERROR "BOOST_INCLUDE_DIR is required when PGP_BUILD_PLUGIN=ON.")
  endif()
  get_filename_component(_kenshi_lib_dir "\${KENSHI_LIB_LIBRARY}" DIRECTORY)
  get_filename_component(_kenshi_lib_root "\${_kenshi_lib_dir}" DIRECTORY)
  set(_sdk_mygui_lib "\${_kenshi_lib_dir}/Libraries/mygui/MyGUIEngine_x64.lib")
  set(_sdk_ogre_lib "\${_kenshi_lib_dir}/Libraries/ogre/OgreMain_x64.lib")
  set(_candidate_lib_dirs
    "\${_kenshi_lib_dir}"
    "\${_kenshi_lib_dir}/Libraries"
    "\${_kenshi_lib_dir}/Libraries/mygui"
    "\${_kenshi_lib_dir}/Libraries/ogre"
    "\${_kenshi_lib_root}/KenshiLib Source/Libraries"
    "\${_kenshi_lib_root}/KenshiLib Source/Libraries/mygui"
    "\${_kenshi_lib_root}/KenshiLib Source/Libraries/ogre"
    "\${_kenshi_lib_root}/KenshiLib_Examples_deps/KenshiLib/Libraries")
  if(EXISTS "\${_sdk_mygui_lib}")
    set(MYGUI_ENGINE_LIBRARY "\${_sdk_mygui_lib}")
  else()
    find_library(MYGUI_ENGINE_LIBRARY NAMES MyGUIEngine_x64 MyGUIEngine_x64.lib PATHS \${_candidate_lib_dirs} NO_DEFAULT_PATH)
  endif()
  if(EXISTS "\${_sdk_ogre_lib}")
    set(OGRE_MAIN_LIBRARY "\${_sdk_ogre_lib}")
  else()
    find_library(OGRE_MAIN_LIBRARY NAMES OgreMain_x64 OgreMain_x64.lib PATHS \${_candidate_lib_dirs} NO_DEFAULT_PATH)
  endif()
  if(NOT MYGUI_ENGINE_LIBRARY)
    message(FATAL_ERROR "MyGUIEngine_x64.lib not found.")
  endif()
  if(NOT OGRE_MAIN_LIBRARY)
    message(FATAL_ERROR "OgreMain_x64.lib not found.")
  endif()
  add_library(ProfessionGearProgression SHARED src/ProfessionGearPlugin.cpp)
  target_include_directories(ProfessionGearProgression PRIVATE
    "\${CMAKE_CURRENT_SOURCE_DIR}/src"
    "\${KENSHI_LIB_INCLUDE_DIR}"
    "\${KENSHI_LIB_INCLUDE_DIR}/ogre"
    "\${KENSHI_LIB_INCLUDE_DIR}/mygui"
    "\${BOOST_INCLUDE_DIR}")
  target_link_libraries(ProfessionGearProgression PRIVATE
    ProfessionGearCore "\${KENSHI_LIB_LIBRARY}" "\${MYGUI_ENGINE_LIBRARY}" "\${OGRE_MAIN_LIBRARY}")
  if(MSVC)
    target_compile_definitions(ProfessionGearProgression PRIVATE UNICODE _UNICODE BOOST_ALL_NO_LIB)
    target_compile_options(ProfessionGearProgression PRIVATE /EHa)
  endif()
  set_target_properties(ProfessionGearProgression PROPERTIES OUTPUT_NAME "ProfessionGearProgression")
endif()

if(PGP_BUILD_TESTS)
  enable_testing()
  add_executable(ProfessionGearTests tests/test_profession_gear.cpp)
  target_link_libraries(ProfessionGearTests PRIVATE ProfessionGearCore)
  add_test(NAME profession_gear_core COMMAND ProfessionGearTests)
endif()
