#!/usr/bin/env python3
"""Bug 107: 55 of 135 prompts in run 8 began "You are #HERIKA_NAME#, a character
in the world of Kenshi": the PROMPT_HEAD setting carries a name placeholder and
only the diary code replaced it. Fix: stobeResolveNpcPromptOverrides() fills
#HERIKA_NAME# / {HERIKA_NAME} / #NPC_NAME# with the NPC's name.
Usage: patch_r20_bug107_placeholder.py <StobeServer tree root>"""
import sys, pathlib
root = pathlib.Path(sys.argv[1])

def patch(rel, pairs):
    p = root / rel; s = p.read_text()
    for a, b in pairs:
        if b in s: continue
        assert s.count(a) == 1, f"{rel}: anchor not found: {a[:70]!r}"
        s = s.replace(a, b)
    p.write_text(s); print("patched", p)

patch("lib/chat_helper_functions.php", [
    ("""    $resolvedPromptHead = $npcPromptHead !== '' ? $npcPromptHead : $profilePromptHead;
    if ($resolvedPromptHead === '' && function_exists('getSetting')) {
        $resolvedPromptHead = trim(strval(getSetting('PROMPT_HEAD', '')));
    }

    return [
        'prompt_head' => $resolvedPromptHead,
        'profile_prompt' => $npcProfilePrompt !== '' ? $npcProfilePrompt : $profilePrompt,
    ];""",
     """    $resolvedPromptHead = $npcPromptHead !== '' ? $npcPromptHead : $profilePromptHead;
    if ($resolvedPromptHead === '' && function_exists('getSetting')) {
        $resolvedPromptHead = trim(strval(getSetting('PROMPT_HEAD', '')));
    }
    $resolvedProfilePrompt = $npcProfilePrompt !== '' ? $npcProfilePrompt : $profilePrompt;
    // Bug 107: fill the name placeholders (only the diary code did this).
    $placeholderName = trim(strval($npcData['name'] ?? ($metadata['name'] ?? '')));
    if ($placeholderName !== '') {
        $placeholders = ['#HERIKA_NAME#', '{HERIKA_NAME}', '#NPC_NAME#'];
        $resolvedPromptHead = str_replace($placeholders, $placeholderName, $resolvedPromptHead);
        $resolvedProfilePrompt = str_replace($placeholders, $placeholderName, $resolvedProfilePrompt);
    }

    return [
        'prompt_head' => $resolvedPromptHead,
        'profile_prompt' => $resolvedProfilePrompt,
    ];"""),
])
