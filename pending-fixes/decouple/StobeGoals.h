#pragma once
/* Non-FP gameplay executor moved from KenshiFP (StobeGoals.cpp). Game thread only. */
void StobeGoals_Tick(void *gameWorld);   /* each stable-world PlayerInterface::update */
void StobeGoals_HidePanel(void);         /* world not stable / unloading */
/* implemented in main.cpp (Stobe internals) */
float *StobeGoals_ProximityRadius(void);
long StobeGoals_ChatInterrupt(void);
extern "C" __declspec(dllexport) int StobeFightTruceActive(void);
