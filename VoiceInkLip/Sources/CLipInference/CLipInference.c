#include "CLipInference.h"
#include <onnxruntime/onnxruntime_c_api.h>
#include <math.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct LipInferenceRun {
    const OrtApi *api;
    OrtRunOptions *run_options;
    OrtSessionOptions *session_options;
    pthread_mutex_t lock;
    bool cancelled;
};

static void set_error(char *error, size_t capacity, const char *message) {
    if (error != NULL && capacity > 0) snprintf(error, capacity, "%s", message);
}

static bool check_status(const OrtApi *api, OrtStatus *status, char *error, size_t capacity) {
    if (status == NULL) return true;
    set_error(error, capacity, api->GetErrorMessage(status));
    api->ReleaseStatus(status);
    return false;
}

LipInferenceRun *LipInferenceCreate(char *error, size_t error_capacity) {
    const OrtApi *api = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (api == NULL) {
        set_error(error, error_capacity, "ONNX Runtime API 24 is unavailable.");
        return NULL;
    }
    LipInferenceRun *run = calloc(1, sizeof(*run));
    if (run == NULL) {
        set_error(error, error_capacity, "Could not allocate the lip inference run.");
        return NULL;
    }
    run->api = api;
    if (pthread_mutex_init(&run->lock, NULL) != 0) {
        set_error(error, error_capacity, "Could not initialize the lip inference lock.");
        free(run);
        return NULL;
    }
#define SETUP(call) if (!check_status(api, (call), error, error_capacity)) goto failed
    SETUP(api->CreateRunOptions(&run->run_options));
    SETUP(api->CreateSessionOptions(&run->session_options));
    // Four intra-op threads include the calling worker. Sequential execution needs no inter-op pool.
    SETUP(api->SetIntraOpNumThreads(run->session_options, 4));
    SETUP(api->SetInterOpNumThreads(run->session_options, 1));
    SETUP(api->SetSessionExecutionMode(run->session_options, ORT_SEQUENTIAL));
    SETUP(api->AddSessionConfigEntry(run->session_options, "session.intra_op.allow_spinning", "0"));
    SETUP(api->AddSessionConfigEntry(run->session_options, "session.inter_op.allow_spinning", "0"));
#undef SETUP
    return run;
failed:
    LipInferenceDestroy(run);
    return NULL;
}

void LipInferenceCancel(LipInferenceRun *run) {
    pthread_mutex_lock(&run->lock);
    run->cancelled = true;
    // Both public APIs are designed to signal work executing on another thread.
    OrtStatus *status = run->api->RunOptionsSetTerminate(run->run_options);
    if (status != NULL) run->api->ReleaseStatus(status);
    status = run->api->SessionOptionsSetLoadCancellationFlag(run->session_options, true);
    if (status != NULL) run->api->ReleaseStatus(status);
    pthread_mutex_unlock(&run->lock);
}

bool LipInferenceIsCancelled(LipInferenceRun *run) {
    pthread_mutex_lock(&run->lock);
    bool cancelled = run->cancelled;
    pthread_mutex_unlock(&run->lock);
    return cancelled;
}

int LipInferenceRecognize(LipInferenceRun *run, const char *model_path,
                         const float *frames, size_t frame_count, size_t value_count,
                         LipInferenceOutput *output, char *error, size_t error_capacity) {
    const OrtApi *api = run->api;
    OrtEnv *env = NULL;
    OrtSession *session = NULL;
    OrtValue *input = NULL;
    OrtValue *result = NULL;
    OrtTensorTypeAndShapeInfo *shape = NULL;
    OrtAllocator *allocator = NULL;
    void *input_data = NULL;
    void *result_data = NULL;
    int outcome = LIP_INFERENCE_ERROR;
    *output = (LipInferenceOutput){0};
    if (LipInferenceIsCancelled(run)) return LIP_INFERENCE_CANCELLED;
    if (model_path == NULL || frames == NULL || frame_count == 0 ||
        frame_count > INT64_MAX || frame_count > SIZE_MAX / (88 * 88) ||
        value_count != frame_count * 88 * 88 || value_count > SIZE_MAX / sizeof(float)) {
        set_error(error, error_capacity, "Expected a float32 mouth tensor with shape [1,T,88,88].");
        return LIP_INFERENCE_ERROR;
    }
    for (size_t index = 0; index < value_count; ++index) {
        if (!isfinite(frames[index])) {
            set_error(error, error_capacity, "The mouth tensor contains a non-finite value.");
            return LIP_INFERENCE_ERROR;
        }
        if ((index & 65535) == 0 && LipInferenceIsCancelled(run)) return LIP_INFERENCE_CANCELLED;
    }
#define CHECK(call) if (!check_status(api, (call), error, error_capacity)) goto finished
    CHECK(api->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "VoiceInkLip", &env));
    if (LipInferenceIsCancelled(run)) goto finished;
    CHECK(api->CreateSession(env, model_path, run->session_options, &session));
    if (LipInferenceIsCancelled(run)) goto finished;
    size_t input_count = 0;
    size_t output_count = 0;
    CHECK(api->SessionGetInputCount(session, &input_count));
    CHECK(api->SessionGetOutputCount(session, &output_count));
    if (input_count != 1 || output_count != 1) {
        set_error(error, error_capacity, "The visual CTC model must have one input and one output.");
        goto finished;
    }
    CHECK(api->GetAllocatorWithDefaultOptions(&allocator));
    const int64_t input_shape[] = {1, (int64_t)frame_count, 88, 88};
    CHECK(api->CreateTensorAsOrtValue(allocator, input_shape, 4,
                                    ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input));
    CHECK(api->GetTensorMutableData(input, &input_data));
    memcpy(input_data, frames, value_count * sizeof(float));
    if (LipInferenceIsCancelled(run)) goto finished;
    const char *input_names[] = {"mouth"};
    const char *output_names[] = {"log_probs"};
    const OrtValue *inputs[] = {input};
    CHECK(api->Run(session, run->run_options, input_names, inputs, 1,
                   output_names, 1, &result));
    if (LipInferenceIsCancelled(run)) goto finished;
    CHECK(api->GetTensorTypeAndShape(result, &shape));
    ONNXTensorElementDataType element_type;
    size_t rank = 0;
    CHECK(api->GetTensorElementType(shape, &element_type));
    CHECK(api->GetDimensionsCount(shape, &rank));
    if (element_type != ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT || rank != 3) {
        set_error(error, error_capacity, "Expected float32 visual CTC output with rank three.");
        goto finished;
    }
    int64_t dimensions[3];
    CHECK(api->GetDimensions(shape, dimensions, 3));
    if (dimensions[0] != 1 || dimensions[1] != (int64_t)frame_count || dimensions[2] != 1049 ||
        frame_count > SIZE_MAX / (1049 * sizeof(float))) {
        set_error(error, error_capacity, "Expected visual CTC output with shape [1,T,1049].");
        goto finished;
    }
    size_t result_count = 0;
    CHECK(api->GetTensorShapeElementCount(shape, &result_count));
    if (result_count != frame_count * 1049) {
        set_error(error, error_capacity, "The visual CTC output buffer does not match its shape.");
        goto finished;
    }
    CHECK(api->GetTensorMutableData(result, &result_data));
    const float *scores = result_data;
    for (size_t index = 0; index < result_count; ++index) {
        if (!isfinite(scores[index])) {
            set_error(error, error_capacity, "The visual CTC output contains a non-finite value.");
            goto finished;
        }
        if ((index & 65535) == 0 && LipInferenceIsCancelled(run)) goto finished;
    }
    output->values = malloc(result_count * sizeof(float));
    if (output->values == NULL) {
        set_error(error, error_capacity, "Could not allocate the visual CTC output.");
        goto finished;
    }
    memcpy(output->values, result_data, result_count * sizeof(float));
    output->value_count = result_count;
    output->time_steps = frame_count;
    output->vocabulary_size = 1049;
    outcome = LIP_INFERENCE_OK;
finished:
#undef CHECK
    if (shape != NULL) api->ReleaseTensorTypeAndShapeInfo(shape);
    if (result != NULL) api->ReleaseValue(result);
    if (input != NULL) api->ReleaseValue(input);
    if (session != NULL) api->ReleaseSession(session);
    if (env != NULL) api->ReleaseEnv(env);
    if (LipInferenceIsCancelled(run)) outcome = LIP_INFERENCE_CANCELLED;
    if (outcome != LIP_INFERENCE_OK) LipInferenceFreeOutput(output);
    return outcome;
}

void LipInferenceFreeOutput(LipInferenceOutput *output) {
    free(output->values);
    *output = (LipInferenceOutput){0};
}

void LipInferenceDestroy(LipInferenceRun *run) {
    if (run == NULL) return;
    if (run->run_options != NULL) run->api->ReleaseRunOptions(run->run_options);
    if (run->session_options != NULL) run->api->ReleaseSessionOptions(run->session_options);
    pthread_mutex_destroy(&run->lock);
    free(run);
}
