#!/usr/bin/env python3
"""Stobe.dll round 18b (feature 2): TTS volume boost and distance-fade setting
(STOBE's own Settings window, not Kenshi's).

(a) TTS Volume range 0-200 % (was 0-100). Above 100 % the samples are amplified;
    the existing per-format clamping prevents overflow (loud lines may clip).
(c) New "TTS fade distance %" (25-400, default 100): scales how far TTS carries
    before fading/muting by camera distance (100 = previous behaviour).
    Ini: [Settings] TTSFadePercent. Shares the TTS Volume row (two boxes) so the
    window layout doesn't grow.

Usage: patch_dll_round18b.py <STOBE-src root>
"""
import sys, pathlib

root = pathlib.Path(sys.argv[1]) / "src"

def patch(rel, pairs):
    f = root / rel
    s = f.read_text()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, f"{rel}: anchor count {n}: {old[:70]!r}"
        s = s.replace(old, new)
    f.write_text(s)
    print("patched", f)

patch("Globals.cpp", [("int g_ttsVolumePercent = 100;",
    "int g_ttsVolumePercent = 100;\nint g_ttsFadePercent = 100; // TTS distance fade range, % of default (round 18b)")])
patch("Globals.h", [("extern int g_ttsVolumePercent;",
    "extern int g_ttsVolumePercent;\nextern int g_ttsFadePercent;")])

patch("Functions.cpp", [
    ("""int ClampTtsVolumePercent(int volumePercent) {
  if (volumePercent < 0) {
    return 0;
  }
  if (volumePercent > 100) {
    return 100;
  }""",
     """int ClampTtsVolumePercent(int volumePercent) {
  if (volumePercent < 0) {
    return 0;
  }
  if (volumePercent > 200) { // 0-200 %: above 100 boosts (round 18b)
    return 200;
  }"""),
    ("  farDistanceUnits *= kPlaybackRangeMultiplier;\n",
     "  farDistanceUnits *= kPlaybackRangeMultiplier;\n"
     "  {\n"
     "    int fadePercent = g_ttsFadePercent < 25 ? 25 : (g_ttsFadePercent > 400 ? 400 : g_ttsFadePercent);\n"
     "    farDistanceUnits *= static_cast<float>(fadePercent) / 100.0f; // round 18b\n"
     "  }\n"),
])

patch("AudioPlayback.cpp", [
    ("""  if (volumePercent > 100) {
    return 100;
  }
  return volumePercent;""",
     """  if (volumePercent > 200) {
    return 200;
  }
  return volumePercent;"""),
    ("""  if (volumePercent >= 100) {
    return;
  }
  if (volumePercent < 0) {
    volumePercent = 0;
  }""",
     """  if (volumePercent == 100) {
    return;
  }
  if (volumePercent < 0) {
    volumePercent = 0;
  }"""),
    ("  if (volumePercent < 100) {\n    ApplyWavVolumeInPlace(wavData, volumePercent);",
     "  if (volumePercent != 100) {\n    ApplyWavVolumeInPlace(wavData, volumePercent);"),
])

patch("Utils.cpp", [
    ("""  } else if (g_ttsVolumePercent > 100) {
    g_ttsVolumePercent = 100;
  }""",
     """  } else if (g_ttsVolumePercent > 200) {
    g_ttsVolumePercent = 200;
  }
  g_ttsFadePercent =
      ReadLayeredIniInt(baseIniPath, customIniPath, "Settings", "TTSFadePercent", 100);
  if (g_ttsFadePercent < 25) {
    g_ttsFadePercent = 25;
  } else if (g_ttsFadePercent > 400) {
    g_ttsFadePercent = 400;
  }"""),
    ('      ", TTSVolume=" + ToString(g_ttsVolumePercent) +\n',
     '      ", TTSVolume=" + ToString(g_ttsVolumePercent) +\n      ", TTSFadePercent=" + ToString(g_ttsFadePercent) +\n'),
    ("""  WritePrivateProfileStringA("Settings", "TTSVolume",
                             ToString(g_ttsVolumePercent).c_str(),
                             iniPath.c_str());""",
     """  WritePrivateProfileStringA("Settings", "TTSVolume",
                             ToString(g_ttsVolumePercent).c_str(),
                             iniPath.c_str());
  WritePrivateProfileStringA("Settings", "TTSFadePercent",
                             ToString(g_ttsFadePercent).c_str(),
                             iniPath.c_str());"""),
])

patch("SettingsWindow.cpp", [
    ("MyGUI::EditBox *g_ttsVolumeEdit = nullptr;",
     "MyGUI::EditBox *g_ttsVolumeEdit = nullptr;\nMyGUI::EditBox *g_ttsFadeEdit = nullptr;"),
    ("""  if (g_ttsVolumeEdit) {
    g_ttsVolumeEdit->setCaption(
        WideFromUtf8(ToString(g_ttsVolumePercent)).c_str());
  }""",
     """  if (g_ttsVolumeEdit) {
    g_ttsVolumeEdit->setCaption(
        WideFromUtf8(ToString(g_ttsVolumePercent)).c_str());
  }
  if (g_ttsFadeEdit) {
    g_ttsFadeEdit->setCaption(
        WideFromUtf8(ToString(g_ttsFadePercent)).c_str());
  }"""),
    ("""  int ttsVolume = ParseIntOrDefault(
      g_ttsVolumeEdit ? g_ttsVolumeEdit->getCaption() : "",
      g_ttsVolumePercent);""",
     """  int ttsVolume = ParseIntOrDefault(
      g_ttsVolumeEdit ? g_ttsVolumeEdit->getCaption() : "",
      g_ttsVolumePercent);
  int ttsFade = ParseIntOrDefault(
      g_ttsFadeEdit ? g_ttsFadeEdit->getCaption() : "",
      g_ttsFadePercent);"""),
    ("  g_ttsVolumePercent = ClampInt(ttsVolume, 0, 100);",
     "  g_ttsVolumePercent = ClampInt(ttsVolume, 0, 200);\n  g_ttsFadePercent = ClampInt(ttsFade, 25, 400);"),
    ("  g_ttsVolumeEdit = nullptr;\n  g_boredRangeEdit = nullptr;",
     "  g_ttsVolumeEdit = nullptr;\n  g_ttsFadeEdit = nullptr;\n  g_boredRangeEdit = nullptr;"),
    ("""  CreateLabel(client, labelX, y, labelW, rowH, "TTS Volume (0-100)",
              "Stobe_Plugin_TtsVolumeLabel");
  g_ttsVolumeEdit = client->createWidgetReal<MyGUI::EditBox>(
      "Kenshi_EditBox", fieldX, y, fieldW, rowH,
      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_Plugin_TtsVolumeEdit");""",
     """  CreateLabel(client, labelX, y, labelW, rowH, "TTS Volume % (0-200) / Fade %",
              "Stobe_Plugin_TtsVolumeLabel");
  g_ttsVolumeEdit = client->createWidgetReal<MyGUI::EditBox>(
      "Kenshi_EditBox", fieldX, y, fieldW * 0.48f, rowH,
      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_Plugin_TtsVolumeEdit");
  g_ttsFadeEdit = client->createWidgetReal<MyGUI::EditBox>(
      "Kenshi_EditBox", fieldX + fieldW * 0.52f, y, fieldW * 0.48f, rowH,
      MyGUI::Align::Top | MyGUI::Align::Left, "Stobe_Plugin_TtsFadeEdit");"""),
])
