#ifndef C_LIP_INFERENCE_H
#define C_LIP_INFERENCE_H

#include <stddef.h>
#include <stdbool.h>

typedef struct LipInferenceRun LipInferenceRun;

typedef struct {
    float *values;
    size_t value_count;
    size_t time_steps;
    size_t vocabulary_size;
} LipInferenceOutput;

enum {
    LIP_INFERENCE_OK = 0,
    LIP_INFERENCE_ERROR = 1,
    LIP_INFERENCE_CANCELLED = 2
};

LipInferenceRun *LipInferenceCreate(char *error, size_t error_capacity);
void LipInferenceCancel(LipInferenceRun *run);
bool LipInferenceIsCancelled(LipInferenceRun *run);

// One invocation per run. Cancel may run concurrently; destroy only after recognize returns.
int LipInferenceRecognize(LipInferenceRun *run, const char *model_path,
                         const float *frames, size_t frame_count, size_t value_count,
                         LipInferenceOutput *output, char *error, size_t error_capacity);
void LipInferenceFreeOutput(LipInferenceOutput *output);
void LipInferenceDestroy(LipInferenceRun *run);

#endif
