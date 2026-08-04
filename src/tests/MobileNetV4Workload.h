#ifndef __MOBILENET_V4_WORKLOAD_H__
#define __MOBILENET_V4_WORKLOAD_H__

#include <cstdint>
#include <string>
#include <vector>

enum class WorkloadOp
{
    POINTWISE_CONV,
    DEPTHWISE_CONV,
    ADD,
    RELU
};

enum class WorkloadPlacement
{
    BANK_SIDE,
    LOGIC_DIE,
    HYBRID
};

struct MobileNetV4Layer
{
    std::string name;
    std::string block;
    WorkloadOp op;
    uint32_t height;
    uint32_t width;
    uint32_t inputChannels;
    uint32_t outputChannels;
    uint32_t kernel;
    uint32_t stride;
    WorkloadPlacement placement;
    std::string source;
};

struct LoweredPIMWorkload
{
    std::string name;
    WorkloadOp sourceOp;
    std::string kernel;
    uint64_t invocations;
    uint64_t inputDim;
    uint64_t outputDim;
    uint64_t paddedInputDim;
    uint64_t paddedOutputDim;
    uint64_t logicalElements;
    uint64_t paddedElements;
    uint64_t macs;
    bool supported;
    std::string reason;
};

struct DepthwiseTapLayout
{
    uint32_t outputHeight;
    uint32_t outputWidth;
    uint32_t channels;
    uint32_t kernel;
    std::vector<std::vector<float>> inputTapPlanes;
    std::vector<std::vector<float>> weightTapPlanes;
};

struct WorkloadTensorShape
{
    uint32_t height;
    uint32_t width;
    uint32_t channels;
};

struct WorkloadStageTransfer
{
    WorkloadPlacement source;
    WorkloadPlacement destination;
    uint64_t bytes;
    uint64_t cycles;
};

struct WorkloadExecutionStage
{
    MobileNetV4Layer layer;
    WorkloadTensorShape input;
    WorkloadTensorShape output;
    bool hasInputTransfer;
    WorkloadStageTransfer inputTransfer;
};

struct WorkloadExecutionPlan
{
    std::string block;
    std::vector<WorkloadExecutionStage> stages;
    uint64_t totalTransferBytes;
    uint64_t totalTransferCycles;
};

class MobileNetV4Workload
{
  public:
    static std::vector<MobileNetV4Layer> loadCsv(const std::string& path);
    static LoweredPIMWorkload lower(const MobileNetV4Layer& layer, uint32_t channels = 64,
                                    uint32_t ranks = 1, uint32_t banks = 16,
                                    uint32_t grfs = 8, uint32_t lanesPerBurst = 16,
                                    uint32_t pimBlocksPerChannel = 8);
    static DepthwiseTapLayout makeDepthwiseTapLayout(const std::vector<float>& input,
                                                     const std::vector<float>& weights,
                                                     uint32_t height, uint32_t width,
                                                     uint32_t channels, uint32_t kernel,
                                                     uint32_t stride);
    static std::vector<float> depthwiseReference(const std::vector<float>& input,
                                                 const std::vector<float>& weights,
                                                 uint32_t height, uint32_t width,
                                                 uint32_t channels, uint32_t kernel,
                                                 uint32_t stride);
    static std::vector<float> pointwiseReference(const std::vector<float>& input,
                                                 const std::vector<float>& weights,
                                                 uint32_t height, uint32_t width,
                                                 uint32_t inputChannels,
                                                 uint32_t outputChannels);
    static WorkloadExecutionPlan buildExecutionPlan(
        const std::vector<MobileNetV4Layer>& layers, const std::string& block,
        uint64_t interconnectBytesPerCycle, uint32_t bytesPerElement = 2,
        WorkloadPlacement initialPlacement = WorkloadPlacement::BANK_SIDE);
};

#endif
