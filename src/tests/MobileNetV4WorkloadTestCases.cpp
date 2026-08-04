#include "gtest/gtest.h"
#include "tests/MobileNetV4Workload.h"
#include "tests/PIMKernel.h"
#include "tests/TestCases.h"

#include <algorithm>

using namespace DRAMSim;

namespace
{
NumpyBurstType packFp16Plane(const vector<float>& values, uint64_t paddedElements)
{
    NumpyBurstType packed;
    packed.shape = {1, static_cast<unsigned long>(paddedElements)};
    packed.loadTobShape(16);
    packed.bData.resize(paddedElements / 16);
    for (size_t i = 0; i < values.size(); i++)
        packed.bData[i / 16].fp16Data_[i % 16] = fp16(values[i]);
    return packed;
}

TEST(LogicDieSchedulerTest, EightUnitsSerializeTwoEightBlockCommands)
{
    LogicDieScheduler scheduler;
    const auto first = scheduler.reserve(100, 8, 8, 2, 64, sizeof(BurstType), 1, 0, true);
    const auto second = scheduler.reserve(100, 8, 8, 2, 64, sizeof(BurstType), 1, 0, true);

    EXPECT_EQ(first.serviceCycles, 4u);
    EXPECT_EQ(first.queueCycles, 0u);
    EXPECT_EQ(first.completionDelay, 4u);
    EXPECT_EQ(second.queueCycles, 4u);
    EXPECT_EQ(second.completionDelay, 8u);
    EXPECT_EQ(scheduler.getBusyUntil(), 108u);
}

TEST(LogicDieSchedulerTest, SixteenUnitsRunTwoEightBlockCommandsInParallel)
{
    LogicDieScheduler scheduler;
    const auto first = scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 1, 0, true);
    const auto second = scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 1, 0, true);

    EXPECT_EQ(first.queueCycles, 0u);
    EXPECT_EQ(second.queueCycles, 0u);
    EXPECT_EQ(first.completionDelay, 4u);
    EXPECT_EQ(second.completionDelay, 4u);
    EXPECT_EQ(scheduler.getBusyUntil(), 104u);
}

TEST(LogicDieSchedulerTest, SameCycleCommandPaysDispatchOverheadOnce)
{
    LogicDieScheduler scheduler;
    const auto first = scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 7, 3, true);
    const auto second = scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 7, 3, true);

    EXPECT_FALSE(first.commandCoalesced);
    EXPECT_EQ(first.dispatchOverheadCycles, 3u);
    EXPECT_EQ(first.serviceCycles, 7u);
    EXPECT_TRUE(second.commandCoalesced);
    EXPECT_EQ(second.dispatchOverheadCycles, 0u);
    EXPECT_EQ(second.serviceCycles, 4u);
    EXPECT_EQ(scheduler.getDispatchCount(), 1u);
    EXPECT_EQ(scheduler.getCoalescedCommandCount(), 1u);
    EXPECT_EQ(scheduler.getDispatchOverheadCycles(), 3u);
}

TEST(LogicDieSchedulerTest, DisabledCoalescingChargesEveryCommand)
{
    LogicDieScheduler scheduler;
    const auto first = scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 7, 3, false);
    const auto second = scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 7, 3, false);

    EXPECT_FALSE(first.commandCoalesced);
    EXPECT_FALSE(second.commandCoalesced);
    EXPECT_EQ(first.serviceCycles, 7u);
    EXPECT_EQ(second.serviceCycles, 7u);
    EXPECT_EQ(scheduler.getDispatchCount(), 2u);
    EXPECT_EQ(scheduler.getCoalescedCommandCount(), 0u);
    EXPECT_EQ(scheduler.getDispatchOverheadCycles(), 6u);
}

TEST(LogicDieWeightBufferTest, ReusesCanonicalChannelAcrossSpatialGroups)
{
    LogicDieWeightBuffer buffer;
    BurstType weight;
    weight.set(fp16(3.5f));
    buffer.beginLayer(2, sizeof(BurstType), 0, 1);

    ASSERT_TRUE(buffer.store(0, 0, 4, 7, 9, weight));
    BurstType result;
    EXPECT_TRUE(buffer.read(2, 0, 4, 7, 9, result));
    EXPECT_FLOAT_EQ(static_cast<float>(result.fp16Data_[0]), 3.5f);
    EXPECT_FALSE(buffer.read(3, 0, 4, 7, 9, result));
}

TEST(LogicDieWeightBufferTest, RejectsFillBeyondConfiguredCapacity)
{
    LogicDieWeightBuffer buffer;
    BurstType weight;
    buffer.beginLayer(1, sizeof(BurstType), 0, 1);

    EXPECT_TRUE(buffer.store(0, 0, 0, 0, 0, weight));
    EXPECT_FALSE(buffer.store(0, 0, 0, 0, 1, weight));
    EXPECT_EQ(buffer.getStoredBytes(), sizeof(BurstType));
}

TEST(LogicDieWeightBufferTest, SerializesConcurrentFillsAcrossWritePorts)
{
    LogicDieWeightBuffer buffer;
    buffer.beginLayer(1, 4 * sizeof(BurstType), 2, 3);

    EXPECT_EQ(buffer.completeFill(10), 13);
    EXPECT_EQ(buffer.completeFill(10), 13);
    EXPECT_EQ(buffer.completeFill(10), 16);
    EXPECT_EQ(buffer.completeFill(10), 16);
    EXPECT_EQ(buffer.getReadyCycle(), 16);
    EXPECT_EQ(buffer.getWriteQueueCycles(), 6);
}


NumpyBurstType packPointwiseInput(const vector<float>& values, uint32_t physicalInputDim = 128)
{
    return packFp16Plane(values, physicalInputDim);
}

NumpyBurstType packPointwiseBatchInput(const vector<float>& values, uint32_t batchSize,
                                       uint32_t logicalInputDim,
                                       uint32_t physicalInputDim = 128)
{
    if (physicalInputDim < logicalInputDim || physicalInputDim % 16 != 0)
        throw invalid_argument("Physical pointwise input must contain the logical FP16 vector");
    if (values.size() != static_cast<uint64_t>(batchSize) * logicalInputDim)
        throw invalid_argument("Pointwise batch input values do not match dimensions");
    NumpyBurstType packed;
    packed.shape = {batchSize, physicalInputDim};
    packed.loadTobShape(16);
    packed.bData.resize(static_cast<uint64_t>(batchSize) * packed.bShape[1]);
    for (uint32_t batch = 0; batch < batchSize; batch++)
        for (uint32_t input = 0; input < logicalInputDim; input++)
        {
            const uint64_t burst = static_cast<uint64_t>(batch) * packed.bShape[1] + input / 16;
            packed.bData[burst].fp16Data_[input % 16] =
                fp16(values[static_cast<uint64_t>(batch) * logicalInputDim + input]);
        }
    return packed;
}

NumpyBurstType packPointwiseWeights(const vector<float>& values, uint32_t logicalInputDim,
                                    uint32_t logicalOutputDim, uint32_t physicalInputDim = 128,
                                    uint32_t physicalOutputDim = 4096)
{
    if (physicalInputDim < logicalInputDim || physicalInputDim % 16 != 0 ||
        physicalOutputDim < logicalOutputDim)
        throw invalid_argument("Physical pointwise weight tile is smaller than its logical shape");
    if (values.size() != static_cast<uint64_t>(logicalInputDim) * logicalOutputDim)
        throw invalid_argument("Pointwise weight values do not match logical dimensions");
    NumpyBurstType packed;
    packed.shape = {physicalOutputDim, physicalInputDim};
    packed.loadTobShape(16);
    packed.bData.resize(static_cast<uint64_t>(physicalOutputDim) * packed.bShape[1]);
    for (uint32_t output = 0; output < logicalOutputDim; output++)
        for (uint32_t input = 0; input < logicalInputDim; input++)
        {
            const uint64_t burst = static_cast<uint64_t>(output) * packed.bShape[1] + input / 16;
            packed.bData[burst].fp16Data_[input % 16] =
                fp16(values[static_cast<uint64_t>(output) * logicalInputDim + input]);
        }
    return packed;
}

vector<float> runPointwiseTensor(PIMKernel& pim, const vector<float>& input, uint32_t positions,
                                 uint32_t inputChannels, uint32_t outputChannels,
                                 NumpyBurstType& packedWeights)
{
    vector<float> output(static_cast<uint64_t>(positions) * outputChannels);
    for (uint32_t position = 0; position < positions; position++)
    {
        vector<float> inputVector(input.begin() + position * inputChannels,
                                  input.begin() + (position + 1) * inputChannels);
        auto packedInput = packPointwiseInput(inputVector);
        auto result = pim.executePointwiseAndRead(&packedWeights, &packedInput, outputChannels);
        for (uint32_t channel = 0; channel < outputChannels; channel++)
            output[static_cast<uint64_t>(position) * outputChannels + channel] =
                static_cast<float>(result[channel]);
    }
    return output;
}

vector<float> runDepthwiseTensor(PIMKernel& pim, const DepthwiseTapLayout& layout,
                                 uint64_t paddedElements)
{
    const int inputBaseRow = 0;
    const int weightBaseRow = 256;
    const int tapRowStride = 16;
    const int productRow = 512;
    const int accumulatorRow = 576;
    const int resultRow = 640;
    vector<NumpyBurstType> inputs;
    vector<NumpyBurstType> weights;
    inputs.reserve(layout.inputTapPlanes.size());
    weights.reserve(layout.weightTapPlanes.size());
    for (size_t tap = 0; tap < layout.inputTapPlanes.size(); tap++)
    {
        inputs.push_back(packFp16Plane(layout.inputTapPlanes[tap], paddedElements));
        weights.push_back(packFp16Plane(layout.weightTapPlanes[tap], paddedElements));
        pim.preloadNoReplacement(&inputs.back(), inputBaseRow + tap * tapRowStride, 0);
        pim.preloadNoReplacement(&weights.back(), weightBaseRow + tap * tapRowStride, 0);
    }
    pim.executeDepthwiseLowered(paddedElements / 16, layout.kernel, inputBaseRow, weightBaseRow,
                                productRow, accumulatorRow, resultRow, tapRowStride);
    vector<BurstType> raw(paddedElements / 16);
    pim.readData(raw.data(), raw.size(), resultRow, 0);
    pim.runPIM();

    const uint64_t logicalElements =
        static_cast<uint64_t>(layout.outputHeight) * layout.outputWidth * layout.channels;
    vector<float> output(logicalElements);
    for (uint64_t i = 0; i < logicalElements; i++)
        output[i] = static_cast<float>(raw[i / 16].fp16Data_[i % 16]);
    return output;
}
}  // namespace

TEST(MobileNetV4WorkloadTest, ConvSmallUib14Lowering)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    ASSERT_EQ(layers.size(), 9);

    auto expand = MobileNetV4Workload::lower(layers[1]);
    EXPECT_TRUE(expand.supported);
    EXPECT_EQ(expand.kernel, "GEMV");
    EXPECT_EQ(expand.invocations, 28 * 28);
    EXPECT_EQ(expand.inputDim, 64);
    EXPECT_EQ(expand.outputDim, 192);
    EXPECT_EQ(expand.paddedInputDim, 128);
    EXPECT_EQ(expand.paddedOutputDim, 4096);
    EXPECT_EQ(expand.macs, 28ULL * 28 * 64 * 192);

    auto depthwise = MobileNetV4Workload::lower(layers[2]);
    EXPECT_TRUE(depthwise.supported);
    EXPECT_EQ(depthwise.kernel, "DEPTHWISE_MUL_ADD");
    EXPECT_EQ(depthwise.macs, 14ULL * 14 * 192 * 5 * 5);
    EXPECT_EQ(depthwise.paddedElements, 131072);

    auto residual = MobileNetV4Workload::lower(layers[7]);
    EXPECT_TRUE(residual.supported);
    EXPECT_EQ(residual.logicalElements, 14ULL * 14 * 96);
    EXPECT_EQ(residual.paddedElements, 131072);
}

TEST(MobileNetV4WorkloadTest, ConvSmallIbExecutionPlan)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    auto plan = MobileNetV4Workload::buildExecutionPlan(layers, "uib14_ib", 64);

    ASSERT_EQ(plan.stages.size(), 5);
    EXPECT_EQ(plan.stages[0].layer.name, "uib14_ib_expand");
    EXPECT_EQ(plan.stages[0].input.channels, 96);
    EXPECT_EQ(plan.stages[0].output.channels, 192);
    EXPECT_EQ(plan.stages[1].layer.name, "uib14_ib_middle_dw");
    EXPECT_EQ(plan.stages[2].layer.name, "uib14_ib_project");
    EXPECT_EQ(plan.stages[2].input.channels, 192);
    EXPECT_EQ(plan.stages[2].output.channels, 96);
    EXPECT_EQ(plan.stages[3].layer.name, "uib14_ib_residual_add");
    EXPECT_EQ(plan.stages[4].layer.name, "uib14_ib_relu");

    EXPECT_TRUE(plan.stages[0].hasInputTransfer);
    EXPECT_TRUE(plan.stages[1].hasInputTransfer);
    EXPECT_TRUE(plan.stages[2].hasInputTransfer);
    EXPECT_TRUE(plan.stages[3].hasInputTransfer);
    EXPECT_FALSE(plan.stages[4].hasInputTransfer);
    EXPECT_EQ(plan.totalTransferBytes, 225792);
    EXPECT_EQ(plan.totalTransferCycles, 3528);
}

TEST(MobileNetV4WorkloadTest, ExecutionPlanRejectsBrokenTensorFlow)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    for (auto& layer : layers)
        if (layer.name == "uib14_ib_project") layer.inputChannels = 191;
    EXPECT_THROW(MobileNetV4Workload::buildExecutionPlan(layers, "uib14_ib", 64),
                 std::invalid_argument);
}

TEST(MobileNetV4WorkloadTest, HierarchyTransferAccounting)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    const uint64_t hierarchyBandwidth = getConfigParam(UINT, "HIERARCHY_PIM_BW");
    auto plan =
        MobileNetV4Workload::buildExecutionPlan(layers, "uib14_ib", hierarchyBandwidth);
    PIMKernel pim(memory, 64, 1);

    for (const auto& stage : plan.stages)
    {
        if (stage.hasInputTransfer)
        {
            EXPECT_EQ(pim.accountHierarchyTransfer(stage.inputTransfer.bytes, hierarchyBandwidth),
                      stage.inputTransfer.cycles);
        }
    }

    EXPECT_EQ(pim.getHierarchyTransferCount(), 4);
    EXPECT_EQ(pim.getHierarchyTransferBytes(), plan.totalTransferBytes);
    EXPECT_EQ(pim.getHierarchyTransferCycles(), plan.totalTransferCycles);
    EXPECT_EQ(pim.getCycle(), plan.totalTransferCycles);
    cout << "MOBILENETV4_HIERARCHY_STATS"
         << " block[" << plan.block << "]"
         << " transfers[" << pim.getHierarchyTransferCount() << "]"
         << " bytes[" << pim.getHierarchyTransferBytes() << "]"
         << " cycles[" << pim.getHierarchyTransferCycles() << "]"
         << " bandwidth_bytes_per_cycle[" << hierarchyBandwidth << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, PointwiseAdapterReturnsLogicalTensor)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    auto input = packPointwiseInput({1, 2, 3});
    auto weights = packPointwiseWeights({1, 0, 0, 0, 1, 0, 1, 1, 1}, 3, 3);
    auto output = pim.executePointwiseAndRead(&weights, &input, 3);

    ASSERT_EQ(output.size(), 3);
    EXPECT_EQ(static_cast<float>(output[0]), 1.0f);
    EXPECT_EQ(static_cast<float>(output[1]), 2.0f);
    EXPECT_EQ(static_cast<float>(output[2]), 6.0f);
}

TEST(MobileNetV4WorkloadTest, PointwiseBatchAdapterReturnsEachPosition)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    auto input = packPointwiseBatchInput({1, 2, 3, 4, 5, 6}, 2, 3);
    auto weights = packPointwiseWeights({1, 0, 0, 0, 1, 0, 1, 1, 1}, 3, 3);
    auto output = pim.executePointwiseBatchAndRead(&weights, &input, 3);

    ASSERT_EQ(output.size(), 6);
    const vector<float> expected = {1, 2, 6, 4, 5, 15};
    for (size_t i = 0; i < expected.size(); i++)
        EXPECT_EQ(static_cast<float>(output[i]), expected[i]);
}

TEST(MobileNetV4WorkloadTest, PointwiseCompactMappingUsesRequestedChannelRange)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    if (!pim.usesLogicDiePIM() || !getConfigParam(BOOL, "LOGIC_COMPACT_OUTPUT"))
        GTEST_SKIP() << "Requires hybrid logic-die PIM with compact output mapping";

    vector<float> inputValues = {1, 2, 3};
    vector<float> weightValues(192 * 3, 0.0f);
    for (unsigned output = 0; output < 192; output++)
        weightValues[output * 3 + output % 3] = 1.0f;
    auto input = packPointwiseBatchInput(inputValues, 1, 3);
    auto weights = packPointwiseWeights(weightValues, 3, 192);

    vector<uint64_t> readsBefore(64), writesBefore(64);
    for (unsigned channel = 0; channel < 64; channel++)
    {
        readsBefore[channel] = memory->channels[channel]->memoryController->totalReads;
        writesBefore[channel] = memory->channels[channel]->memoryController->totalWrites;
    }

    auto output = pim.executePointwiseBatchAndRead(&weights, &input, 192, 5);

    ASSERT_EQ(output.size(), 192);
    for (unsigned index = 0; index < output.size(); index++)
        EXPECT_EQ(static_cast<float>(output[index]), inputValues[index % 3]);
    EXPECT_EQ(pim.getLastPointwiseActiveChannels(), 3u);
    EXPECT_EQ(pim.getLastPointwisePhysicalOutputDim(), 192u);

    for (unsigned channel = 0; channel < 64; channel++)
    {
        const uint64_t reads =
            memory->channels[channel]->memoryController->totalReads - readsBefore[channel];
        const uint64_t writes =
            memory->channels[channel]->memoryController->totalWrites - writesBefore[channel];
        if (channel >= 5 && channel <= 7)
        {
            EXPECT_GT(reads + writes, 0u) << "channel " << channel;
        }
        else
        {
            EXPECT_EQ(reads + writes, 0u) << "unexpected activity on channel " << channel;
        }
    }
}

TEST(MobileNetV4WorkloadTest, PointwiseBatchRunsMobileNetV4Shape)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    const auto layer = find_if(layers.begin(), layers.end(), [](const MobileNetV4Layer& item) {
        return item.name == "uib14_ib_expand";
    });
    ASSERT_NE(layer, layers.end());
    const uint32_t positions = layer->height * layer->width;
    vector<float> input(static_cast<uint64_t>(positions) * layer->inputChannels, 1.0f);
    vector<float> weights(
        static_cast<uint64_t>(layer->outputChannels) * layer->inputChannels, 1.0f);
    auto packedInput =
        packPointwiseBatchInput(input, positions, layer->inputChannels);
    auto packedWeights = packPointwiseWeights(weights, layer->inputChannels,
                                               layer->outputChannels);

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    auto output =
        pim.executePointwiseBatchAndRead(&packedWeights, &packedInput, layer->outputChannels);

    ASSERT_EQ(output.size(), static_cast<uint64_t>(positions) * layer->outputChannels);
    for (const auto& value : output) EXPECT_EQ(static_cast<float>(value), 96.0f);
    cout << "MOBILENETV4_BATCH_POINTWISE_RESULT"
         << " name[" << layer->name << "]"
         << " positions[" << positions << "]"
         << " input_channels[" << layer->inputChannels << "]"
         << " output_channels[" << layer->outputChannels << "]"
         << " outputs_checked[" << output.size() << "]"
         << " active_channels[" << pim.getLastPointwiseActiveChannels() << "]"
         << " physical_output_dim[" << pim.getLastPointwisePhysicalOutputDim() << "]"
         << " spatial_groups[" << pim.getLastPointwiseSpatialGroups() << "]"
         << " batch_waves[" << pim.getLastPointwiseBatchWaves() << "]"
         << " reads[" << pim.getTotalReads() << "]"
         << " writes[" << pim.getTotalWrites() << "]"
         << " global_logic_commands[" << pim.getGlobalLogicCommandCount() << "]"
         << " global_logic_queue_cycles[" << pim.getGlobalLogicQueueCycles() << "]"
         << " global_logic_service_cycles[" << pim.getGlobalLogicServiceCycles() << "]"
         << " global_logic_busy_until[" << pim.getGlobalLogicBusyUntil() << "]"
         << " global_logic_dispatches[" << pim.getGlobalLogicDispatchCount() << "]"
         << " global_logic_coalesced[" << pim.getGlobalLogicCoalescedCommandCount() << "]"
         << " global_logic_dispatch_overhead_cycles["
         << pim.getGlobalLogicDispatchOverheadCycles() << "]"
         << " baseline_logic_weight_bytes[" << pim.getBaselineLogicWeightBytes() << "]"
         << " physical_logic_weight_bytes[" << pim.getPhysicalLogicWeightBytes() << "]"
         << " modeled_logic_weight_bytes[" << pim.getModeledLogicWeightBytes() << "]"
         << " saved_logic_weight_bytes[" << pim.getSavedLogicWeightBytes() << "]"
         << " modeled_writes[" << pim.getModeledTotalWrites() << "]"
         << " logic_weight_buffer_fill_bursts[" << pim.getLogicWeightBufferFillBursts() << "]"
         << " logic_weight_buffer_read_hits[" << pim.getLogicWeightBufferReadHits() << "]"
         << " logic_weight_buffer_read_misses[" << pim.getLogicWeightBufferReadMisses() << "]"
         << " logic_weight_fill_active_channels[" << pim.getLogicWeightFillActiveChannels() << "]"
         << " logic_weight_fill_completed_writes[" << pim.getLogicWeightFillCompletedWrites() << "]"
         << " logic_weight_fill_min_writes_per_channel["
         << pim.getLogicWeightFillMinWritesPerChannel() << "]"
         << " logic_weight_fill_max_writes_per_channel["
         << pim.getLogicWeightFillMaxWritesPerChannel() << "]"
         << " logic_weight_fill_min_completion_cycle["
         << pim.getLogicWeightFillMinCompletionCycle() << "]"
         << " logic_weight_fill_max_completion_cycle["
         << pim.getLogicWeightFillMaxCompletionCycle() << "]"
         << " logic_weight_fill_activates[" << pim.getLogicWeightFillActivates() << "]"
         << " logic_weight_fill_precharges[" << pim.getLogicWeightFillPrecharges() << "]"
         << " logic_weight_fill_barrier_cycles[" << pim.getLogicWeightFillBarrierCycles() << "]"
         << " logic_post_fill_guard_cycles[" << pim.getLogicPostFillGuardCycles() << "]"
         << " logic_weight_buffer_port_wait_cycles["
         << pim.getLogicWeightBufferPortWaitCycles() << "]"
         << " logic_weight_buffer_write_queue_cycles["
         << pim.getLogicWeightBufferWriteQueueCycles() << "]"
         << " total_refreshes[" << pim.getTotalRefreshes() << "]"
         << " bank_side[" << pim.usesBankSidePIM() << "]"
         << " logic_die[" << pim.usesLogicDiePIM() << "]"
         << " cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, MiniatureUibRunsEndToEnd)
{
    const uint32_t height = 3;
    const uint32_t width = 3;
    const uint64_t paddedElements = 64ULL * 1 * 16 * 8 * 16;
    const vector<float> input = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    const vector<float> expandWeights = {1, 2};
    const vector<float> depthwiseWeights(3 * 3 * 2, 1.0f);
    const vector<float> projectWeights = {1, 1};

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    auto packedExpandWeights = packPointwiseWeights(expandWeights, 1, 2);
    auto packedProjectWeights = packPointwiseWeights(projectWeights, 2, 1);
    auto accountTransfer = [&pim](uint64_t bytes) {
        if (pim.usesLogicDiePIM())
            pim.accountHierarchyTransfer(bytes, getConfigParam(UINT, "HIERARCHY_PIM_BW"));
    };

    accountTransfer(input.size() * sizeof(uint16_t));
    auto expanded = runPointwiseTensor(pim, input, height * width, 1, 2, packedExpandWeights);
    accountTransfer(expanded.size() * sizeof(uint16_t));
    auto tapLayout = MobileNetV4Workload::makeDepthwiseTapLayout(
        expanded, depthwiseWeights, height, width, 2, 3, 1);
    auto depthwise = runDepthwiseTensor(pim, tapLayout, paddedElements);
    accountTransfer(depthwise.size() * sizeof(uint16_t));
    auto projected =
        runPointwiseTensor(pim, depthwise, height * width, 2, 1, packedProjectWeights);
    accountTransfer(projected.size() * sizeof(uint16_t));

    auto projectedPadded = packFp16Plane(projected, paddedElements);
    auto residualPadded = packFp16Plane(input, paddedElements);
    pim.preloadNoReplacement(&projectedPadded, 0, 0);
    pim.preloadNoReplacement(&residualPadded, 256, 0);
    pim.executeEltwise(paddedElements / 16, pimBankType::ALL_BANK, KernelType::ADD, 0, 512, 256);
    pim.runPIM();
    pim.executeEltwise(paddedElements / 16, pimBankType::ALL_BANK, KernelType::RELU, 512, 768);
    vector<BurstType> rawOutput(paddedElements / 16);
    pim.readData(rawOutput.data(), rawOutput.size(), 768, 0);
    pim.runPIM();

    auto goldenExpanded = MobileNetV4Workload::pointwiseReference(
        input, expandWeights, height, width, 1, 2);
    auto goldenDepthwise = MobileNetV4Workload::depthwiseReference(
        goldenExpanded, depthwiseWeights, height, width, 2, 3, 1);
    auto goldenProjected = MobileNetV4Workload::pointwiseReference(
        goldenDepthwise, projectWeights, height, width, 2, 1);
    for (size_t i = 0; i < goldenProjected.size(); i++)
    {
        const float expected = max(0.0f, goldenProjected[i] + input[i]);
        EXPECT_EQ(static_cast<float>(rawOutput[i / 16].fp16Data_[i % 16]), expected);
    }
    EXPECT_EQ(pim.getHierarchyTransferCount(), pim.usesLogicDiePIM() ? 4 : 0);
    EXPECT_EQ(pim.getHierarchyTransferBytes(), pim.usesLogicDiePIM() ? 108 : 0);
    cout << "MOBILENETV4_MINI_UIB_RESULT"
         << " elements[" << input.size() << "]"
         << " bank_side[" << pim.usesBankSidePIM() << "]"
         << " logic_die[" << pim.usesLogicDiePIM() << "]"
         << " last_pointwise_active_channels[" << pim.getLastPointwiseActiveChannels() << "]"
         << " last_pointwise_physical_output_dim["
         << pim.getLastPointwisePhysicalOutputDim() << "]"
         << " last_pointwise_spatial_groups[" << pim.getLastPointwiseSpatialGroups() << "]"
         << " last_pointwise_batch_waves[" << pim.getLastPointwiseBatchWaves() << "]"
         << " reads[" << pim.getTotalReads() << "]"
         << " writes[" << pim.getTotalWrites() << "]"
         << " global_logic_commands[" << pim.getGlobalLogicCommandCount() << "]"
         << " global_logic_queue_cycles[" << pim.getGlobalLogicQueueCycles() << "]"
         << " global_logic_service_cycles[" << pim.getGlobalLogicServiceCycles() << "]"
         << " global_logic_busy_until[" << pim.getGlobalLogicBusyUntil() << "]"
         << " global_logic_dispatches[" << pim.getGlobalLogicDispatchCount() << "]"
         << " global_logic_coalesced[" << pim.getGlobalLogicCoalescedCommandCount() << "]"
         << " global_logic_dispatch_overhead_cycles["
         << pim.getGlobalLogicDispatchOverheadCycles() << "]"
         << " baseline_logic_weight_bytes[" << pim.getBaselineLogicWeightBytes() << "]"
         << " physical_logic_weight_bytes[" << pim.getPhysicalLogicWeightBytes() << "]"
         << " modeled_logic_weight_bytes[" << pim.getModeledLogicWeightBytes() << "]"
         << " saved_logic_weight_bytes[" << pim.getSavedLogicWeightBytes() << "]"
         << " modeled_writes[" << pim.getModeledTotalWrites() << "]"
         << " logic_weight_buffer_fill_bursts[" << pim.getLogicWeightBufferFillBursts() << "]"
         << " logic_weight_buffer_read_hits[" << pim.getLogicWeightBufferReadHits() << "]"
         << " logic_weight_buffer_read_misses[" << pim.getLogicWeightBufferReadMisses() << "]"
         << " logic_weight_fill_active_channels[" << pim.getLogicWeightFillActiveChannels() << "]"
         << " logic_weight_fill_completed_writes[" << pim.getLogicWeightFillCompletedWrites() << "]"
         << " logic_weight_fill_min_writes_per_channel["
         << pim.getLogicWeightFillMinWritesPerChannel() << "]"
         << " logic_weight_fill_max_writes_per_channel["
         << pim.getLogicWeightFillMaxWritesPerChannel() << "]"
         << " logic_weight_fill_min_completion_cycle["
         << pim.getLogicWeightFillMinCompletionCycle() << "]"
         << " logic_weight_fill_max_completion_cycle["
         << pim.getLogicWeightFillMaxCompletionCycle() << "]"
         << " logic_weight_fill_activates[" << pim.getLogicWeightFillActivates() << "]"
         << " logic_weight_fill_precharges[" << pim.getLogicWeightFillPrecharges() << "]"
         << " logic_weight_fill_barrier_cycles[" << pim.getLogicWeightFillBarrierCycles() << "]"
         << " logic_post_fill_guard_cycles[" << pim.getLogicPostFillGuardCycles() << "]"
         << " logic_weight_buffer_port_wait_cycles["
         << pim.getLogicWeightBufferPortWaitCycles() << "]"
         << " logic_weight_buffer_write_queue_cycles["
         << pim.getLogicWeightBufferWriteQueueCycles() << "]"
         << " total_refreshes[" << pim.getTotalRefreshes() << "]"
         << " transfer_bytes[" << pim.getHierarchyTransferBytes() << "]"
         << " transfer_cycles[" << pim.getHierarchyTransferCycles() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, ActualShapeUibRunsEndToEnd)
{
    const uint32_t height = 14;
    const uint32_t width = 14;
    const uint32_t inputChannels = 96;
    const uint32_t expandedChannels = 192;
    const uint32_t positions = height * width;
    const uint64_t paddedElements = 64ULL * 1 * 16 * 8 * 16;
    vector<float> input(static_cast<uint64_t>(positions) * inputChannels, 1.0f);
    vector<float> expandWeights(static_cast<uint64_t>(expandedChannels) * inputChannels, 0.0f);
    for (uint32_t output = 0; output < expandedChannels; output++)
        expandWeights[static_cast<uint64_t>(output) * inputChannels + output % inputChannels] =
            1.0f;
    vector<float> depthwiseWeights(3 * 3 * expandedChannels, 1.0f);
    vector<float> projectWeights(static_cast<uint64_t>(inputChannels) * expandedChannels, 0.0f);
    for (uint32_t output = 0; output < inputChannels; output++)
        projectWeights[static_cast<uint64_t>(output) * expandedChannels + output] = 1.0f;

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    auto packedInput = packPointwiseBatchInput(input, positions, inputChannels);
    auto packedExpandWeights =
        packPointwiseWeights(expandWeights, inputChannels, expandedChannels);
    const uint64_t hierarchyBandwidth = getConfigParam(UINT, "HIERARCHY_PIM_BW");
    auto accountTransfer = [&pim, hierarchyBandwidth](uint64_t bytes) {
        if (pim.usesLogicDiePIM())
            pim.accountHierarchyTransfer(bytes, hierarchyBandwidth);
    };

    accountTransfer(input.size() * sizeof(uint16_t));
    auto expandedFp16 =
        pim.executePointwiseBatchAndRead(&packedExpandWeights, &packedInput, expandedChannels);
    const unsigned expandSpatialGroups = pim.getLastPointwiseSpatialGroups();
    const unsigned expandBatchWaves = pim.getLastPointwiseBatchWaves();
    vector<float> expanded(expandedFp16.size());
    transform(expandedFp16.begin(), expandedFp16.end(), expanded.begin(),
              [](fp16 value) { return static_cast<float>(value); });
    accountTransfer(expanded.size() * sizeof(uint16_t));

    auto tapLayout = MobileNetV4Workload::makeDepthwiseTapLayout(
        expanded, depthwiseWeights, height, width, expandedChannels, 3, 1);
    auto depthwise = runDepthwiseTensor(pim, tapLayout, paddedElements);
    accountTransfer(depthwise.size() * sizeof(uint16_t));

    auto packedDepthwise =
        packPointwiseBatchInput(depthwise, positions, expandedChannels, 256);
    auto packedProjectWeights =
        packPointwiseWeights(projectWeights, expandedChannels, inputChannels, 256);
    auto projectedFp16 =
        pim.executePointwiseBatchAndRead(&packedProjectWeights, &packedDepthwise, inputChannels);
    const unsigned projectSpatialGroups = pim.getLastPointwiseSpatialGroups();
    const unsigned projectBatchWaves = pim.getLastPointwiseBatchWaves();
    vector<float> projected(projectedFp16.size());
    transform(projectedFp16.begin(), projectedFp16.end(), projected.begin(),
              [](fp16 value) { return static_cast<float>(value); });
    accountTransfer(projected.size() * sizeof(uint16_t));

    auto projectedPadded = packFp16Plane(projected, paddedElements);
    auto residualPadded = packFp16Plane(input, paddedElements);
    pim.preloadNoReplacement(&projectedPadded, 0, 0);
    pim.preloadNoReplacement(&residualPadded, 256, 0);
    pim.executeEltwise(paddedElements / 16, pimBankType::ALL_BANK, KernelType::ADD, 0, 512, 256);
    pim.runPIM();
    pim.executeEltwise(paddedElements / 16, pimBankType::ALL_BANK, KernelType::RELU, 512, 768);
    vector<BurstType> rawOutput(paddedElements / 16);
    pim.readData(rawOutput.data(), rawOutput.size(), 768, 0);
    pim.runPIM();

    for (uint32_t y = 0; y < height; y++)
        for (uint32_t x = 0; x < width; x++)
        {
            const bool topOrBottom = y == 0 || y == height - 1;
            const bool leftOrRight = x == 0 || x == width - 1;
            const float expected = (topOrBottom && leftOrRight)
                                       ? 5.0f
                                       : ((topOrBottom || leftOrRight) ? 7.0f : 10.0f);
            for (uint32_t channel = 0; channel < inputChannels; channel++)
            {
                const uint64_t index =
                    (static_cast<uint64_t>(y) * width + x) * inputChannels + channel;
                EXPECT_EQ(static_cast<float>(rawOutput[index / 16].fp16Data_[index % 16]),
                          expected);
            }
        }
    EXPECT_EQ(pim.getHierarchyTransferCount(), pim.usesLogicDiePIM() ? 4 : 0);
    EXPECT_EQ(pim.getHierarchyTransferBytes(), pim.usesLogicDiePIM() ? 225792 : 0);
    const uint64_t expectedTransferCycles =
        (!pim.usesLogicDiePIM() || hierarchyBandwidth == 0)
            ? 0
            : 2 * ((37632 + hierarchyBandwidth - 1) / hierarchyBandwidth) +
                  2 * ((75264 + hierarchyBandwidth - 1) / hierarchyBandwidth);
    EXPECT_EQ(pim.getHierarchyTransferCycles(), expectedTransferCycles);
    if (pim.usesLogicDiePIM() && getConfigParam(BOOL, "LOGIC_SPATIAL_GROUPING"))
    {
        const bool shared = getConfigParam(BOOL, "LOGIC_SHARED_WEIGHT_BUFFER");
        const uint64_t capacity = getConfigParam(UINT64, "LOGIC_WEIGHT_BUFFER_BYTES");
        const uint64_t expectedPhysicalWeightBytes =
            (shared && capacity >= 49152 ? 49152 : 1032192) +
            (shared && capacity >= 65536 ? 65536 : 2097152);
        EXPECT_EQ(pim.getBaselineLogicWeightBytes(), 3129344);
        EXPECT_EQ(pim.getPhysicalLogicWeightBytes(), expectedPhysicalWeightBytes);
        EXPECT_EQ(pim.getLogicWeightBufferReadMisses(), 0);
        if (shared && capacity >= 49152)
        {
            EXPECT_GT(pim.getLogicWeightBufferReadHits(), 0);
            EXPECT_EQ(pim.getLogicWeightFillCompletedWrites(),
                      pim.getLogicWeightBufferFillBursts());
        }
    }
    cout << "MOBILENETV4_ACTUAL_UIB_RESULT"
         << " shape[14x14x96_to_192_to_96]"
         << " outputs_checked[" << input.size() << "]"
         << " bank_side[" << pim.usesBankSidePIM() << "]"
         << " logic_die[" << pim.usesLogicDiePIM() << "]"
         << " last_pointwise_active_channels[" << pim.getLastPointwiseActiveChannels() << "]"
         << " last_pointwise_physical_output_dim["
         << pim.getLastPointwisePhysicalOutputDim() << "]"
         << " expand_spatial_groups[" << expandSpatialGroups << "]"
         << " expand_batch_waves[" << expandBatchWaves << "]"
         << " project_spatial_groups[" << projectSpatialGroups << "]"
         << " project_batch_waves[" << projectBatchWaves << "]"
         << " reads[" << pim.getTotalReads() << "]"
         << " writes[" << pim.getTotalWrites() << "]"
         << " global_logic_commands[" << pim.getGlobalLogicCommandCount() << "]"
         << " global_logic_queue_cycles[" << pim.getGlobalLogicQueueCycles() << "]"
         << " global_logic_service_cycles[" << pim.getGlobalLogicServiceCycles() << "]"
         << " global_logic_busy_until[" << pim.getGlobalLogicBusyUntil() << "]"
         << " global_logic_dispatches[" << pim.getGlobalLogicDispatchCount() << "]"
         << " global_logic_coalesced[" << pim.getGlobalLogicCoalescedCommandCount() << "]"
         << " global_logic_dispatch_overhead_cycles["
         << pim.getGlobalLogicDispatchOverheadCycles() << "]"
         << " baseline_logic_weight_bytes[" << pim.getBaselineLogicWeightBytes() << "]"
         << " physical_logic_weight_bytes[" << pim.getPhysicalLogicWeightBytes() << "]"
         << " modeled_logic_weight_bytes[" << pim.getModeledLogicWeightBytes() << "]"
         << " saved_logic_weight_bytes[" << pim.getSavedLogicWeightBytes() << "]"
         << " modeled_writes[" << pim.getModeledTotalWrites() << "]"
         << " logic_weight_buffer_fill_bursts[" << pim.getLogicWeightBufferFillBursts() << "]"
         << " logic_weight_buffer_read_hits[" << pim.getLogicWeightBufferReadHits() << "]"
         << " logic_weight_buffer_read_misses[" << pim.getLogicWeightBufferReadMisses() << "]"
         << " logic_weight_fill_active_channels[" << pim.getLogicWeightFillActiveChannels() << "]"
         << " logic_weight_fill_completed_writes[" << pim.getLogicWeightFillCompletedWrites() << "]"
         << " logic_weight_fill_min_writes_per_channel["
         << pim.getLogicWeightFillMinWritesPerChannel() << "]"
         << " logic_weight_fill_max_writes_per_channel["
         << pim.getLogicWeightFillMaxWritesPerChannel() << "]"
         << " logic_weight_fill_min_completion_cycle["
         << pim.getLogicWeightFillMinCompletionCycle() << "]"
         << " logic_weight_fill_max_completion_cycle["
         << pim.getLogicWeightFillMaxCompletionCycle() << "]"
         << " logic_weight_fill_activates[" << pim.getLogicWeightFillActivates() << "]"
         << " logic_weight_fill_precharges[" << pim.getLogicWeightFillPrecharges() << "]"
         << " logic_weight_fill_barrier_cycles[" << pim.getLogicWeightFillBarrierCycles() << "]"
         << " logic_post_fill_guard_cycles[" << pim.getLogicPostFillGuardCycles() << "]"
         << " logic_weight_buffer_port_wait_cycles["
         << pim.getLogicWeightBufferPortWaitCycles() << "]"
         << " logic_weight_buffer_write_queue_cycles["
         << pim.getLogicWeightBufferWriteQueueCycles() << "]"
         << " total_refreshes[" << pim.getTotalRefreshes() << "]"
         << " transfer_bytes[" << pim.getHierarchyTransferBytes() << "]"
         << " transfer_cycles[" << pim.getHierarchyTransferCycles() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, RejectsInvalidDimensions)
{
    MobileNetV4Layer invalid{"bad", "uib", WorkloadOp::RELU, 0, 14, 96, 96, 1, 1,
                             WorkloadPlacement::BANK_SIDE, "test"};
    EXPECT_THROW(MobileNetV4Workload::lower(invalid), std::invalid_argument);
}

TEST(MobileNetV4WorkloadTest, DepthwiseSamePaddingTapLayout)
{
    const vector<float> input = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    const vector<float> weights(9, 1.0f);
    auto layout = MobileNetV4Workload::makeDepthwiseTapLayout(input, weights, 3, 3, 1, 3, 1);
    auto reference = MobileNetV4Workload::depthwiseReference(input, weights, 3, 3, 1, 3, 1);

    ASSERT_EQ(layout.outputHeight, 3);
    ASSERT_EQ(layout.outputWidth, 3);
    ASSERT_EQ(layout.inputTapPlanes.size(), 9);
    EXPECT_EQ(layout.inputTapPlanes[0][0], 0.0f);
    EXPECT_EQ(layout.inputTapPlanes[4][0], 1.0f);
    EXPECT_EQ(layout.inputTapPlanes[8][0], 5.0f);
    const vector<float> expected = {12, 21, 16, 27, 45, 33, 24, 39, 28};
    EXPECT_EQ(reference, expected);

    vector<float> accumulated(reference.size(), 0.0f);
    for (size_t tap = 0; tap < layout.inputTapPlanes.size(); tap++)
        for (size_t i = 0; i < accumulated.size(); i++)
            accumulated[i] += layout.inputTapPlanes[tap][i] * layout.weightTapPlanes[tap][i];
    EXPECT_EQ(accumulated, reference);
}

TEST(MobileNetV4WorkloadTest, DepthwiseSamePaddingStrideTwo)
{
    vector<float> input(16);
    for (size_t i = 0; i < input.size(); i++) input[i] = static_cast<float>(i + 1);
    const vector<float> weights(9, 1.0f);
    auto layout = MobileNetV4Workload::makeDepthwiseTapLayout(input, weights, 4, 4, 1, 3, 2);
    auto reference = MobileNetV4Workload::depthwiseReference(input, weights, 4, 4, 1, 3, 2);

    EXPECT_EQ(layout.outputHeight, 2);
    EXPECT_EQ(layout.outputWidth, 2);
    EXPECT_EQ(reference, (vector<float>{54, 45, 72, 54}));
}

TEST(MobileNetV4WorkloadTest, DepthwiseTapLayoutRunsOnBankSidePim)
{
    const vector<float> input = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    const vector<float> weights(9, 1.0f);
    auto layout = MobileNetV4Workload::makeDepthwiseTapLayout(input, weights, 3, 3, 1, 3, 1);
    auto reference = MobileNetV4Workload::depthwiseReference(input, weights, 3, 3, 1, 3, 1);
    const uint64_t paddedElements = 64ULL * 1 * 16 * 8 * 16;

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    const int inputBaseRow = 0;
    const int weightBaseRow = 256;
    const int tapRowStride = 16;
    const int productRow = 512;
    const int accumulatorRow = 576;
    const int resultRow = 640;
    vector<NumpyBurstType> inputPlanes;
    vector<NumpyBurstType> weightPlanes;
    inputPlanes.reserve(layout.inputTapPlanes.size());
    weightPlanes.reserve(layout.weightTapPlanes.size());
    for (size_t tap = 0; tap < layout.inputTapPlanes.size(); tap++)
    {
        inputPlanes.push_back(packFp16Plane(layout.inputTapPlanes[tap], paddedElements));
        weightPlanes.push_back(packFp16Plane(layout.weightTapPlanes[tap], paddedElements));
        pim.preloadNoReplacement(&inputPlanes.back(), inputBaseRow + tap * tapRowStride, 0);
        pim.preloadNoReplacement(&weightPlanes.back(), weightBaseRow + tap * tapRowStride, 0);
    }

    pim.executeDepthwiseLowered(paddedElements / 16, 3, inputBaseRow, weightBaseRow, productRow,
                                accumulatorRow, resultRow, tapRowStride);
    vector<BurstType> output(paddedElements / 16);
    pim.readData(output.data(), output.size(), resultRow, 0);
    pim.runPIM();

    for (size_t i = 0; i < reference.size(); i++)
        EXPECT_FLOAT_EQ(static_cast<float>(output[i / 16].fp16Data_[i % 16]), reference[i]);
    for (size_t i = reference.size(); i < 16; i++)
        EXPECT_EQ(static_cast<float>(output[0].fp16Data_[i]), 0.0f);
}

TEST(MobileNetV4WorkloadTest, PointwiseGemvSimulatorSmoke)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    auto workload = MobileNetV4Workload::lower(layers[1]);
    ASSERT_TRUE(workload.supported);

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel kernel(memory, 64, 1);
    DataDim data(KernelType::GEMV, 1, workload.paddedOutputDim, workload.paddedInputDim, false);
    data.weight_npbst_.bData.resize(data.weight_npbst_.bShape[0] *
                                    data.weight_npbst_.bShape[1]);

    kernel.preloadGemv(&data.weight_npbst_);
    kernel.executeGemv(&data.weight_npbst_, &data.input_npbst_, false);
    kernel.runPIM();

    EXPECT_GT(kernel.getCycle(), 0);
    cout << "MOBILENETV4_LAYER_RESULT"
         << " name[" << workload.name << "]"
         << " kernel[" << workload.kernel << "]"
         << " input_dim[" << workload.inputDim << "]"
         << " output_dim[" << workload.outputDim << "]"
         << " padded_input_dim[" << workload.paddedInputDim << "]"
         << " padded_output_dim[" << workload.paddedOutputDim << "]"
         << " spatial_invocations[" << workload.invocations << "]"
         << " single_invocation_cycle[" << kernel.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, ReluBankSideSimulatorSmoke)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    auto workload = MobileNetV4Workload::lower(layers[8]);
    ASSERT_TRUE(workload.supported);
    ASSERT_EQ(workload.kernel, "RELU");

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel kernel(memory, 64, 1);
    NumpyBurstType input;
    input.shape = {1, static_cast<unsigned long>(workload.paddedElements)};
    input.loadTobShape(16);
    input.bData.resize(workload.paddedElements / 16);

    kernel.preloadNoReplacement(&input, 0, 0);
    kernel.executeEltwise(workload.paddedElements / 16, pimBankType::ALL_BANK,
                          KernelType::RELU, 0, 256);
    kernel.runPIM();

    EXPECT_GT(kernel.getCycle(), 0);
    cout << "MOBILENETV4_LAYER_RESULT"
         << " name[" << workload.name << "]"
         << " kernel[" << workload.kernel << "]"
         << " logical_elements[" << workload.logicalElements << "]"
         << " padded_elements[" << workload.paddedElements << "]"
         << " cycle[" << kernel.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, DepthwiseBankSideSimulatorSmoke)
{
    auto layers = MobileNetV4Workload::loadCsv("data/mobilenetv4/conv_small_uib14.csv");
    auto workload = MobileNetV4Workload::lower(layers[5]);
    ASSERT_TRUE(workload.supported);

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel kernel(memory, 64, 1);
    NumpyBurstType ones;
    ones.shape = {1, static_cast<unsigned long>(workload.paddedElements)};
    ones.loadTobShape(16);
    ones.bData.resize(workload.paddedElements / 16);
    for (auto& burst : ones.bData) burst.set(fp16(1.0f));

    const int inputBaseRow = 0;
    const int weightBaseRow = 256;
    const int tapRowStride = 16;
    const int productRow = 512;
    const int accumulatorRow = 576;
    const int resultRow = 640;
    for (unsigned tap = 0; tap < layers[5].kernel * layers[5].kernel; tap++)
    {
        kernel.preloadNoReplacement(&ones, inputBaseRow + tap * tapRowStride, 0);
        kernel.preloadNoReplacement(&ones, weightBaseRow + tap * tapRowStride, 0);
    }
    kernel.executeDepthwiseLowered(workload.paddedElements / 16, layers[5].kernel, inputBaseRow,
                                   weightBaseRow, productRow, accumulatorRow, resultRow,
                                   tapRowStride);
    vector<BurstType> output(workload.paddedElements / 16);
    kernel.readData(output.data(), output.size(), resultRow, 0);
    kernel.runPIM();

    EXPECT_GT(kernel.getCycle(), 0);
    for (const auto& burst : output)
        for (int lane = 0; lane < 16; lane++)
            EXPECT_EQ(static_cast<float>(burst.fp16Data_[lane]), 9.0f);
    cout << "MOBILENETV4_LAYER_RESULT"
         << " name[" << workload.name << "]"
         << " kernel[" << workload.kernel << "]"
         << " logical_elements[" << workload.logicalElements << "]"
         << " padded_elements[" << workload.paddedElements << "]"
         << " taps[" << layers[5].kernel * layers[5].kernel << "]"
         << " cycle[" << kernel.getCycle() << "]" << endl;
}
