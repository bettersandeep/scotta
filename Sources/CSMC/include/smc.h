#pragma once
#include <stdint.h>

// Returns 0 on success, a kern_return_t, or the negative SMC result byte.
int smc_open(void);
int smc_read(const char *key, uint8_t *out, uint32_t *size);
// Writes `size` bytes, zero-padded or truncated to the key's own size.
int smc_write(const char *key, const uint8_t *in, uint32_t size);

// Toggles kIOPMSleepDisabledKey (system and lid sleep). Root only. Returns an IOReturn.
int pm_set_sleep_disabled(int disabled);

// Apple's manual charge limit (PowerUI private framework, macOS 26+). Returns 0 on success.
int pui_get(int *enabled, int *limit);
int pui_set_limit(int pct);   // enables the limit if needed; pct must be one of 80/85/90/95/100
int pui_disable(void);
