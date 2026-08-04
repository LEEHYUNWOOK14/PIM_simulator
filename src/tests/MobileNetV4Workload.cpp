#include "tests/MobileNetV4Workload.h"

#include <fstream>
#include <sstream>
#include <stdexcept>

using namespace std;

namespace
{
vector<string> splitCsvRow(const string& line)
{
    vector<string> fields;
    string field;
    stringstream stream(line);
    while (getline(stream, field, ',')) fields.push_back(field);
    return fields;
}

uint32_t parseUint(const string& value, const string& field, size_t line)
{
    size_t parsed = 0;
    unsigned long result = stoul(value, &parsed);
    if (parsed != value.size())
        throw runtime_error("Invalid " + field + " at workload line " + to_string(line));
    return static_cast<uint32_t>(result);
}

WorkloadOp parseOp(const string& value, size_t line)
{
    if (value == "pointwise_conv") return WorkloadOp::POINTWISE_CONV;
    if (value == "depthwise_conv") return WorkloadOp::DEPTHWISE_CONV;
    if (value == "add") return WorkloadOp::ADD;
    if (value == "relu") return WorkloadOp::RELU;
    throw runtime_error("Unknown operation '" + value + "' at workload line " + to_string(line));
}

WorkloadPlacement parsePlacement(const string& value, size_t line)
{
    if (value == "bank_side") return WorkloadPlacement::BANK_SIDE;
    if (value == "logic_die") return WorkloadPlacement::LOGIC_DIE;
    if (value == "hybrid") return WorkloadPlacement::HYBRID;
    throw runtime_error("Unknown placement '" + value + "' at workload line " +
                        to_string(line));
}

uint64_t roundUp(uint64_t value, uint64_t granularity)
{
    return ((value + granularity - 1) / granularity) * granularity;
}

uint32_t sameOutputSize(uint32_t input, uint32_t stride)
{
    return (input + stride - 1) / stride;
}

int samePadBefore(uint32_t input, uint32_t output, uint32_t kernel, uint32_t stride)
{
    const int total = static_cast<int>((output - 1) * stride + kernel) -
                      static_cast<int>(input);
    return total > 0 ? total / 2 : 0;
}
}  // namespace

vector<MobileNetV4Layer> MobileNetV4Workload::loadCsv(const string& path)
{
    ifstream input(path);
    if (!input) throw runtime_error("Cannot open MobileNetV4 workload: " + path);

    const string expectedHeader =
        "name,block,op,height,width,input_channels,output_channels,kernel,stride,placement,source";
    string line;
    if (!getline(input, line) || line != expectedHeader)
        throw runtime_error("Invalid MobileNetV4 workload header in " + path);

    vector<MobileNetV4Layer> layers;
    for (size_t lineNumber = 2; getline(input, line); lineNumber++)
    {
        if (line.empty() || line[0] == '#') continue;
        vector<string> fields = splitCsvRow(line);
        if (fields.size() != 11)
            throw runtime_error("Expected 11 fields at workload line " + to_string(lineNumber));

        layers.push_back({fields[0], fields[1], parseOp(fields[2], lineNumber),
                          parseUint(fields[3], "height", lineNumber),
                          parseUint(fields[4], "width", lineNumber),
                          parseUint(fields[5], "input_channels", lineNumber),
                          parseUint(fields[6], "output_channels", lineNumber),
                          parseUint(fields[7], "kernel", lineNumber),
                          parseUint(fields[8], "stride", lineNumber),
                          parsePlacement(fields[9], lineNumber), fields[10]});
    }
    return layers;
}

LoweredPIMWorkload MobileNetV4Workload::lower(const MobileNetV4Layer& layer, uint32_t channels,
                                               uint32_t ranks, uint32_t banks, uint32_t grfs,
                                               uint32_t lanesPerBurst,
                                               uint32_t pimBlocksPerChannel)
{
    if (layer.height == 0 || layer.width == 0 || layer.inputChannels == 0 ||
        layer.outputChannels == 0)
        throw invalid_argument("MobileNetV4 workload dimensions must be greater than zero");

    LoweredPIMWorkload result{};
    result.name = layer.name;
    result.sourceOp = layer.op;
    result.logicalElements =
        static_cast<uint64_t>(layer.height) * layer.width * layer.outputChannels;
    const uint64_t elementwiseGranularity =
        static_cast<uint64_t>(channels) * ranks * banks * grfs * lanesPerBurst;

    switch (layer.op)
    {
        case WorkloadOp::POINTWISE_CONV:
            result.kernel = "GEMV";
            result.invocations = static_cast<uint64_t>(layer.height) * layer.width;
            result.inputDim = layer.inputChannels;
            result.outputDim = layer.outputChannels;
            result.paddedInputDim = roundUp(result.inputDim, grfs * lanesPerBurst);
            result.paddedOutputDim =
                roundUp(result.outputDim,
                        static_cast<uint64_t>(channels) * ranks * pimBlocksPerChannel * grfs);
            result.macs = result.invocations * result.inputDim * result.outputDim;
            result.paddedElements = result.logicalElements;
            result.supported = true;
            result.reason = "Each spatial position is lowered to one GEMV";
            break;
        case WorkloadOp::ADD:
        case WorkloadOp::RELU:
            result.kernel = (layer.op == WorkloadOp::ADD) ? "ADD" : "RELU";
            result.invocations = 1;
            result.inputDim = result.logicalElements;
            result.outputDim = result.logicalElements;
            result.paddedInputDim = roundUp(result.inputDim, elementwiseGranularity);
            result.paddedOutputDim = result.paddedInputDim;
            result.paddedElements = roundUp(result.logicalElements, elementwiseGranularity);
            result.supported = true;
            result.reason = "Tensor is padded to the 64-channel PIM execution granularity";
            break;
        case WorkloadOp::DEPTHWISE_CONV:
            result.kernel = "DEPTHWISE_MUL_ADD";
            result.invocations = 1;
            result.inputDim = result.logicalElements;
            result.outputDim = result.logicalElements;
            result.paddedInputDim = roundUp(result.inputDim, elementwiseGranularity);
            result.paddedOutputDim = result.paddedInputDim;
            result.macs = result.logicalElements * layer.kernel * layer.kernel;
            result.paddedElements = result.paddedInputDim;
            result.supported = true;
            result.reason = "Pre-aligned tap planes are lowered to bank-side MUL and ADD";
            break;
    }
    return result;
}

DepthwiseTapLayout MobileNetV4Workload::makeDepthwiseTapLayout(
    const vector<float>& input, const vector<float>& weights, uint32_t height, uint32_t width,
    uint32_t channels, uint32_t kernel, uint32_t stride)
{
    if (height == 0 || width == 0 || channels == 0 || kernel == 0 || kernel % 2 == 0 ||
        stride == 0)
        throw invalid_argument("Depthwise dimensions must be positive and kernel must be odd");
    if (input.size() != static_cast<uint64_t>(height) * width * channels)
        throw invalid_argument("Depthwise NHWC input size does not match its dimensions");
    if (weights.size() != static_cast<uint64_t>(kernel) * kernel * channels)
        throw invalid_argument("Depthwise weight size must be kernel*kernel*channels");

    DepthwiseTapLayout layout{};
    layout.outputHeight = sameOutputSize(height, stride);
    layout.outputWidth = sameOutputSize(width, stride);
    layout.channels = channels;
    layout.kernel = kernel;
    const uint64_t outputElements =
        static_cast<uint64_t>(layout.outputHeight) * layout.outputWidth * channels;
    const uint32_t taps = kernel * kernel;
    layout.inputTapPlanes.assign(taps, vector<float>(outputElements, 0.0f));
    layout.weightTapPlanes.assign(taps, vector<float>(outputElements, 0.0f));

    const int padTop = samePadBefore(height, layout.outputHeight, kernel, stride);
    const int padLeft = samePadBefore(width, layout.outputWidth, kernel, stride);
    for (uint32_t oy = 0; oy < layout.outputHeight; oy++)
        for (uint32_t ox = 0; ox < layout.outputWidth; ox++)
            for (uint32_t c = 0; c < channels; c++)
            {
                const uint64_t outputIndex =
                    (static_cast<uint64_t>(oy) * layout.outputWidth + ox) * channels + c;
                for (uint32_t ky = 0; ky < kernel; ky++)
                    for (uint32_t kx = 0; kx < kernel; kx++)
                    {
                        const uint32_t tap = ky * kernel + kx;
                        const int iy = static_cast<int>(oy * stride + ky) - padTop;
                        const int ix = static_cast<int>(ox * stride + kx) - padLeft;
                        if (iy >= 0 && iy < static_cast<int>(height) && ix >= 0 &&
                            ix < static_cast<int>(width))
                        {
                            const uint64_t inputIndex =
                                (static_cast<uint64_t>(iy) * width + ix) * channels + c;
                            layout.inputTapPlanes[tap][outputIndex] = input[inputIndex];
                        }
                        layout.weightTapPlanes[tap][outputIndex] =
                            weights[static_cast<uint64_t>(tap) * channels + c];
                    }
            }
    return layout;
}

vector<float> MobileNetV4Workload::depthwiseReference(
    const vector<float>& input, const vector<float>& weights, uint32_t height, uint32_t width,
    uint32_t channels, uint32_t kernel, uint32_t stride)
{
    // Validate dimensions consistently, while keeping the arithmetic independent of tap planes.
    makeDepthwiseTapLayout(input, weights, height, width, channels, kernel, stride);
    const uint32_t outputHeight = sameOutputSize(height, stride);
    const uint32_t outputWidth = sameOutputSize(width, stride);
    const int padTop = samePadBefore(height, outputHeight, kernel, stride);
    const int padLeft = samePadBefore(width, outputWidth, kernel, stride);
    vector<float> output(static_cast<uint64_t>(outputHeight) * outputWidth * channels, 0.0f);
    for (uint32_t oy = 0; oy < outputHeight; oy++)
        for (uint32_t ox = 0; ox < outputWidth; ox++)
            for (uint32_t c = 0; c < channels; c++)
                for (uint32_t ky = 0; ky < kernel; ky++)
                    for (uint32_t kx = 0; kx < kernel; kx++)
                    {
                        const int iy = static_cast<int>(oy * stride + ky) - padTop;
                        const int ix = static_cast<int>(ox * stride + kx) - padLeft;
                        if (iy < 0 || iy >= static_cast<int>(height) || ix < 0 ||
                            ix >= static_cast<int>(width))
                            continue;
                        const uint64_t inputIndex =
                            (static_cast<uint64_t>(iy) * width + ix) * channels + c;
                        const uint64_t weightIndex =
                            (static_cast<uint64_t>(ky) * kernel + kx) * channels + c;
                        const uint64_t outputIndex =
                            (static_cast<uint64_t>(oy) * outputWidth + ox) * channels + c;
                        output[outputIndex] += input[inputIndex] * weights[weightIndex];
                    }
    return output;
}

vector<float> MobileNetV4Workload::pointwiseReference(
    const vector<float>& input, const vector<float>& weights, uint32_t height, uint32_t width,
    uint32_t inputChannels, uint32_t outputChannels)
{
    const uint64_t positions = static_cast<uint64_t>(height) * width;
    if (height == 0 || width == 0 || inputChannels == 0 || outputChannels == 0)
        throw invalid_argument("Pointwise dimensions must be positive");
    if (input.size() != positions * inputChannels)
        throw invalid_argument("Pointwise NHWC input size does not match its dimensions");
    if (weights.size() != static_cast<uint64_t>(outputChannels) * inputChannels)
        throw invalid_argument("Pointwise weights must use output-channel-major order");

    vector<float> output(positions * outputChannels, 0.0f);
    for (uint64_t position = 0; position < positions; position++)
        for (uint32_t outputChannel = 0; outputChannel < outputChannels; outputChannel++)
            for (uint32_t inputChannel = 0; inputChannel < inputChannels; inputChannel++)
                output[position * outputChannels + outputChannel] +=
                    input[position * inputChannels + inputChannel] *
                    weights[static_cast<uint64_t>(outputChannel) * inputChannels + inputChannel];
    return output;
}

WorkloadExecutionPlan MobileNetV4Workload::buildExecutionPlan(
    const vector<MobileNetV4Layer>& layers, const string& block,
    uint64_t interconnectBytesPerCycle, uint32_t bytesPerElement,
    WorkloadPlacement initialPlacement)
{
    if (block.empty()) throw invalid_argument("Workload block name must not be empty");
    if (bytesPerElement == 0) throw invalid_argument("Bytes per element must be positive");
    if (initialPlacement == WorkloadPlacement::HYBRID)
        throw invalid_argument("A tensor cannot reside at the HYBRID pseudo-placement");

    vector<MobileNetV4Layer> selected;
    for (const auto& layer : layers)
        if (layer.block == block) selected.push_back(layer);
    if (selected.empty()) throw invalid_argument("No layers found for workload block " + block);

    WorkloadExecutionPlan plan{};
    plan.block = block;
    WorkloadTensorShape current{selected.front().height, selected.front().width,
                                selected.front().inputChannels};
    WorkloadPlacement currentPlacement = initialPlacement;

    for (const auto& layer : selected)
    {
        if (layer.placement == WorkloadPlacement::HYBRID)
            throw invalid_argument("Each workload stage needs one physical placement");
        if (layer.inputChannels != current.channels)
            throw invalid_argument("Input channel mismatch before layer " + layer.name);

        WorkloadTensorShape output{layer.height, layer.width, layer.outputChannels};
        if (layer.op == WorkloadOp::DEPTHWISE_CONV)
        {
            if (layer.outputChannels != layer.inputChannels)
                throw invalid_argument("Depthwise input/output channels differ at " + layer.name);
            if (sameOutputSize(current.height, layer.stride) != layer.height ||
                sameOutputSize(current.width, layer.stride) != layer.width)
                throw invalid_argument("Depthwise spatial shape mismatch at " + layer.name);
        }
        else if (current.height != layer.height || current.width != layer.width)
        {
            throw invalid_argument("Spatial shape mismatch before layer " + layer.name);
        }

        WorkloadExecutionStage stage{};
        stage.layer = layer;
        stage.input = current;
        stage.output = output;
        stage.hasInputTransfer = currentPlacement != layer.placement;
        if (stage.hasInputTransfer)
        {
            const uint64_t bytes = static_cast<uint64_t>(current.height) * current.width *
                                   current.channels * bytesPerElement;
            const uint64_t cycles = interconnectBytesPerCycle == 0
                                        ? 0
                                        : (bytes + interconnectBytesPerCycle - 1) /
                                              interconnectBytesPerCycle;
            stage.inputTransfer = {currentPlacement, layer.placement, bytes, cycles};
            plan.totalTransferBytes += bytes;
            plan.totalTransferCycles += cycles;
        }
        plan.stages.push_back(stage);
        current = output;
        currentPlacement = layer.placement;
    }
    return plan;
}
