#ifndef SW_AUDIO_RING_H
#define SW_AUDIO_RING_H
#include <stddef.h>
#include <stdint.h>

typedef struct SWAudioRing SWAudioRing;
SWAudioRing *SWAudioRingCreate(size_t capacity);
void SWAudioRingDestroy(SWAudioRing *ring);
// Single producer; never allocates, locks, or waits. Drops a whole block if full.
void SWAudioRingWrite(SWAudioRing *ring, const float *input, size_t count, size_t stride,
                      double startTime, double sampleRate);
// Single consumer. Timestamps belong to samples, even if the producer advances.
size_t SWAudioRingRead(SWAudioRing *ring, float *output, size_t maximum, double *endTime);
size_t SWAudioRingAvailable(SWAudioRing *ring);
uint64_t SWAudioRingDropped(SWAudioRing *ring);
size_t SWAudioRingLastBlockSize(SWAudioRing *ring);
#endif
