#include "gtest/gtest.h"
#include "ActivationRowBuffer.h"
#include "HierarchyPIMArbiter.h"
#include "HierarchyTilePipeline.h"
#include "tests/MobileNetV4Workload.h"
#include "tests/PIMKernel.h"
#include "tests/TestCases.h"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <sstream>

using namespace DRAMSim;

namespace
{
uint16_t fp16Bits(fp16 value)
{
    BurstType burst;
    burst.fp16Data_[0] = value;
    return burst.u16Data_[0];
}

template <typename Iterator, typename Converter>
string fp16Hash(Iterator begin, Iterator end, Converter converter)
{
    uint64_t hash = 1469598103934665603ULL;
    for (auto it = begin; it != end; ++it)
    {
        const uint16_t bits = fp16Bits(converter(*it));
        hash ^= bits & 0xff;
        hash *= 1099511628211ULL;
        hash ^= bits >> 8;
        hash *= 1099511628211ULL;
    }
    ostringstream formatted;
    formatted << hex << setw(16) << setfill('0') << hash;
    return formatted.str();
}

template <typename Container>
string fp16Hash(const Container& values)
{
    return fp16Hash(values.begin(), values.end(), [](const auto& value) { return fp16(value); });
}

TEST(HierarchyPIMArbiterTest, PriorityPoliciesExposeOppositeSideWait)
{
    HierarchyPIMArbiter bankPriority(HierarchyArbitrationPolicy::BANK_PRIORITY);
    HierarchyPIMArbiter logicPriority(HierarchyArbitrationPolicy::LOGIC_PRIORITY);
    for (uint64_t id = 0; id < 4; id++)
    {
        const HierarchyPIMRequest bank{HierarchyRequestSource::BANK_SIDE, 0, 1, id};
        const HierarchyPIMRequest logic{HierarchyRequestSource::LOGIC_DIE, 0, 1, id};
        bankPriority.enqueue(bank);
        bankPriority.enqueue(logic);
        logicPriority.enqueue(bank);
        logicPriority.enqueue(logic);
    }
    for (uint64_t cycle = 0; cycle < 8; cycle++)
    {
        EXPECT_TRUE(bankPriority.issue(cycle, true, true));
        EXPECT_TRUE(logicPriority.issue(cycle, true, true));
    }
    EXPECT_EQ(bankPriority.getStats().logicMaxWaitCycles, 7u);
    EXPECT_EQ(logicPriority.getStats().bankMaxWaitCycles, 7u);
}

TEST(HierarchyPIMArbiterTest, RoundRobinAlternatesReadySources)
{
    HierarchyPIMArbiter arbiter(HierarchyArbitrationPolicy::ROUND_ROBIN);
    for (uint64_t id = 0; id < 2; id++)
    {
        arbiter.enqueue({HierarchyRequestSource::BANK_SIDE, 0, 1, id});
        arbiter.enqueue({HierarchyRequestSource::LOGIC_DIE, 0, 1, id});
    }
    const HierarchyRequestSource expected[] = {
        HierarchyRequestSource::BANK_SIDE, HierarchyRequestSource::LOGIC_DIE,
        HierarchyRequestSource::BANK_SIDE, HierarchyRequestSource::LOGIC_DIE};
    for (uint64_t cycle = 0; cycle < 4; cycle++)
    {
        HierarchyPIMRequest issued{};
        ASSERT_TRUE(arbiter.issue(cycle, true, true, &issued));
        EXPECT_EQ(issued.source, expected[cycle]);
    }
}

TEST(HierarchyPIMArbiterTest, ReadyBypassUsesAlternateWithoutLosingBlockedRequest)
{
    HierarchyPIMArbiter strict(HierarchyArbitrationPolicy::ROUND_ROBIN);
    HierarchyPIMArbiter bypass(HierarchyArbitrationPolicy::READY_BYPASS);
    for (auto* arbiter : {&strict, &bypass})
    {
        arbiter->enqueue({HierarchyRequestSource::BANK_SIDE, 0, 1, 0});
        arbiter->enqueue({HierarchyRequestSource::BANK_SIDE, 0, 1, 1});
        arbiter->enqueue({HierarchyRequestSource::LOGIC_DIE, 0, 1, 0});
        ASSERT_TRUE(arbiter->issue(0, true, false));
    }
    EXPECT_FALSE(strict.issue(1, true, false));
    EXPECT_TRUE(bypass.issue(1, true, false));
    EXPECT_EQ(bypass.getStats().readyBypasses, 1u);
    EXPECT_TRUE(bypass.issue(2, true, true));
    EXPECT_EQ(bypass.getStats().logicIssued, 1u);
}

TEST(HierarchyPIMArbiterTest, SimultaneousRequestPolicyMicrobenchmark)
{
    struct Result
    {
        const char* name;
        uint64_t completionCycle;
        HierarchyPIMArbiterStats stats;
    };
    auto run = [](const char* name, HierarchyArbitrationPolicy policy) {
        HierarchyPIMArbiter arbiter(policy);
        for (uint64_t id = 0; id < 64; id++)
        {
            arbiter.enqueue({HierarchyRequestSource::BANK_SIDE, 0, 1, id});
            arbiter.enqueue({HierarchyRequestSource::LOGIC_DIE, 0, 1, id});
        }
        uint64_t cycle = 0;
        while (!arbiter.empty())
        {
            arbiter.issue(cycle, true, cycle >= 16);
            cycle++;
        }
        return Result{name, cycle - 1, arbiter.getStats()};
    };

    const Result results[] = {
        run("bank_priority", HierarchyArbitrationPolicy::BANK_PRIORITY),
        run("logic_priority", HierarchyArbitrationPolicy::LOGIC_PRIORITY),
        run("round_robin", HierarchyArbitrationPolicy::ROUND_ROBIN),
        run("ready_bypass", HierarchyArbitrationPolicy::READY_BYPASS)};
    for (const auto& result : results)
    {
        EXPECT_EQ(result.stats.bankIssued, 64u);
        EXPECT_EQ(result.stats.logicIssued, 64u);
        cout << "HIERARCHY_ARBITRATION_RESULT"
             << " policy[" << result.name << "]"
             << " completion_cycle[" << result.completionCycle << "]"
             << " bank_wait_cycles[" << result.stats.bankWaitCycles << "]"
             << " logic_wait_cycles[" << result.stats.logicWaitCycles << "]"
             << " bank_max_wait[" << result.stats.bankMaxWaitCycles << "]"
             << " logic_max_wait[" << result.stats.logicMaxWaitCycles << "]"
             << " ready_bypasses[" << result.stats.readyBypasses << "]"
             << " arbitration_stall_cycles[" << result.stats.arbitrationStallCycles << "]"
             << endl;
    }
    EXPECT_EQ(results[2].stats.arbitrationStallCycles, 15u);
    EXPECT_EQ(results[2].completionCycle, 142u);
    EXPECT_EQ(results[3].stats.readyBypasses, 15u);
    EXPECT_EQ(results[3].stats.arbitrationStallCycles, 0u);
    EXPECT_EQ(results[3].completionCycle, 127u);
}

TEST(HierarchyTilePipelineTest, UsesMeasuredUibStagesWithDepthwiseHalo)
{
    const auto result = HierarchyTilePipeline::schedule(
        14, 14, 88048, 20360, 103288, 1659, 873);
    EXPECT_EQ(result.sequentialCycles, 214228u);
    EXPECT_LT(result.firstDepthwiseStart, result.lastExpandEnd);
    EXPECT_LT(result.pipelinedCycles, result.sequentialCycles);
    EXPECT_EQ(result.logicResourceCycles, 191336u);
    EXPECT_EQ(result.bankResourceCycles, 22892u);
    cout << "HIERARCHY_TILE_PIPELINE_RESULT"
         << " height[14] width[14]"
         << " sequential_cycles[" << result.sequentialCycles << "]"
         << " pipelined_cycles[" << result.pipelinedCycles << "]"
         << " overlap_gain_cycles[" << result.overlapGainCycles << "]"
         << " first_depthwise_start[" << result.firstDepthwiseStart << "]"
         << " last_expand_end[" << result.lastExpandEnd << "]"
         << " first_project_start[" << result.firstProjectStart << "]"
         << " logic_resource_cycles[" << result.logicResourceCycles << "]"
         << " bank_resource_cycles[" << result.bankResourceCycles << "]"
         << endl;
}

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

TEST(LogicDieSchedulerTest, ReleaseEpochCoalescesMatchingStreamOrdinalsAcrossCycles)
{
    LogicDieScheduler scheduler;
    scheduler.beginReleaseEpoch(2);
    const auto first = scheduler.reserve(
        100, 8, 16, 2, 64, sizeof(BurstType), 7, 3, true, {1, 0, 0, true});
    const auto second = scheduler.reserve(
        107, 8, 16, 2, 64, sizeof(BurstType), 7, 3, true, {1, 0, 1, true});
    const auto nextOrdinal = scheduler.reserve(
        108, 8, 16, 2, 64, sizeof(BurstType), 7, 3, true, {1, 1, 0, true});

    EXPECT_FALSE(first.commandCoalesced);
    EXPECT_TRUE(second.commandCoalesced);
    EXPECT_FALSE(nextOrdinal.commandCoalesced);
    EXPECT_EQ(scheduler.getReleaseEpochCount(), 1u);
    EXPECT_EQ(scheduler.getMaxReleaseStreams(), 2u);
    EXPECT_EQ(scheduler.getCompletedReadyMasks(), 1u);
    EXPECT_EQ(scheduler.getIncompleteReadyMasks(), 0u);
}

TEST(LogicDieSchedulerTest, ReleaseEpochBuildsDynamicMasksForUnevenStreams)
{
    LogicDieScheduler scheduler;
    scheduler.beginReleaseEpoch(3, {{0, 2}, {1, 1}, {2, 1}}, 1);
    for (uint64_t stream = 0; stream < 3; stream++)
        scheduler.reserve(100 + stream, 8, 16, 2, 64, sizeof(BurstType), 9, 3, true,
                          {1, 0, stream, true});
    scheduler.reserve(110, 8, 16, 2, 64, sizeof(BurstType), 9, 3, true,
                      {1, 1, 0, true});

    EXPECT_EQ(scheduler.getBroadcastMaskCount(), 2u);
    EXPECT_EQ(scheduler.getBroadcastFanout(), 4u);
    EXPECT_EQ(scheduler.getMinBroadcastFanout(), 1u);
    EXPECT_EQ(scheduler.getMaxBroadcastFanout(), 3u);
    EXPECT_EQ(scheduler.getCompletedReadyMasks(), 1u);
    EXPECT_EQ(scheduler.getIncompleteReadyMasks(), 0u);
    const auto stats = scheduler.getEpochStats(1);
    EXPECT_EQ(stats.maskCount, 2u);
    EXPECT_EQ(stats.totalResidencyCycles, 2u);
    EXPECT_EQ(stats.maxResidencyCycles, 2u);
    EXPECT_EQ(stats.peakOpenMasks, 1u);
    EXPECT_EQ(stats.onlinePeakOpenMasks, 1u);
    EXPECT_EQ(stats.onlineQueueFullEvents, 0u);
    EXPECT_EQ(stats.incompleteExpectedMasks, 0u);
}

TEST(LogicDieSchedulerTest, FiniteBroadcastQueueAddsBackpressure)
{
    LogicDieScheduler scheduler;
    scheduler.beginReleaseEpoch(2, {{0, 2}, {1, 2}}, 1);
    scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 5, 0, true,
                      {1, 0, 0, true});
    scheduler.reserve(101, 8, 16, 2, 64, sizeof(BurstType), 5, 0, true,
                      {1, 1, 0, true});
    scheduler.reserve(105, 8, 16, 2, 64, sizeof(BurstType), 5, 0, true,
                      {1, 1, 1, true});
    scheduler.reserve(110, 8, 16, 2, 64, sizeof(BurstType), 5, 0, true,
                      {1, 0, 1, true});

    const auto constrained = scheduler.applyBroadcastQueueDepth(1);
    EXPECT_EQ(constrained.stallCycles, 10u);
    EXPECT_EQ(constrained.fullEvents, 1u);
    EXPECT_EQ(scheduler.getBroadcastQueueStallCycles(), 10u);
    const auto onlineStats = scheduler.getEpochStats(1);
    EXPECT_EQ(onlineStats.onlinePeakOpenMasks, 2u);
    EXPECT_EQ(onlineStats.onlineQueueFullEvents, 1u);
    EXPECT_EQ(onlineStats.incompleteExpectedMasks, 0u);
    const auto repeated = scheduler.applyBroadcastQueueDepth(1);
    EXPECT_EQ(repeated.stallCycles, 0u);
}

TEST(LogicDieSchedulerTest, ExpectedMaskRejectsWrongStreamWithSameFanout)
{
    LogicDieScheduler scheduler;
    scheduler.beginReleaseEpoch(2, {{0, 1}, {1, 1}}, 4);
    scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 5, 0, true,
                      {1, 0, 0, true});
    scheduler.reserve(101, 8, 16, 2, 64, sizeof(BurstType), 5, 0, true,
                      {1, 0, 2, true});

    const auto stats = scheduler.getEpochStats(1);
    EXPECT_EQ(stats.totalFanout, 2u);
    EXPECT_EQ(stats.incompleteExpectedMasks, 1u);
}

TEST(LogicDieSchedulerTest, FinitePcuQueueReleasesEntriesAtServiceStart)
{
    LogicDieScheduler scheduler;
    for (uint64_t request = 0; request < 4; request++)
        scheduler.reserve(0, 8, 16, 2, 64, sizeof(BurstType), request, 0, false);

    EXPECT_FALSE(scheduler.canAccept(99, {}, 0, 2));
    EXPECT_TRUE(scheduler.canAccept(99, {}, 4, 2));
}

TEST(LogicDieSchedulerTest, FinitePcuQueueLeavesDistributedAdmissionHeadroom)
{
    LogicDieScheduler scheduler;
    for (uint64_t request = 0; request < 4; request++)
        scheduler.reserve(0, 8, 16, 2, 64, sizeof(BurstType), request, 0, false);
    EXPECT_FALSE(scheduler.canAccept(99, {}, 0, 64, 64));
    EXPECT_TRUE(scheduler.canAccept(99, {}, 4, 64, 64));
}

TEST(LogicDieSchedulerTest, FullQueueAcceptsExistingMaskAndRejectsNewMask)
{
    LogicDieScheduler scheduler;
    scheduler.beginReleaseEpoch(2, {{0, 2}, {1, 2}}, 1);
    scheduler.reserve(100, 8, 16, 2, 64, sizeof(BurstType), 5, 0, true,
                      {1, 0, 0, true});

    EXPECT_TRUE(scheduler.canAccept(5, {1, 0, 1, true}));
    EXPECT_FALSE(scheduler.canAccept(5, {1, 1, 0, true}));
    scheduler.recordOnlineIssueStall(0, 101);
    scheduler.recordOnlineIssueStall(1, 200);
    EXPECT_EQ(scheduler.getOnlineIssueStallCycles(), 2u);
    EXPECT_EQ(scheduler.getOnlineIssueBusyOverlapCycles(), 1u);
    EXPECT_EQ(scheduler.getBlockedWallCycles(), 2u);
    EXPECT_EQ(scheduler.getBlockedStreamCount(), 2u);
    EXPECT_EQ(scheduler.getMinBlockedCyclesPerStream(), 1u);
    EXPECT_EQ(scheduler.getMaxBlockedCyclesPerStream(), 1u);
    EXPECT_EQ(scheduler.getBlockedStreamMaskLow(), 3u);
    EXPECT_EQ(scheduler.getBlockedStreamMaskHigh(), 0u);
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

TEST(LogicDieOutputBufferTest, CompletesAndRetiresTileInOrder)
{
    LogicDieOutputBuffer buffer(2);
    const LogicDieOutputBuffer::TileId first{7, 0, 0};
    const LogicDieOutputBuffer::TileId second{7, 1, 0};
    BurstType value;
    value.set(fp16(2.5f));
    buffer.beginLayer(7);

    ASSERT_TRUE(buffer.reserve(first, 2));
    ASSERT_TRUE(buffer.reserve(second, 1));
    EXPECT_TRUE(buffer.write(first, 1, value));
    EXPECT_FALSE(buffer.isReady(first));
    EXPECT_TRUE(buffer.write(first, 0, value));
    EXPECT_TRUE(buffer.write(second, 0, value));
    EXPECT_TRUE(buffer.isReady(first));
    EXPECT_TRUE(buffer.isReady(second));
    EXPECT_FALSE(buffer.retire(second));
    EXPECT_TRUE(buffer.retire(first));
    EXPECT_TRUE(buffer.retire(second));
    EXPECT_EQ(buffer.getRetirements(), 2u);
}

TEST(LogicDieOutputBufferTest, AppliesBackpressureAtTwoEntries)
{
    LogicDieOutputBuffer buffer(2);
    buffer.beginLayer(3);

    EXPECT_TRUE(buffer.reserve({3, 0, 0}, 1));
    EXPECT_TRUE(buffer.reserve({3, 1, 0}, 1));
    EXPECT_TRUE(buffer.full());
    EXPECT_FALSE(buffer.reserve({3, 2, 0}, 1));
    EXPECT_EQ(buffer.getFullStalls(), 1u);
    EXPECT_EQ(buffer.getPeakEntries(), 2u);
}

TEST(LogicDieOutputBufferTest, RejectsIncompleteReadAndWrongLayer)
{
    LogicDieOutputBuffer buffer(2);
    BurstType value;
    BurstType result;
    value.set(fp16(4.0f));
    buffer.beginLayer(9);

    EXPECT_FALSE(buffer.reserve({8, 0, 0}, 1));
    ASSERT_TRUE(buffer.reserve({9, 0, 0}, 1));
    EXPECT_FALSE(buffer.read({9, 0, 0}, 0, result));
    ASSERT_TRUE(buffer.write({9, 0, 0}, 0, value));
    ASSERT_TRUE(buffer.read({9, 0, 0}, 0, result));
    EXPECT_FLOAT_EQ(static_cast<float>(result.fp16Data_[0]), 4.0f);
}

TEST(LogicDieOutputBufferTest, CommitsCompletedTileToDownstreamStorage)
{
    LogicDieOutputBuffer buffer(2);
    const LogicDieOutputBuffer::TileId tile{11, 4, 0};
    BurstType first;
    BurstType second;
    BurstType result;
    first.set(fp16(1.25f));
    second.set(fp16(2.5f));
    buffer.beginLayer(11);

    ASSERT_TRUE(buffer.reserve(tile, 2));
    ASSERT_TRUE(buffer.write(tile, 1, second));
    EXPECT_FALSE(buffer.commitReadyFront());
    ASSERT_TRUE(buffer.write(tile, 0, first));
    ASSERT_TRUE(buffer.commitReadyFront());
    EXPECT_EQ(buffer.size(), 0u);
    ASSERT_TRUE(buffer.readCommitted(tile, 0, result));
    EXPECT_FLOAT_EQ(static_cast<float>(result.fp16Data_[0]), 1.25f);
    ASSERT_TRUE(buffer.readCommitted(tile, 1, result));
    EXPECT_FLOAT_EQ(static_cast<float>(result.fp16Data_[0]), 2.5f);
    EXPECT_TRUE(buffer.releaseCommitted(tile));
    EXPECT_FALSE(buffer.readCommitted(tile, 0, result));
}

TEST(LogicDieOutputBufferTest, AppliesConfiguredDrainLatencyAndBandwidth)
{
    LogicDieOutputBuffer buffer(2, 3, 2);
    const LogicDieOutputBuffer::TileId tile{12, 0, 0};
    BurstType value;
    BurstType result;
    buffer.beginLayer(12);

    ASSERT_TRUE(buffer.reserve(tile, 5));
    for (size_t burst = 0; burst < 5; burst++) ASSERT_TRUE(buffer.write(tile, burst, value));
    buffer.advance(100);
    EXPECT_FALSE(buffer.readCommitted(tile, 0, result));
    buffer.advance(105);
    EXPECT_FALSE(buffer.readCommitted(tile, 0, result));
    buffer.advance(106);
    EXPECT_TRUE(buffer.readCommitted(tile, 0, result));
    EXPECT_EQ(buffer.getDrainBusyCycles(), 6u);
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

    cout << "POINTWISE_BATCH_RETIREMENT_RESULT"
         << " positions[2]"
         << " outputs_checked[" << output.size() << "]"
         << " output_buffer[" << getConfigParam(BOOL, "LOGIC_OUTPUT_BUFFER_ENABLE") << "]"
         << " hab_residency[" << getConfigParam(BOOL, "LOGIC_HAB_RESIDENCY") << "]"
         << " source_queues[" << getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES") << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, PointwiseHabResidencyDrainsAcrossWaves)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    constexpr uint32_t positions = 128;
    vector<float> input(static_cast<uint64_t>(positions) * 3);
    for (uint32_t position = 0; position < positions; position++)
    {
        input[position * 3] = position + 1;
        input[position * 3 + 1] = position + 2;
        input[position * 3 + 2] = position + 3;
    }
    auto packedInput = packPointwiseBatchInput(input, positions, 3);
    auto weights = packPointwiseWeights({1, 0, 0, 0, 1, 0, 1, 1, 1}, 3, 3);
    auto output = pim.executePointwiseBatchAndRead(&weights, &packedInput, 3);

    ASSERT_EQ(output.size(), static_cast<uint64_t>(positions) * 3);
    for (uint32_t position = 0; position < positions; position++)
    {
        EXPECT_EQ(static_cast<float>(output[position * 3]), position + 1.0f);
        EXPECT_EQ(static_cast<float>(output[position * 3 + 1]), position + 2.0f);
        EXPECT_EQ(static_cast<float>(output[position * 3 + 2]), 3.0f * position + 6.0f);
    }

    cout << "HAB_RESIDENCY_WAVE_RESULT"
         << " positions[" << positions << "]"
         << " outputs_checked[" << output.size() << "]"
         << " spatial_groups[" << pim.getLastPointwiseSpatialGroups() << "]"
         << " batch_waves[" << pim.getLastPointwiseBatchWaves() << "]"
         << " hab_entries[" << pim.getLogicHabEntries() << "]"
         << " hab_exits[" << pim.getLogicHabExits() << "]"
         << " hab_residency[" << getConfigParam(BOOL, "LOGIC_HAB_RESIDENCY") << "]"
         << " source_queues[" << getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES") << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, PointwiseHabResidencySingleGroupTwoWaves)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 1, 1);
    auto input = packPointwiseBatchInput({1, 2, 3, 4, 5, 6}, 2, 3);
    auto weights = packPointwiseWeights({1, 0, 0, 0, 1, 0, 1, 1, 1}, 3, 3);
    auto output = pim.executePointwiseBatchAndRead(&weights, &input, 3);

    ASSERT_EQ(output.size(), 6u);
    const vector<float> expected = {1, 2, 6, 4, 5, 15};
    for (size_t index = 0; index < expected.size(); index++)
        EXPECT_EQ(static_cast<float>(output[index]), expected[index]);

    cout << "MODE_TRANSITION_LATENCY_RESULT"
         << " channels[1] positions[2] outputs_checked[" << output.size() << "]"
         << " spatial_groups[" << pim.getLastPointwiseSpatialGroups() << "]"
         << " batch_waves[" << pim.getLastPointwiseBatchWaves() << "]"
         << " hab_entries[" << pim.getLogicHabEntries() << "]"
         << " hab_exits[" << pim.getLogicHabExits() << "]"
         << " mode_latency[" << getConfigParam(UINT, "LOGIC_MODE_TRANSITION_LATENCY") << "]"
         << " hab_residency[" << getConfigParam(BOOL, "LOGIC_HAB_RESIDENCY") << "]"
         << " source_queues[" << getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES") << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, PointwiseHabResidencyThreeChannelGroup)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 3, 1);
    constexpr unsigned positions = 2;
    constexpr unsigned outputChannels = 192;
    vector<float> input = {1, 2, 3, 4, 5, 6};
    vector<float> weights(outputChannels * 3, 0.0f);
    for (unsigned output = 0; output < outputChannels; output++)
        weights[output * 3 + output % 3] = 1.0f;
    auto packedInput = packPointwiseBatchInput(input, positions, 3);
    auto packedWeights = packPointwiseWeights(weights, 3, outputChannels);
    const auto output = pim.executePointwiseBatchAndRead(
        &packedWeights, &packedInput, outputChannels);

    ASSERT_EQ(output.size(), static_cast<uint64_t>(positions) * outputChannels);
    for (unsigned position = 0; position < positions; position++)
        for (unsigned channel = 0; channel < outputChannels; channel++)
            EXPECT_EQ(static_cast<float>(output[position * outputChannels + channel]),
                      input[position * 3 + channel % 3]);
    EXPECT_EQ(pim.getRankCommandRejects(),
              pim.getRankModeTransitionRejects() + pim.getRankLogicQueueRejects());
    EXPECT_EQ(pim.getRankCommandRejects(),
              pim.getRankBankDomainRejects() + pim.getRankLogicDomainRejects());
    if (getConfigParam(BOOL, "LOGIC_DIRECT_STAGING_COMMAND_PATH"))
    {
        EXPECT_GT(pim.getLogicWeightFillCompletedWrites(), 0);
        EXPECT_EQ(pim.getLogicWeightFillActivates(), 0);
        EXPECT_EQ(pim.getLogicWeightFillPrecharges(), 0);
    }
    cout << "HAB_GROUP_SCALE_RESULT channels[3] groups[1] positions[2]"
         << " input_channels[3] output_channels[192] outputs_checked[" << output.size() << "]"
         << " hab_entries[" << pim.getLogicHabEntries() << "]"
         << " hab_exits[" << pim.getLogicHabExits() << "]"
         << " rank_command_rejects[" << pim.getRankCommandRejects() << "]"
         << " rank_mode_transition_rejects[" << pim.getRankModeTransitionRejects() << "]"
         << " rank_logic_queue_rejects[" << pim.getRankLogicQueueRejects() << "]"
         << " rank_bank_domain_rejects[" << pim.getRankBankDomainRejects() << "]"
         << " rank_logic_domain_rejects[" << pim.getRankLogicDomainRejects() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, PointwiseHabResidencyTwoThreeChannelGroups)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 6, 1);
    constexpr unsigned positions = 4;
    constexpr unsigned outputChannels = 192;
    vector<float> input(positions * 3);
    for (unsigned position = 0; position < positions; position++)
        for (unsigned channel = 0; channel < 3; channel++)
            input[position * 3 + channel] = position * 3 + channel + 1;
    vector<float> weights(outputChannels * 3, 0.0f);
    for (unsigned output = 0; output < outputChannels; output++)
        weights[output * 3 + output % 3] = 1.0f;
    auto packedInput = packPointwiseBatchInput(input, positions, 3);
    auto packedWeights = packPointwiseWeights(weights, 3, outputChannels);
    const auto output = pim.executePointwiseBatchAndRead(
        &packedWeights, &packedInput, outputChannels);

    ASSERT_EQ(output.size(), static_cast<uint64_t>(positions) * outputChannels);
    for (unsigned position = 0; position < positions; position++)
        for (unsigned channel = 0; channel < outputChannels; channel++)
            EXPECT_EQ(static_cast<float>(output[position * outputChannels + channel]),
                      input[position * 3 + channel % 3]);
    EXPECT_EQ(pim.getRankCommandRejects(),
              pim.getRankModeTransitionRejects() + pim.getRankLogicQueueRejects());
    EXPECT_EQ(pim.getRankCommandRejects(),
              pim.getRankBankDomainRejects() + pim.getRankLogicDomainRejects());
    cout << "HAB_GROUP_SCALE_RESULT channels[6] groups[2] positions[4]"
         << " input_channels[3] output_channels[192] outputs_checked[" << output.size() << "]"
         << " hab_entries[" << pim.getLogicHabEntries() << "]"
         << " hab_exits[" << pim.getLogicHabExits() << "]"
         << " rank_command_rejects[" << pim.getRankCommandRejects() << "]"
         << " rank_mode_transition_rejects[" << pim.getRankModeTransitionRejects() << "]"
         << " rank_logic_queue_rejects[" << pim.getRankLogicQueueRejects() << "]"
         << " rank_bank_domain_rejects[" << pim.getRankBankDomainRejects() << "]"
         << " rank_logic_domain_rejects[" << pim.getRankLogicDomainRejects() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, NonblockingSpatialPointwiseHandlePreservesBuffersAndOutput)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    if (!pim.usesLogicDiePIM() || !getConfigParam(BOOL, "LOGIC_SPATIAL_GROUPING"))
        GTEST_SKIP() << "Nonblocking spatial handle requires hybrid spatial configuration";

    auto input = packPointwiseBatchInput({1, 2, 3, 4, 5, 6}, 2, 3);
    auto weights = packPointwiseWeights({1, 0, 0, 0, 1, 0, 1, 1, 1}, 3, 3);
    const uint64_t startCycle = pim.getCycle();
    auto handle = pim.enqueuePointwiseSpatialGroups(&weights, &input, 3);
    const uint64_t enqueueCycle = pim.getCycle();
    EXPECT_FALSE(handle->waited);
    EXPECT_FALSE(handle->consumed);
    EXPECT_TRUE(memory->hasPendingTransactions());
    EXPECT_THROW(pim.readPointwiseSpatial(handle), logic_error);
    EXPECT_THROW(pim.enqueuePointwiseSpatialGroups(&weights, &input, 3), logic_error);

    pim.waitPointwiseSpatial(handle);
    const uint64_t waitCycle = pim.getCycle();
    EXPECT_TRUE(handle->waited);
    EXPECT_FALSE(memory->hasPendingTransactions());
    const auto output = pim.readPointwiseSpatial(handle);
    const vector<float> expected = {1, 2, 6, 4, 5, 15};
    ASSERT_EQ(output.size(), expected.size());
    for (size_t i = 0; i < expected.size(); i++)
        EXPECT_EQ(static_cast<float>(output[i]), expected[i]);
    EXPECT_THROW(pim.readPointwiseSpatial(handle), logic_error);
    cout << "NONBLOCKING_POINTWISE_RESULT"
         << " positions[2] input_channels[3] output_channels[3]"
         << " enqueue_cycles[" << enqueueCycle - startCycle << "]"
         << " wait_cycles[" << waitCycle - enqueueCycle << "]"
         << " outputs_checked[" << output.size() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, NonblockingExpandFeedsTwoDepthwiseTileRows)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    if (!pim.usesLogicDiePIM() || !getConfigParam(BOOL, "LOGIC_SPATIAL_GROUPING"))
        GTEST_SKIP() << "Tile-row halo test requires hybrid spatial configuration";

    const uint32_t height = 3;
    const uint32_t width = 14;
    const uint32_t inputChannels = 96;
    const uint32_t expandedChannels = 192;
    const uint32_t positions = height * width;
    vector<float> input(static_cast<uint64_t>(positions) * inputChannels, 1.0f);
    vector<float> weights(static_cast<uint64_t>(expandedChannels) * inputChannels, 0.0f);
    for (uint32_t output = 0; output < expandedChannels; output++)
        weights[static_cast<uint64_t>(output) * inputChannels + output % inputChannels] = 1.0f;
    auto packedInput = packPointwiseBatchInput(input, positions, inputChannels);
    auto packedWeights = packPointwiseWeights(weights, inputChannels, expandedChannels);

    auto handle = pim.enqueuePointwiseSpatialGroups(&packedWeights, &packedInput,
                                                     expandedChannels);
    pim.waitPointwiseSpatial(handle);
    const auto expandedFp16 = pim.readPointwiseSpatial(handle);
    vector<float> expanded(expandedFp16.size());
    transform(expandedFp16.begin(), expandedFp16.end(), expanded.begin(),
              [](fp16 value) { return static_cast<float>(value); });
    const vector<float> depthwiseWeights(3 * 3 * expandedChannels, 1.0f);
    const auto reference = MobileNetV4Workload::depthwiseReference(
        expanded, depthwiseWeights, height, width, expandedChannels, 3, 1);
    const auto layout = MobileNetV4Workload::makeDepthwiseTapLayout(
        expanded, depthwiseWeights, height, width, expandedChannels, 3, 1);
    const uint64_t paddedElements = 64ULL * 1 * 16 * 8 * 16;
    const auto depthwise = runDepthwiseTensor(pim, layout, paddedElements);

    const uint64_t checked = static_cast<uint64_t>(2) * width * expandedChannels;
    ASSERT_GE(depthwise.size(), checked);
    for (uint64_t index = 0; index < checked; index++)
        EXPECT_EQ(depthwise[index], reference[index]);
    cout << "NONBLOCKING_TILE_ROW_RESULT"
         << " input_rows[3] output_rows_checked[2] width[" << width << "]"
         << " channels[" << expandedChannels << "]"
         << " outputs_checked[" << checked << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, PointwiseSpatialSessionCompletesContiguousRowRanges)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    if (!pim.usesLogicDiePIM() || !getConfigParam(BOOL, "LOGIC_SPATIAL_GROUPING"))
        GTEST_SKIP() << "Row session test requires hybrid spatial configuration";

    const unsigned height = 3;
    const unsigned width = 4;
    const unsigned channels = 3;
    vector<float> input(height * width * channels);
    for (size_t index = 0; index < input.size(); index++) input[index] = index + 1;
    const vector<float> weights = {1, 0, 0, 0, 1, 0, 1, 1, 1};
    auto packedInput = packPointwiseBatchInput(input, height * width, channels);
    auto packedWeights = packPointwiseWeights(weights, channels, channels);
    auto session = pim.beginPointwiseSpatialSession(
        &packedWeights, &packedInput, height, width, channels);
    ActivationRowBuffer rowBuffer(height, width * channels, 3);

    pim.enqueuePointwiseRows(session, 0, 2);
    EXPECT_THROW(pim.enqueuePointwiseRows(session, 2, 1), logic_error);
    pim.waitPointwiseRows(session);
    const auto firstRows = pim.readPointwiseRows(session);
    EXPECT_EQ(firstRows.size(), 2u * width * channels);
    rowBuffer.pushRow(0, vector<fp16>(firstRows.begin(), firstRows.begin() + width * channels));
    rowBuffer.pushRow(1, vector<fp16>(firstRows.begin() + width * channels,
                                     firstRows.end()));
    ASSERT_TRUE(rowBuffer.canRelease());
    const auto topWindow = rowBuffer.release();
    EXPECT_EQ(topWindow.outputRow, 0u);
    for (unsigned index = 0; index < width * channels; index++)
    {
        EXPECT_EQ(static_cast<float>(topWindow.rows[index]), 0.0f);
        EXPECT_EQ(topWindow.rows[width * channels + index], firstRows[index]);
        EXPECT_EQ(topWindow.rows[2 * width * channels + index],
                  firstRows[width * channels + index]);
    }
    EXPECT_EQ(session->nextRow, 2u);
    EXPECT_THROW(pim.enqueuePointwiseRows(session, 0, 1), invalid_argument);

    pim.enqueuePointwiseRows(session, 2, 1);
    pim.waitPointwiseRows(session);
    const auto lastRow = pim.readPointwiseRows(session);
    EXPECT_EQ(lastRow.size(), width * channels);
    rowBuffer.pushRow(2, lastRow);
    ASSERT_TRUE(rowBuffer.canRelease());
    const auto middleWindow = rowBuffer.release();
    const auto bottomWindow = rowBuffer.release();
    EXPECT_EQ(middleWindow.outputRow, 1u);
    EXPECT_EQ(bottomWindow.outputRow, 2u);
    EXPECT_EQ(rowBuffer.releasedRows(), height);
    EXPECT_EQ(rowBuffer.peakRows(), 3u);
    EXPECT_EQ(session->nextRow, height);
    EXPECT_EQ(session->reusedRowRanges, 1u);
    EXPECT_GT(session->weightFillBursts, 0u);
    EXPECT_EQ(session->reusedWeightFillBursts, 0u);
    EXPECT_EQ(session->crfProgramCalls, 8u);
    EXPECT_EQ(session->reusedCrfProgramCalls, 0u);
    EXPECT_THROW(pim.enqueuePointwiseRows(session, 3, 1), invalid_argument);

    const auto reference = MobileNetV4Workload::pointwiseReference(
        input, weights, height, width, channels, channels);
    ASSERT_EQ(session->output.size(), reference.size());
    for (size_t index = 0; index < reference.size(); index++)
        EXPECT_EQ(static_cast<float>(session->output[index]), reference[index]);
    cout << "POINTWISE_ROW_SESSION_RESULT"
         << " height[" << height << "] width[" << width << "]"
         << " row_ranges[2] completed_rows[" << session->nextRow << "]"
         << " reused_ranges[" << session->reusedRowRanges << "]"
         << " weight_fill_bursts[" << session->weightFillBursts << "]"
         << " reused_fill_bursts[" << session->reusedWeightFillBursts << "]"
         << " crf_program_calls[" << session->crfProgramCalls << "]"
         << " reused_crf_calls[" << session->reusedCrfProgramCalls << "]"
         << " released_depthwise_rows[" << rowBuffer.releasedRows() << "]"
         << " line_buffer_peak_rows[" << rowBuffer.peakRows() << "]"
         << " outputs_checked[" << reference.size() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, ActivationRowBufferReleasesThreeByThreeHaloRows)
{
    const unsigned height = 4;
    const unsigned rowElements = 3;
    ActivationRowBuffer buffer(height, rowElements, 3);

    EXPECT_FALSE(buffer.canRelease());
    buffer.pushRow(0, {fp16(1), fp16(2), fp16(3)});
    EXPECT_FALSE(buffer.canRelease());
    buffer.pushRow(1, {fp16(4), fp16(5), fp16(6)});
    ASSERT_TRUE(buffer.canRelease());
    const auto top = buffer.release();
    EXPECT_EQ(top.outputRow, 0u);
    const vector<float> expectedTop = {0, 0, 0, 1, 2, 3, 4, 5, 6};
    for (size_t index = 0; index < expectedTop.size(); index++)
        EXPECT_EQ(static_cast<float>(top.rows[index]), expectedTop[index]);

    buffer.pushRow(2, {fp16(7), fp16(8), fp16(9)});
    const auto middle0 = buffer.release();
    const vector<float> expectedMiddle0 = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    for (size_t index = 0; index < expectedMiddle0.size(); index++)
        EXPECT_EQ(static_cast<float>(middle0.rows[index]), expectedMiddle0[index]);

    buffer.pushRow(3, {fp16(10), fp16(11), fp16(12)});
    const auto middle1 = buffer.release();
    const auto bottom = buffer.release();
    EXPECT_EQ(middle1.outputRow, 2u);
    EXPECT_EQ(bottom.outputRow, 3u);
    const vector<float> expectedBottom = {7, 8, 9, 10, 11, 12, 0, 0, 0};
    for (size_t index = 0; index < expectedBottom.size(); index++)
        EXPECT_EQ(static_cast<float>(bottom.rows[index]), expectedBottom[index]);
    EXPECT_EQ(buffer.completedRows(), height);
    EXPECT_EQ(buffer.releasedRows(), height);
    EXPECT_LE(buffer.peakRows(), 3u);
    cout << "ACTIVATION_ROW_BUFFER_RESULT"
         << " input_rows[" << height << "] released_rows[" << buffer.releasedRows() << "]"
         << " kernel[3] peak_rows[" << buffer.peakRows() << "]"
         << " values_checked[27]" << endl;
}

TEST(MobileNetV4WorkloadTest, BankDepthwiseStageAndLogicPointwiseShareDrain)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    if (!pim.usesLogicDiePIM() || !getConfigParam(BOOL, "LOGIC_SPATIAL_GROUPING"))
        GTEST_SKIP() << "Hierarchy overlap test requires hybrid spatial configuration";

    const unsigned height = 3;
    const unsigned width = 4;
    const unsigned channels = 3;
    vector<float> input(height * width * channels);
    for (size_t index = 0; index < input.size(); index++) input[index] = index + 1;
    const vector<float> weights = {1, 0, 0, 0, 1, 0, 1, 1, 1};
    auto packedInput = packPointwiseBatchInput(input, height * width, channels);
    auto packedWeights = packPointwiseWeights(weights, channels, channels);
    auto session = pim.beginPointwiseSpatialSession(
        &packedWeights, &packedInput, height, width, channels);

    pim.enqueuePointwiseRows(session, 0, 2);
    pim.waitPointwiseRows(session);
    pim.readPointwiseRows(session);
    pim.resetHierarchyActivity();

    const int depthwiseDim = 64 * 1 * 16 * 8;
    auto depthwise = pim.beginDepthwiseLowered(depthwiseDim, 3, 0, 256, 512, 576, 640, 16);
    pim.enqueueDepthwiseStage(depthwise);
    ASSERT_TRUE(depthwise->stagePending);
    ASSERT_TRUE(memory->hasPendingTransactions());

    const uint64_t overlapStart = pim.getCycle();
    pim.enqueuePointwiseRows(session, 2, 1);
    ASSERT_TRUE(session->activeHandle != nullptr);
    ASSERT_TRUE(memory->hasPendingTransactions());
    pim.waitPointwiseRows(session);
    const uint64_t sharedDrainEnd = pim.getCycle();
    EXPECT_FALSE(memory->hasPendingTransactions());
    const auto lastRow = pim.readPointwiseRows(session);
    pim.waitDepthwiseStage(depthwise);
    EXPECT_EQ(depthwise->nextStage, 1u);
    EXPECT_FALSE(depthwise->stagePending);

    const auto reference = MobileNetV4Workload::pointwiseReference(
        input, weights, height, width, channels, channels);
    ASSERT_EQ(lastRow.size(), width * channels);
    const uint64_t offset = static_cast<uint64_t>(2) * width * channels;
    for (size_t index = 0; index < lastRow.size(); index++)
        EXPECT_EQ(static_cast<float>(lastRow[index]), reference[offset + index]);
    const auto activity = pim.getHierarchyActivityStats();
    EXPECT_GT(activity.bankIssues, 0u);
    EXPECT_GT(activity.logicIssues, 0u);
    if (getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES"))
    {
        EXPECT_GT(activity.overlappingWindowCycles, 0u);
        EXPECT_LE(activity.logicFirstIssue, activity.bankLastIssue);
        EXPECT_LE(activity.bankFirstIssue, activity.logicLastIssue);
    }
    else
    {
        EXPECT_EQ(activity.overlappingWindowCycles, 0u);
        EXPECT_LT(activity.bankLastIssue, activity.logicFirstIssue);
    }
    cout << "HIERARCHY_SHARED_DRAIN_RESULT"
         << " bank_stages_enqueued[1] bank_stages_completed[1]"
         << " logic_rows_enqueued[1] logic_outputs_checked[" << lastRow.size() << "]"
         << " shared_drain_cycles[" << sharedDrainEnd - overlapStart << "]"
         << " bank_issues[" << activity.bankIssues << "]"
         << " logic_issues[" << activity.logicIssues << "]"
         << " bank_first_issue[" << activity.bankFirstIssue << "]"
         << " bank_last_issue[" << activity.bankLastIssue << "]"
         << " logic_first_issue[" << activity.logicFirstIssue << "]"
         << " logic_last_issue[" << activity.logicLastIssue << "]"
         << " overlapping_issue_cycles[" << activity.overlappingIssueCycles << "]"
         << " overlapping_window_cycles[" << activity.overlappingWindowCycles << "]"
         << " pending_after_drain[" << memory->hasPendingTransactions() << "]" << endl;
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
    const char* requestedLayer = getenv("MOBILENETV4_LAYER_NAME");
    const string layerName = requestedLayer == nullptr ? "uib14_ib_expand" : requestedLayer;
    const auto layer = find_if(layers.begin(), layers.end(), [&layerName](const MobileNetV4Layer& item) {
        return item.name == layerName;
    });
    ASSERT_NE(layer, layers.end()) << "Unknown MOBILENETV4_LAYER_NAME: " << layerName;
    ASSERT_EQ(layer->op, WorkloadOp::POINTWISE_CONV);
    const uint32_t positions = layer->height * layer->width;
    vector<float> input(static_cast<uint64_t>(positions) * layer->inputChannels, 1.0f);
    vector<float> weights(
        static_cast<uint64_t>(layer->outputChannels) * layer->inputChannels, 1.0f);
    const uint32_t physicalInputChannels =
        ((layer->inputChannels + 127) / 128) * 128;
    auto packedInput =
        packPointwiseBatchInput(input, positions, layer->inputChannels, physicalInputChannels);
    auto packedWeights = packPointwiseWeights(weights, layer->inputChannels,
                                               layer->outputChannels, physicalInputChannels);

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    PIMKernel pim(memory, 64, 1);
    auto output =
        pim.executePointwiseBatchAndRead(&packedWeights, &packedInput, layer->outputChannels);

    ASSERT_EQ(output.size(), static_cast<uint64_t>(positions) * layer->outputChannels);
    for (const auto& value : output)
        EXPECT_EQ(static_cast<float>(value), static_cast<float>(layer->inputChannels));
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
         << " logic_release_epochs[" << pim.getLogicReleaseEpochCount() << "]"
         << " logic_release_max_streams[" << pim.getLogicReleaseMaxStreams() << "]"
         << " logic_release_complete_masks[" << pim.getLogicReleaseCompleteMasks() << "]"
         << " logic_release_incomplete_masks[" << pim.getLogicReleaseIncompleteMasks() << "]"
         << " logic_broadcast_masks[" << pim.getLogicBroadcastMaskCount() << "]"
         << " logic_broadcast_fanout[" << pim.getLogicBroadcastFanout() << "]"
         << " logic_broadcast_min_fanout[" << pim.getLogicBroadcastMinFanout() << "]"
         << " logic_broadcast_max_fanout[" << pim.getLogicBroadcastMaxFanout() << "]"
         << " logic_epoch1_masks[" << pim.getLogicEpochStats(1).maskCount << "]"
         << " logic_epoch1_fanout[" << pim.getLogicEpochStats(1).totalFanout << "]"
         << " logic_epoch1_max_residency[" << pim.getLogicEpochStats(1).maxResidencyCycles << "]"
         << " logic_epoch1_total_residency[" << pim.getLogicEpochStats(1).totalResidencyCycles << "]"
         << " logic_epoch1_peak_open_masks[" << pim.getLogicEpochStats(1).peakOpenMasks << "]"
         << " logic_epoch1_online_peak_open_masks["
         << pim.getLogicEpochStats(1).onlinePeakOpenMasks << "]"
         << " logic_epoch1_online_full_events["
         << pim.getLogicEpochStats(1).onlineQueueFullEvents << "]"
         << " logic_epoch1_incomplete_expected_masks["
         << pim.getLogicEpochStats(1).incompleteExpectedMasks << "]"
         << " logic_epoch2_masks[" << pim.getLogicEpochStats(2).maskCount << "]"
         << " logic_epoch2_fanout[" << pim.getLogicEpochStats(2).totalFanout << "]"
         << " logic_epoch2_max_residency[" << pim.getLogicEpochStats(2).maxResidencyCycles << "]"
         << " logic_epoch2_total_residency[" << pim.getLogicEpochStats(2).totalResidencyCycles << "]"
         << " logic_epoch2_peak_open_masks[" << pim.getLogicEpochStats(2).peakOpenMasks << "]"
         << " logic_epoch2_online_peak_open_masks["
         << pim.getLogicEpochStats(2).onlinePeakOpenMasks << "]"
         << " logic_epoch2_online_full_events["
         << pim.getLogicEpochStats(2).onlineQueueFullEvents << "]"
         << " logic_epoch2_incomplete_expected_masks["
         << pim.getLogicEpochStats(2).incompleteExpectedMasks << "]"
         << " logic_broadcast_queue_stall_cycles["
         << pim.getLogicBroadcastQueueStallCycles() << "]"
         << " logic_broadcast_queue_full_events["
         << pim.getLogicBroadcastQueueFullEvents() << "]"
         << " logic_broadcast_queue_applied_cycles["
         << pim.getLogicBroadcastQueueAppliedCycles() << "]"
         << " logic_broadcast_queue_last_pre_stall_cycle["
         << pim.getLogicBroadcastQueueLastPreStallCycle() << "]"
         << " logic_online_issue_blocked_channel_cycles["
         << pim.getLogicOnlineIssueStallCycles() << "]"
         << " logic_online_issue_busy_overlap_channel_cycles["
         << pim.getLogicOnlineIssueBusyOverlapCycles() << "]"
         << " logic_blocked_wall_cycles[" << pim.getLogicBlockedWallCycles() << "]"
         << " logic_blocked_streams[" << pim.getLogicBlockedStreamCount() << "]"
         << " logic_min_blocked_per_stream[" << pim.getLogicMinBlockedCyclesPerStream() << "]"
         << " logic_max_blocked_per_stream[" << pim.getLogicMaxBlockedCyclesPerStream() << "]"
         << " logic_min_issued_per_stream[" << pim.getLogicMinIssuedCommandsPerStream() << "]"
         << " logic_max_issued_per_stream[" << pim.getLogicMaxIssuedCommandsPerStream() << "]"
         << " logic_blocked_stream_mask_low[" << pim.getLogicBlockedStreamMaskLow() << "]"
         << " logic_blocked_stream_mask_high[" << pim.getLogicBlockedStreamMaskHigh() << "]"
         << " command_predicate_reject_cycles[" << pim.getCommandPredicateRejectCycles() << "]"
         << " command_predicate_hol_cycles[" << pim.getCommandPredicateHolCycles() << "]"
         << " command_predicate_hol_candidates["
         << pim.getCommandPredicateHolCandidates() << "]"
         << " command_predicate_hol_max_candidates["
         << pim.getCommandPredicateHolMaxCandidates() << "]"
         << " command_predicate_bypass_issues["
         << pim.getCommandPredicateBypassIssues() << "]"
         << " issuability_logic_busy_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::LOGIC_PCU_BUSY)
         << "] issuability_logic_busy_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::LOGIC_PCU_BUSY)
         << "] issuability_mode_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "] issuability_mode_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "] issuability_bank_state_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::BANK_STATE)
         << "] issuability_bank_state_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::BANK_STATE)
         << "] issuability_timing_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::TIMING)
         << "] issuability_timing_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::TIMING)
         << "] issuability_row_mismatch_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] issuability_row_mismatch_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] issuability_row_limit_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT)
         << "] issuability_row_limit_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT)
         << "] issuability_xaw_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::XAW_LIMIT)
         << "] issuability_xaw_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::XAW_LIMIT) << "]"
         << " epoch_mismatch_rejects[" << pim.getEpochMismatchRejects() << "]"
         << " barrier_outstanding_rejects[" << pim.getBarrierOutstandingRejects() << "]"
         << " write_bus_busy_rejects[" << pim.getWriteBusBusyRejects() << "]"
         << " rank_command_rejects[" << pim.getRankCommandRejects() << "]"
         << " rank_mode_transition_rejects[" << pim.getRankModeTransitionRejects() << "]"
         << " rank_logic_queue_rejects[" << pim.getRankLogicQueueRejects() << "]"
         << " rank_bank_domain_rejects[" << pim.getRankBankDomainRejects() << "]"
         << " rank_logic_domain_rejects[" << pim.getRankLogicDomainRejects() << "]"
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
         << " total_cycle[" << pim.getCycle() << "]"
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
    if (getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION"))
    {
        const uint64_t aggregationTaps =
            getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS");
        EXPECT_EQ(pim.getDepthwiseAccumulatorPartialBursts(),
                  paddedElements / 16 * (9 / aggregationTaps));
        EXPECT_EQ(pim.getDepthwiseAccumulatorFinalBursts(), paddedElements / 16);
        EXPECT_EQ(pim.getDepthwiseAccumulatorPeakEntries(), paddedElements / 16);
        EXPECT_TRUE(memory->logicDieAccumulator->empty());
    }
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
         << " logic_release_epochs[" << pim.getLogicReleaseEpochCount() << "]"
         << " logic_release_max_streams[" << pim.getLogicReleaseMaxStreams() << "]"
         << " logic_release_complete_masks[" << pim.getLogicReleaseCompleteMasks() << "]"
         << " logic_release_incomplete_masks[" << pim.getLogicReleaseIncompleteMasks() << "]"
         << " logic_broadcast_masks[" << pim.getLogicBroadcastMaskCount() << "]"
         << " logic_broadcast_fanout[" << pim.getLogicBroadcastFanout() << "]"
         << " logic_broadcast_min_fanout[" << pim.getLogicBroadcastMinFanout() << "]"
         << " logic_broadcast_max_fanout[" << pim.getLogicBroadcastMaxFanout() << "]"
         << " logic_epoch1_masks[" << pim.getLogicEpochStats(1).maskCount << "]"
         << " logic_epoch1_fanout[" << pim.getLogicEpochStats(1).totalFanout << "]"
         << " logic_epoch1_max_residency[" << pim.getLogicEpochStats(1).maxResidencyCycles << "]"
         << " logic_epoch1_total_residency[" << pim.getLogicEpochStats(1).totalResidencyCycles << "]"
         << " logic_epoch1_peak_open_masks[" << pim.getLogicEpochStats(1).peakOpenMasks << "]"
         << " logic_epoch1_online_peak_open_masks["
         << pim.getLogicEpochStats(1).onlinePeakOpenMasks << "]"
         << " logic_epoch1_online_full_events["
         << pim.getLogicEpochStats(1).onlineQueueFullEvents << "]"
         << " logic_epoch1_incomplete_expected_masks["
         << pim.getLogicEpochStats(1).incompleteExpectedMasks << "]"
         << " logic_epoch2_masks[" << pim.getLogicEpochStats(2).maskCount << "]"
         << " logic_epoch2_fanout[" << pim.getLogicEpochStats(2).totalFanout << "]"
         << " logic_epoch2_max_residency[" << pim.getLogicEpochStats(2).maxResidencyCycles << "]"
         << " logic_epoch2_total_residency[" << pim.getLogicEpochStats(2).totalResidencyCycles << "]"
         << " logic_epoch2_peak_open_masks[" << pim.getLogicEpochStats(2).peakOpenMasks << "]"
         << " logic_epoch2_online_peak_open_masks["
         << pim.getLogicEpochStats(2).onlinePeakOpenMasks << "]"
         << " logic_epoch2_online_full_events["
         << pim.getLogicEpochStats(2).onlineQueueFullEvents << "]"
         << " logic_epoch2_incomplete_expected_masks["
         << pim.getLogicEpochStats(2).incompleteExpectedMasks << "]"
         << " logic_broadcast_queue_stall_cycles["
         << pim.getLogicBroadcastQueueStallCycles() << "]"
         << " logic_broadcast_queue_full_events["
         << pim.getLogicBroadcastQueueFullEvents() << "]"
         << " logic_broadcast_queue_applied_cycles["
         << pim.getLogicBroadcastQueueAppliedCycles() << "]"
         << " logic_broadcast_queue_last_pre_stall_cycle["
         << pim.getLogicBroadcastQueueLastPreStallCycle() << "]"
         << " logic_online_issue_blocked_channel_cycles["
         << pim.getLogicOnlineIssueStallCycles() << "]"
         << " logic_online_issue_busy_overlap_channel_cycles["
         << pim.getLogicOnlineIssueBusyOverlapCycles() << "]"
         << " logic_blocked_wall_cycles[" << pim.getLogicBlockedWallCycles() << "]"
         << " logic_blocked_streams[" << pim.getLogicBlockedStreamCount() << "]"
         << " logic_min_blocked_per_stream[" << pim.getLogicMinBlockedCyclesPerStream() << "]"
         << " logic_max_blocked_per_stream[" << pim.getLogicMaxBlockedCyclesPerStream() << "]"
         << " logic_min_issued_per_stream[" << pim.getLogicMinIssuedCommandsPerStream() << "]"
         << " logic_max_issued_per_stream[" << pim.getLogicMaxIssuedCommandsPerStream() << "]"
         << " logic_blocked_stream_mask_low[" << pim.getLogicBlockedStreamMaskLow() << "]"
         << " logic_blocked_stream_mask_high[" << pim.getLogicBlockedStreamMaskHigh() << "]"
         << " command_predicate_reject_cycles[" << pim.getCommandPredicateRejectCycles() << "]"
         << " command_predicate_hol_cycles[" << pim.getCommandPredicateHolCycles() << "]"
         << " command_predicate_hol_candidates["
         << pim.getCommandPredicateHolCandidates() << "]"
         << " command_predicate_hol_max_candidates["
         << pim.getCommandPredicateHolMaxCandidates() << "]"
         << " command_predicate_bypass_issues["
         << pim.getCommandPredicateBypassIssues() << "]"
         << " epoch_mismatch_rejects[" << pim.getEpochMismatchRejects() << "]"
         << " barrier_outstanding_rejects[" << pim.getBarrierOutstandingRejects() << "]"
         << " write_bus_busy_rejects[" << pim.getWriteBusBusyRejects() << "]"
         << " rank_command_rejects[" << pim.getRankCommandRejects() << "]"
         << " rank_mode_transition_rejects[" << pim.getRankModeTransitionRejects() << "]"
         << " rank_logic_queue_rejects[" << pim.getRankLogicQueueRejects() << "]"
         << " rank_bank_domain_rejects[" << pim.getRankBankDomainRejects() << "]"
         << " rank_logic_domain_rejects[" << pim.getRankLogicDomainRejects() << "]"
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
    cout << "COMMAND_ISSUABILITY_RESULT"
         << " rank_mode_blocked_controller_cycles["
         << pim.getRankModeBlockedControllerCycles()
         << "] rank_logic_queue_blocked_controller_cycles["
         << pim.getRankLogicQueueBlockedControllerCycles() << "]"
         << " logic_busy_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::LOGIC_PCU_BUSY)
         << "] logic_busy_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::LOGIC_PCU_BUSY)
         << "] mode_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "] mode_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "] bank_state_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::BANK_STATE)
         << "] bank_state_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::BANK_STATE)
         << "] timing_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::TIMING)
         << "] timing_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::TIMING)
         << "] row_mismatch_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] row_mismatch_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] row_limit_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT)
         << "] row_limit_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT)
         << "] xaw_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::XAW_LIMIT)
         << "] xaw_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::XAW_LIMIT) << "]"
         << " bank_state_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::BANK_STATE)
         << "] timing_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::TIMING)
         << "] row_mismatch_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] mode_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "]"
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

    auto bankOnlyCycles = [&pim]() { return pim.getGlobalBankStateOnlyCycles(); };
    auto hierarchyAllCycles = [&pim]() {
        return pim.getGlobalHierarchyUnionAllActiveBlockedCycles();
    };
    auto bankAllCycles = [&pim]() {
        return pim.getGlobalAllActiveBlockedCycles(
            CommandIssuabilityRejectReason::BANK_STATE);
    };
    constexpr size_t commandTagCount = static_cast<size_t>(CommandTagClass::COUNT);
    auto bankTagAllCycles = [&pim]() {
        array<uint64_t, commandTagCount> cycles{};
        for (size_t tagClass = 0; tagClass < commandTagCount; tagClass++)
            cycles[tagClass] = pim.getGlobalBankTagAllActiveBlockedCycles(
                static_cast<CommandTagClass>(tagClass));
        return cycles;
    };
    constexpr size_t predicateCount =
        static_cast<size_t>(HierarchyPredicateBlockReason::COUNT);
    auto predicateAllCycles = [&pim]() {
        array<uint64_t, predicateCount> cycles{};
        for (size_t reason = 0; reason < predicateCount; reason++)
            cycles[reason] = pim.getGlobalPredicateAllActiveBlockedCycles(
                static_cast<HierarchyPredicateBlockReason>(reason));
        return cycles;
    };

    const uint64_t expandStartCycle = pim.getCycle();
    const uint64_t expandBankOnlyStart = bankOnlyCycles();
    const uint64_t expandHierarchyAllStart = hierarchyAllCycles();
    const uint64_t expandBankAllStart = bankAllCycles();
    const auto expandTagAllStart = bankTagAllCycles();
    const auto expandPredicateStart = predicateAllCycles();
    accountTransfer(input.size() * sizeof(uint16_t));
    auto expandedFp16 =
        pim.executePointwiseBatchAndRead(&packedExpandWeights, &packedInput, expandedChannels);
    const unsigned expandSpatialGroups = pim.getLastPointwiseSpatialGroups();
    const unsigned expandBatchWaves = pim.getLastPointwiseBatchWaves();
    vector<float> expanded(expandedFp16.size());
    transform(expandedFp16.begin(), expandedFp16.end(), expanded.begin(),
              [](fp16 value) { return static_cast<float>(value); });
    accountTransfer(expanded.size() * sizeof(uint16_t));
    const uint64_t expandEndCycle = pim.getCycle();
    const uint64_t expandBankOnly = bankOnlyCycles() - expandBankOnlyStart;
    const uint64_t expandHierarchyAll = hierarchyAllCycles() - expandHierarchyAllStart;
    const uint64_t expandBankAll = bankAllCycles() - expandBankAllStart;
    const auto expandTagAllEnd = bankTagAllCycles();
    const auto expandPredicateEnd = predicateAllCycles();

    const uint64_t depthwiseStartCycle = pim.getCycle();
    const uint64_t depthwiseBankOnlyStart = bankOnlyCycles();
    const uint64_t depthwiseHierarchyAllStart = hierarchyAllCycles();
    const uint64_t depthwiseBankAllStart = bankAllCycles();
    const auto depthwisePredicateStart = predicateAllCycles();
    auto tapLayout = MobileNetV4Workload::makeDepthwiseTapLayout(
        expanded, depthwiseWeights, height, width, expandedChannels, 3, 1);
    auto depthwise = runDepthwiseTensor(pim, tapLayout, paddedElements);
    accountTransfer(depthwise.size() * sizeof(uint16_t));
    const uint64_t depthwiseEndCycle = pim.getCycle();
    const uint64_t depthwiseBankOnly = bankOnlyCycles() - depthwiseBankOnlyStart;
    const uint64_t depthwiseHierarchyAll = hierarchyAllCycles() - depthwiseHierarchyAllStart;
    const uint64_t depthwiseBankAll = bankAllCycles() - depthwiseBankAllStart;
    const auto depthwisePredicateEnd = predicateAllCycles();

    const uint64_t projectStartCycle = pim.getCycle();
    const uint64_t projectBankOnlyStart = bankOnlyCycles();
    const uint64_t projectHierarchyAllStart = hierarchyAllCycles();
    const uint64_t projectBankAllStart = bankAllCycles();
    const auto projectTagAllStart = bankTagAllCycles();
    const auto projectPredicateStart = predicateAllCycles();
    const uint64_t projectOrderedBarriersStart =
        pim.getWriteBarrierCompletions(WriteCompletionClass::ORDERED);
    const uint64_t projectModeBarriersStart =
        pim.getWriteBarrierCompletions(WriteCompletionClass::PIM_MODE);
    const uint64_t projectControlBarriersStart =
        pim.getWriteBarrierCompletions(WriteCompletionClass::PIM_CONTROL);
    const uint64_t projectWritebackBarriersStart =
        pim.getWriteBarrierCompletions(WriteCompletionClass::PIM_WRITEBACK);
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
    const uint64_t projectEndCycle = pim.getCycle();
    const uint64_t projectBankOnly = bankOnlyCycles() - projectBankOnlyStart;
    const uint64_t projectHierarchyAll = hierarchyAllCycles() - projectHierarchyAllStart;
    const uint64_t projectBankAll = bankAllCycles() - projectBankAllStart;
    const auto projectTagAllEnd = bankTagAllCycles();
    const auto projectPredicateEnd = predicateAllCycles();
    const uint64_t projectOrderedBarriers =
        pim.getWriteBarrierCompletions(WriteCompletionClass::ORDERED) -
        projectOrderedBarriersStart;
    const uint64_t projectModeBarriers =
        pim.getWriteBarrierCompletions(WriteCompletionClass::PIM_MODE) -
        projectModeBarriersStart;
    const uint64_t projectControlBarriers =
        pim.getWriteBarrierCompletions(WriteCompletionClass::PIM_CONTROL) -
        projectControlBarriersStart;
    const uint64_t projectWritebackBarriers =
        pim.getWriteBarrierCompletions(WriteCompletionClass::PIM_WRITEBACK) -
        projectWritebackBarriersStart;

    const uint64_t addStartCycle = pim.getCycle();
    const uint64_t addBankOnlyStart = bankOnlyCycles();
    const uint64_t addHierarchyAllStart = hierarchyAllCycles();
    const uint64_t addBankAllStart = bankAllCycles();
    const auto addPredicateStart = predicateAllCycles();
    auto projectedPadded = packFp16Plane(projected, paddedElements);
    auto residualPadded = packFp16Plane(input, paddedElements);
    pim.preloadNoReplacement(&projectedPadded, 0, 0);
    pim.preloadNoReplacement(&residualPadded, 256, 0);
    pim.executeEltwise(paddedElements / 16, pimBankType::ALL_BANK, KernelType::ADD, 0, 512, 256);
    pim.runPIM();
    const uint64_t addEndCycle = pim.getCycle();
    const uint64_t addBankOnly = bankOnlyCycles() - addBankOnlyStart;
    const uint64_t addHierarchyAll = hierarchyAllCycles() - addHierarchyAllStart;
    const uint64_t addBankAll = bankAllCycles() - addBankAllStart;
    const auto addPredicateEnd = predicateAllCycles();
    const uint64_t reluStartCycle = pim.getCycle();
    const uint64_t reluBankOnlyStart = bankOnlyCycles();
    const uint64_t reluHierarchyAllStart = hierarchyAllCycles();
    const uint64_t reluBankAllStart = bankAllCycles();
    const auto reluPredicateStart = predicateAllCycles();
    pim.executeEltwise(paddedElements / 16, pimBankType::ALL_BANK, KernelType::RELU, 512, 768);
    vector<BurstType> rawOutput(paddedElements / 16);
    pim.readData(rawOutput.data(), rawOutput.size(), 768, 0);
    pim.runPIM();
    const uint64_t reluEndCycle = pim.getCycle();
    const uint64_t reluBankOnly = bankOnlyCycles() - reluBankOnlyStart;
    const uint64_t reluHierarchyAll = hierarchyAllCycles() - reluHierarchyAllStart;
    const uint64_t reluBankAll = bankAllCycles() - reluBankAllStart;
    const auto reluPredicateEnd = predicateAllCycles();

    const string uibTracePath = getConfigParam(STRING, "LOGIC_UIB_TRACE_FILE");
    if (!uibTracePath.empty() && uibTracePath != "none")
    {
        ofstream trace(uibTracePath);
        ASSERT_TRUE(trace) << "Unable to open UIB trace: " << uibTracePath;
        trace << "sequence,stage,target,start_cycle,end_cycle,cycles,input_elements,"
                 "output_elements,input_fp16_hash,output_fp16_hash\n";
        const auto writeStage = [&trace](unsigned sequence, const string& stage,
                                         const string& target, uint64_t start, uint64_t end,
                                         uint64_t inputElements, uint64_t outputElements,
                                         const string& inputHash, const string& outputHash) {
            trace << sequence << ',' << stage << ',' << target << ',' << start << ',' << end
                  << ',' << end - start << ',' << inputElements << ',' << outputElements << ','
                  << inputHash << ',' << outputHash << '\n';
        };
        const string inputHash = fp16Hash(input);
        const string expandedHash = fp16Hash(expandedFp16);
        const string depthwiseHash = fp16Hash(depthwise);
        const string projectedHash = fp16Hash(projectedFp16);
        vector<fp16> residualOutput(input.size());
        for (uint64_t index = 0; index < input.size(); ++index)
            residualOutput[index] = rawOutput[index / 16].fp16Data_[index % 16];
        const string finalHash = fp16Hash(residualOutput);
        writeStage(0, "expand_pointwise", "logic_die", expandStartCycle, expandEndCycle,
                   input.size(), expandedFp16.size(), inputHash, expandedHash);
        writeStage(1, "depthwise_3x3", "bank_to_logic", depthwiseStartCycle,
                   depthwiseEndCycle, expandedFp16.size(), depthwise.size(), expandedHash,
                   depthwiseHash);
        writeStage(2, "project_pointwise", "logic_die", projectStartCycle, projectEndCycle,
                   depthwise.size(), projectedFp16.size(), depthwiseHash, projectedHash);
        writeStage(3, "residual_add", "bank_side", addStartCycle, addEndCycle,
                   projectedFp16.size() + input.size(), input.size(),
                   projectedHash + "+" + inputHash, finalHash);
        writeStage(4, "relu_readback", "bank_side", reluStartCycle, reluEndCycle,
                   input.size(), input.size(), finalHash, finalHash);

        ofstream requests(uibTracePath + ".requests.csv");
        ASSERT_TRUE(requests) << "Unable to open UIB request trace: " << uibTracePath;
        requests << "sequence,stage,arrival_cycle,service_start_cycle,completion_cycle,"
                    "queue_cycles,compute_cycles,transfer_bytes,transfer_cycles,service_cycles,"
                    "stream_id,epoch_id,command_ordinal,dispatch_signature,blocks,coalesced\n";
        uint64_t requestSequence = 0;
        for (const auto& event : memory->logicDieScheduler->getReservationEvents())
        {
            const char* stage = nullptr;
            if (event.arrivalCycle >= expandStartCycle && event.arrivalCycle < expandEndCycle)
                stage = "expand_pointwise";
            else if (event.arrivalCycle >= projectStartCycle &&
                     event.arrivalCycle < projectEndCycle)
                stage = "project_pointwise";
            if (stage == nullptr) continue;
            requests << requestSequence++ << ',' << stage << ',' << event.arrivalCycle << ','
                     << event.serviceStartCycle << ',' << event.completionCycle << ','
                     << event.queueCycles << ',' << event.computeCycles << ','
                     << event.transferBytes << ',' << event.transferCycles << ','
                     << event.serviceCycles << ',' << event.streamId << ',' << event.epochId
                     << ',' << event.commandOrdinal << ',' << event.dispatchSignature << ','
                     << event.blocks << ',' << event.commandCoalesced << '\n';
        }
    }
    array<uint64_t, commandTagCount> expandTagAll{};
    array<uint64_t, commandTagCount> projectTagAll{};
    for (size_t tagClass = 0; tagClass < commandTagCount; tagClass++)
    {
        expandTagAll[tagClass] = expandTagAllEnd[tagClass] - expandTagAllStart[tagClass];
        projectTagAll[tagClass] = projectTagAllEnd[tagClass] - projectTagAllStart[tagClass];
    }
    auto tagValue = [](const array<uint64_t, commandTagCount>& values,
                       CommandTagClass tagClass) {
        return values[static_cast<size_t>(tagClass)];
    };
    auto predicateDelta = [](const array<uint64_t, predicateCount>& end,
                             const array<uint64_t, predicateCount>& start,
                             HierarchyPredicateBlockReason reason) {
        const size_t index = static_cast<size_t>(reason);
        return end[index] - start[index];
    };

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
    EXPECT_EQ(pim.getLogicOutputBufferReservations(), 2 * positions);
    EXPECT_EQ(pim.getLogicOutputBufferRetirements(), 2 * positions);
    // Callback-driven output returns retry every blocked channel-cycle, so this
    // counter measures backpressure intensity rather than rejected tile count.
    EXPECT_GT(pim.getLogicOutputBufferFullStalls(), 0u);
    EXPECT_EQ(pim.getLogicOutputBufferPeakEntries(), 2u);
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
    const auto formatRawTagCounts = [](const map<string, uint64_t>& counts) {
        string formatted;
        for (const auto& entry : counts)
        {
            if (!formatted.empty()) formatted += "|";
            formatted += entry.first + ":" + to_string(entry.second);
        }
        return formatted;
    };
    const string barrierRawTags =
        formatRawTagCounts(pim.getBarrierOutstandingRejectsByRawTag());
    const string epochRawTags = formatRawTagCounts(pim.getEpochMismatchRejectsByRawTag());
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
         << " expand_stage_cycles[" << expandEndCycle - expandStartCycle << "]"
         << " depthwise_stage_cycles[" << depthwiseEndCycle - depthwiseStartCycle << "]"
         << " depthwise_logic_accumulation["
         << getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION") << "]"
         << " depthwise_bank_local_aggregation_taps["
         << getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS") << "]"
         << " depthwise_bank_local_accumulator_entries["
         << getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_ENTRIES") << "]"
         << " depthwise_bank_local_accumulator_ports["
         << getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_PORTS") << "]"
         << " depthwise_bank_local_accumulator_latency["
         << getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_LATENCY") << "]"
         << " depthwise_bank_local_accumulator_banks["
         << getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_BANKS") << "]"
         << " depthwise_bank_local_accumulator_peak_entries["
         << pim.getBankLocalAccumulatorPeakEntries() << "]"
         << " depthwise_bank_local_accumulator_peak_entries_per_bank["
         << pim.getBankLocalAccumulatorPeakEntriesPerBank() << "]"
         << " depthwise_bank_local_accumulator_stalls["
         << pim.getBankLocalAccumulatorStalls() << "]"
         << " depthwise_accum_partial_bursts["
         << pim.getDepthwiseAccumulatorPartialBursts() << "]"
         << " depthwise_accum_final_bursts["
         << pim.getDepthwiseAccumulatorFinalBursts() << "]"
         << " depthwise_accum_peak_entries["
         << pim.getDepthwiseAccumulatorPeakEntries() << "]"
         << " depthwise_accum_transfer_bytes["
         << pim.getDepthwiseAccumulatorTransferBytes() << "]"
         << " depthwise_accum_transfer_cycles["
         << pim.getDepthwiseAccumulatorTransferCycles() << "]"
         << " depthwise_accum_overlap_cycles["
         << pim.getDepthwiseAccumulatorOverlapCycles() << "]"
         << " depthwise_accum_wait_cycles["
         << pim.getDepthwiseAccumulatorWaitCycles() << "]"
         << " project_stage_cycles[" << projectEndCycle - projectStartCycle << "]"
         << " project_ordered_write_barriers[" << projectOrderedBarriers << "]"
         << " project_mode_write_barriers[" << projectModeBarriers << "]"
         << " project_control_write_barriers[" << projectControlBarriers << "]"
         << " project_writeback_barriers[" << projectWritebackBarriers << "]"
         << " barrier_wait_ordered["
         << pim.getBarrierOutstandingRejects(WriteCompletionClass::ORDERED) << "]"
         << " barrier_wait_mode["
         << pim.getBarrierOutstandingRejects(WriteCompletionClass::PIM_MODE) << "]"
         << " barrier_wait_control["
         << pim.getBarrierOutstandingRejects(WriteCompletionClass::PIM_CONTROL) << "]"
         << " barrier_wait_writeback["
         << pim.getBarrierOutstandingRejects(WriteCompletionClass::PIM_WRITEBACK) << "]"
         << " epoch_wait_ordered["
         << pim.getEpochMismatchRejects(WriteCompletionClass::ORDERED) << "]"
         << " epoch_wait_mode["
         << pim.getEpochMismatchRejects(WriteCompletionClass::PIM_MODE) << "]"
         << " epoch_wait_control["
         << pim.getEpochMismatchRejects(WriteCompletionClass::PIM_CONTROL) << "]"
         << " epoch_wait_writeback["
         << pim.getEpochMismatchRejects(WriteCompletionClass::PIM_WRITEBACK) << "]"
         << " barrier_tag_park["
         << pim.getBarrierOutstandingRejects(BarrierTagClass::PARK) << "]"
         << " barrier_tag_operand_load["
         << pim.getBarrierOutstandingRejects(BarrierTagClass::OPERAND_LOAD) << "]"
         << " barrier_tag_alu["
         << pim.getBarrierOutstandingRejects(BarrierTagClass::ALU) << "]"
         << " barrier_tag_mac["
         << pim.getBarrierOutstandingRejects(BarrierTagClass::MAC) << "]"
         << " barrier_tag_output["
         << pim.getBarrierOutstandingRejects(BarrierTagClass::OUTPUT) << "]"
         << " barrier_tag_other["
         << pim.getBarrierOutstandingRejects(BarrierTagClass::OTHER) << "]"
         << " epoch_tag_park[" << pim.getEpochMismatchRejects(BarrierTagClass::PARK) << "]"
         << " epoch_tag_operand_load["
         << pim.getEpochMismatchRejects(BarrierTagClass::OPERAND_LOAD) << "]"
         << " epoch_tag_alu[" << pim.getEpochMismatchRejects(BarrierTagClass::ALU) << "]"
         << " epoch_tag_mac[" << pim.getEpochMismatchRejects(BarrierTagClass::MAC) << "]"
         << " epoch_tag_output["
         << pim.getEpochMismatchRejects(BarrierTagClass::OUTPUT) << "]"
         << " epoch_tag_other[" << pim.getEpochMismatchRejects(BarrierTagClass::OTHER) << "]"
         << " barrier_raw_tags[" << barrierRawTags << "]"
         << " epoch_raw_tags[" << epochRawTags << "]"
         << " logic_output_buffer_reservations["
         << pim.getLogicOutputBufferReservations() << "]"
         << " logic_output_buffer_retirements["
         << pim.getLogicOutputBufferRetirements() << "]"
         << " logic_output_buffer_full_stalls[" << pim.getLogicOutputBufferFullStalls() << "]"
         << " logic_output_buffer_peak_entries[" << pim.getLogicOutputBufferPeakEntries() << "]"
         << " logic_output_buffer_enabled["
         << getConfigParam(BOOL, "LOGIC_OUTPUT_BUFFER_ENABLE") << "]"
         << " logic_output_buffer_entries_setting["
         << getConfigParam(UINT, "LOGIC_OUTPUT_BUFFER_ENTRIES") << "]"
         << " logic_output_drain_latency_setting["
         << getConfigParam(UINT, "LOGIC_OUTPUT_DRAIN_LATENCY") << "]"
         << " logic_output_drain_bw_setting["
         << getConfigParam(UINT, "LOGIC_OUTPUT_DRAIN_BW") << "]"
         << " logic_output_drain_busy_cycles["
         << pim.getLogicOutputBufferDrainBusyCycles() << "]"
         << " logic_output_buffer_full_wall_cycles["
         << pim.getLogicOutputBufferFullWallCycles() << "]"
         << " add_stage_cycles[" << addEndCycle - addStartCycle << "]"
         << " relu_stage_cycles[" << reluEndCycle - reluStartCycle << "]"
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
         << " logic_release_epochs[" << pim.getLogicReleaseEpochCount() << "]"
         << " logic_release_max_streams[" << pim.getLogicReleaseMaxStreams() << "]"
         << " logic_release_complete_masks[" << pim.getLogicReleaseCompleteMasks() << "]"
         << " logic_release_incomplete_masks[" << pim.getLogicReleaseIncompleteMasks() << "]"
         << " logic_broadcast_masks[" << pim.getLogicBroadcastMaskCount() << "]"
         << " logic_broadcast_fanout[" << pim.getLogicBroadcastFanout() << "]"
         << " logic_broadcast_min_fanout[" << pim.getLogicBroadcastMinFanout() << "]"
         << " logic_broadcast_max_fanout[" << pim.getLogicBroadcastMaxFanout() << "]"
         << " logic_epoch1_masks[" << pim.getLogicEpochStats(1).maskCount << "]"
         << " logic_epoch1_fanout[" << pim.getLogicEpochStats(1).totalFanout << "]"
         << " logic_epoch1_max_residency[" << pim.getLogicEpochStats(1).maxResidencyCycles << "]"
         << " logic_epoch1_total_residency[" << pim.getLogicEpochStats(1).totalResidencyCycles << "]"
         << " logic_epoch1_peak_open_masks[" << pim.getLogicEpochStats(1).peakOpenMasks << "]"
         << " logic_epoch1_online_peak_open_masks["
         << pim.getLogicEpochStats(1).onlinePeakOpenMasks << "]"
         << " logic_epoch1_online_full_events["
         << pim.getLogicEpochStats(1).onlineQueueFullEvents << "]"
         << " logic_epoch1_incomplete_expected_masks["
         << pim.getLogicEpochStats(1).incompleteExpectedMasks << "]"
         << " logic_epoch2_masks[" << pim.getLogicEpochStats(2).maskCount << "]"
         << " logic_epoch2_fanout[" << pim.getLogicEpochStats(2).totalFanout << "]"
         << " logic_epoch2_max_residency[" << pim.getLogicEpochStats(2).maxResidencyCycles << "]"
         << " logic_epoch2_total_residency[" << pim.getLogicEpochStats(2).totalResidencyCycles << "]"
         << " logic_epoch2_peak_open_masks[" << pim.getLogicEpochStats(2).peakOpenMasks << "]"
         << " logic_epoch2_online_peak_open_masks["
         << pim.getLogicEpochStats(2).onlinePeakOpenMasks << "]"
         << " logic_epoch2_online_full_events["
         << pim.getLogicEpochStats(2).onlineQueueFullEvents << "]"
         << " logic_epoch2_incomplete_expected_masks["
         << pim.getLogicEpochStats(2).incompleteExpectedMasks << "]"
         << " logic_broadcast_queue_stall_cycles["
         << pim.getLogicBroadcastQueueStallCycles() << "]"
         << " logic_broadcast_queue_full_events["
         << pim.getLogicBroadcastQueueFullEvents() << "]"
         << " logic_broadcast_queue_applied_cycles["
         << pim.getLogicBroadcastQueueAppliedCycles() << "]"
         << " logic_broadcast_queue_last_pre_stall_cycle["
         << pim.getLogicBroadcastQueueLastPreStallCycle() << "]"
         << " logic_online_issue_blocked_channel_cycles["
         << pim.getLogicOnlineIssueStallCycles() << "]"
         << " logic_online_issue_busy_overlap_channel_cycles["
         << pim.getLogicOnlineIssueBusyOverlapCycles() << "]"
         << " logic_blocked_wall_cycles[" << pim.getLogicBlockedWallCycles() << "]"
         << " logic_blocked_streams[" << pim.getLogicBlockedStreamCount() << "]"
         << " logic_min_blocked_per_stream[" << pim.getLogicMinBlockedCyclesPerStream() << "]"
         << " logic_max_blocked_per_stream[" << pim.getLogicMaxBlockedCyclesPerStream() << "]"
         << " logic_min_issued_per_stream[" << pim.getLogicMinIssuedCommandsPerStream() << "]"
         << " logic_max_issued_per_stream[" << pim.getLogicMaxIssuedCommandsPerStream() << "]"
         << " logic_blocked_stream_mask_low[" << pim.getLogicBlockedStreamMaskLow() << "]"
         << " logic_blocked_stream_mask_high[" << pim.getLogicBlockedStreamMaskHigh() << "]"
         << " command_predicate_reject_cycles[" << pim.getCommandPredicateRejectCycles() << "]"
         << " command_predicate_hol_cycles[" << pim.getCommandPredicateHolCycles() << "]"
         << " command_predicate_hol_candidates["
         << pim.getCommandPredicateHolCandidates() << "]"
         << " command_predicate_hol_max_candidates["
         << pim.getCommandPredicateHolMaxCandidates() << "]"
         << " command_predicate_bypass_issues["
         << pim.getCommandPredicateBypassIssues() << "]"
         << " epoch_mismatch_rejects[" << pim.getEpochMismatchRejects() << "]"
         << " barrier_outstanding_rejects[" << pim.getBarrierOutstandingRejects() << "]"
         << " write_bus_busy_rejects[" << pim.getWriteBusBusyRejects() << "]"
         << " rank_command_rejects[" << pim.getRankCommandRejects() << "]"
         << " rank_mode_transition_rejects[" << pim.getRankModeTransitionRejects() << "]"
         << " rank_logic_queue_rejects[" << pim.getRankLogicQueueRejects() << "]"
         << " rank_bank_domain_rejects[" << pim.getRankBankDomainRejects() << "]"
         << " rank_logic_domain_rejects[" << pim.getRankLogicDomainRejects() << "]"
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
    cout << "COMMAND_ISSUABILITY_RESULT"
         << " rank_mode_blocked_controller_cycles["
         << pim.getRankModeBlockedControllerCycles()
         << "] rank_logic_queue_blocked_controller_cycles["
         << pim.getRankLogicQueueBlockedControllerCycles() << "]"
         << " logic_busy_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::LOGIC_PCU_BUSY)
         << "] logic_busy_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::LOGIC_PCU_BUSY)
         << "] mode_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "] mode_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "] bank_state_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::BANK_STATE)
         << "] bank_state_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::BANK_STATE)
         << "] timing_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::TIMING)
         << "] timing_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::TIMING)
         << "] row_mismatch_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] row_mismatch_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] row_limit_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT)
         << "] row_limit_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::ROW_ACCESS_LIMIT)
         << "] xaw_attempts["
         << pim.getIssuabilityRejectAttempts(CommandIssuabilityRejectReason::XAW_LIMIT)
         << "] xaw_wall_cycles["
         << pim.getIssuabilityRejectWallCycles(CommandIssuabilityRejectReason::XAW_LIMIT) << "]"
         << " bank_state_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::BANK_STATE)
         << "] timing_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::TIMING)
         << "] row_mismatch_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] mode_blocked_controller_cycles["
         << pim.getIssuabilityBlockedControllerCycles(CommandIssuabilityRejectReason::MODE_BLOCKED)
         << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
    cout << "GLOBAL_BLOCKED_RESULT"
         << " rank_mode_any_cycles[" << pim.getGlobalRankModeAnyBlockedCycles() << "]"
         << " rank_mode_all_active_cycles["
         << pim.getGlobalRankModeAllActiveBlockedCycles() << "]"
         << " rank_mode_peak_channels[" << pim.getGlobalRankModePeakBlockedChannels() << "]"
         << " bank_state_any_cycles["
         << pim.getGlobalAnyBlockedCycles(CommandIssuabilityRejectReason::BANK_STATE) << "]"
         << " bank_state_all_active_cycles["
         << pim.getGlobalAllActiveBlockedCycles(CommandIssuabilityRejectReason::BANK_STATE)
         << "] bank_state_peak_channels["
         << pim.getGlobalPeakBlockedChannels(CommandIssuabilityRejectReason::BANK_STATE) << "]"
         << " timing_any_cycles["
         << pim.getGlobalAnyBlockedCycles(CommandIssuabilityRejectReason::TIMING) << "]"
         << " timing_all_active_cycles["
         << pim.getGlobalAllActiveBlockedCycles(CommandIssuabilityRejectReason::TIMING)
         << "] timing_peak_channels["
         << pim.getGlobalPeakBlockedChannels(CommandIssuabilityRejectReason::TIMING) << "]"
         << " row_mismatch_any_cycles["
         << pim.getGlobalAnyBlockedCycles(CommandIssuabilityRejectReason::ROW_MISMATCH) << "]"
         << " row_mismatch_all_active_cycles["
         << pim.getGlobalAllActiveBlockedCycles(CommandIssuabilityRejectReason::ROW_MISMATCH)
         << "] row_mismatch_peak_channels["
         << pim.getGlobalPeakBlockedChannels(CommandIssuabilityRejectReason::ROW_MISMATCH) << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
    cout << "GLOBAL_PREDICATE_BLOCKED_RESULT"
         << " epoch_any_cycles["
         << pim.getGlobalPredicateAnyBlockedCycles(
                HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] epoch_all_active_cycles["
         << pim.getGlobalPredicateAllActiveBlockedCycles(
                HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] epoch_peak_channels["
         << pim.getGlobalPredicatePeakBlockedChannels(
                HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] barrier_any_cycles["
         << pim.getGlobalPredicateAnyBlockedCycles(
                HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] barrier_all_active_cycles["
         << pim.getGlobalPredicateAllActiveBlockedCycles(
                HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] barrier_peak_channels["
         << pim.getGlobalPredicatePeakBlockedChannels(
                HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] write_bus_any_cycles["
         << pim.getGlobalPredicateAnyBlockedCycles(
                HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] write_bus_all_active_cycles["
         << pim.getGlobalPredicateAllActiveBlockedCycles(
                HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] write_bus_peak_channels["
         << pim.getGlobalPredicatePeakBlockedChannels(
                HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] total_cycle[" << pim.getCycle() << "]" << endl;
    cout << "GLOBAL_EXCLUSIVE_BLOCKED_RESULT"
         << " hierarchy_union_any_cycles["
         << pim.getGlobalHierarchyUnionAnyBlockedCycles() << "]"
         << " hierarchy_union_all_active_cycles["
         << pim.getGlobalHierarchyUnionAllActiveBlockedCycles() << "]"
         << " hierarchy_union_peak_channels["
         << pim.getGlobalHierarchyUnionPeakBlockedChannels() << "]"
         << " bank_all_no_hierarchy_cycles["
         << pim.getGlobalBankStateAllNoHierarchyCycles() << "]"
         << " bank_all_with_hierarchy_cycles["
         << pim.getGlobalBankStateAllWithHierarchyCycles() << "]"
         << " bank_state_only_cycles[" << pim.getGlobalBankStateOnlyCycles() << "]"
         << " hierarchy_all_no_issuability_cycles["
         << pim.getGlobalHierarchyAllNoIssuabilityCycles() << "]"
         << " bank_hierarchy_all_intersection_cycles["
         << pim.getGlobalBankHierarchyAllIntersectionCycles() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
    cout << "STAGE_BLOCKED_RESULT"
         << " expand_cycles[" << expandEndCycle - expandStartCycle << "]"
         << " expand_bank_only[" << expandBankOnly << "]"
         << " expand_bank_all[" << expandBankAll << "]"
         << " expand_hierarchy_all[" << expandHierarchyAll << "]"
         << " depthwise_cycles[" << depthwiseEndCycle - depthwiseStartCycle << "]"
         << " depthwise_bank_only[" << depthwiseBankOnly << "]"
         << " depthwise_bank_all[" << depthwiseBankAll << "]"
         << " depthwise_hierarchy_all[" << depthwiseHierarchyAll << "]"
         << " project_cycles[" << projectEndCycle - projectStartCycle << "]"
         << " project_bank_only[" << projectBankOnly << "]"
         << " project_bank_all[" << projectBankAll << "]"
         << " project_hierarchy_all[" << projectHierarchyAll << "]"
         << " add_cycles[" << addEndCycle - addStartCycle << "]"
         << " add_bank_only[" << addBankOnly << "]"
         << " add_bank_all[" << addBankAll << "]"
         << " add_hierarchy_all[" << addHierarchyAll << "]"
         << " relu_cycles[" << reluEndCycle - reluStartCycle << "]"
         << " relu_bank_only[" << reluBankOnly << "]"
         << " relu_bank_all[" << reluBankAll << "]"
         << " relu_hierarchy_all[" << reluHierarchyAll << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
    cout << "POINTWISE_BANK_TAG_RESULT"
         << " expand_weight_fill[" << tagValue(expandTagAll, CommandTagClass::WEIGHT_FILL)
         << "] expand_park[" << tagValue(expandTagAll, CommandTagClass::PARK)
         << "] expand_mode[" << tagValue(expandTagAll, CommandTagClass::MODE_CONTROL)
         << "] expand_crf[" << tagValue(expandTagAll, CommandTagClass::CRF_CONTROL)
         << "] expand_input[" << tagValue(expandTagAll, CommandTagClass::INPUT_UPLOAD)
         << "] expand_mac[" << tagValue(expandTagAll, CommandTagClass::MAC)
         << "] expand_output[" << tagValue(expandTagAll, CommandTagClass::OUTPUT)
         << "] expand_other[" << tagValue(expandTagAll, CommandTagClass::OTHER)
         << "] project_weight_fill[" << tagValue(projectTagAll, CommandTagClass::WEIGHT_FILL)
         << "] project_park[" << tagValue(projectTagAll, CommandTagClass::PARK)
         << "] project_mode[" << tagValue(projectTagAll, CommandTagClass::MODE_CONTROL)
         << "] project_crf[" << tagValue(projectTagAll, CommandTagClass::CRF_CONTROL)
         << "] project_input[" << tagValue(projectTagAll, CommandTagClass::INPUT_UPLOAD)
         << "] project_mac[" << tagValue(projectTagAll, CommandTagClass::MAC)
         << "] project_output[" << tagValue(projectTagAll, CommandTagClass::OUTPUT)
         << "] project_other[" << tagValue(projectTagAll, CommandTagClass::OTHER)
         << "] total_cycle[" << pim.getCycle() << "]" << endl;
    cout << "STAGE_PREDICATE_RESULT"
         << " expand_epoch[" << predicateDelta(expandPredicateEnd, expandPredicateStart,
                                                  HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] expand_barrier["
         << predicateDelta(expandPredicateEnd, expandPredicateStart,
                           HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] expand_write_bus["
         << predicateDelta(expandPredicateEnd, expandPredicateStart,
                           HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] depthwise_epoch["
         << predicateDelta(depthwisePredicateEnd, depthwisePredicateStart,
                           HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] depthwise_barrier["
         << predicateDelta(depthwisePredicateEnd, depthwisePredicateStart,
                           HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] depthwise_write_bus["
         << predicateDelta(depthwisePredicateEnd, depthwisePredicateStart,
                           HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] project_epoch["
         << predicateDelta(projectPredicateEnd, projectPredicateStart,
                           HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] project_barrier["
         << predicateDelta(projectPredicateEnd, projectPredicateStart,
                           HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] project_write_bus["
         << predicateDelta(projectPredicateEnd, projectPredicateStart,
                           HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] add_epoch["
         << predicateDelta(addPredicateEnd, addPredicateStart,
                           HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] add_barrier["
         << predicateDelta(addPredicateEnd, addPredicateStart,
                           HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] add_write_bus["
         << predicateDelta(addPredicateEnd, addPredicateStart,
                           HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] relu_epoch["
         << predicateDelta(reluPredicateEnd, reluPredicateStart,
                           HierarchyPredicateBlockReason::EPOCH_MISMATCH)
         << "] relu_barrier["
         << predicateDelta(reluPredicateEnd, reluPredicateStart,
                           HierarchyPredicateBlockReason::BARRIER_OUTSTANDING)
         << "] relu_write_bus["
         << predicateDelta(reluPredicateEnd, reluPredicateStart,
                           HierarchyPredicateBlockReason::WRITE_BUS_BUSY)
         << "] total_cycle[" << pim.getCycle() << "]" << endl;
    cout << "BANK_STATE_RAW_TAG_RESULT tags["
         << formatRawTagCounts(pim.getBankStateBlockedCyclesByRawTag())
         << "] total_cycle[" << pim.getCycle() << "]" << endl;
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

    if (getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION"))
    {
        const uint64_t outputBursts = paddedElements / 16;
        const uint64_t aggregationTaps =
            getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS");
        EXPECT_EQ(pim.getDepthwiseAccumulatorPartialBursts(),
                  outputBursts * (9 / aggregationTaps));
        EXPECT_EQ(pim.getDepthwiseAccumulatorFinalBursts(), outputBursts);
        EXPECT_EQ(pim.getDepthwiseAccumulatorPeakEntries(), outputBursts);
        EXPECT_EQ(pim.getDepthwiseAccumulatorTransferBytes(),
                  paddedElements * 2 * (9 / aggregationTaps));
        EXPECT_GT(pim.getDepthwiseAccumulatorTransferCycles(), 0);
        EXPECT_TRUE(memory->logicDieAccumulator->empty());
    }

    cout << "DEPTHWISE_HIERARCHICAL_ACCUM_RESULT"
         << " enabled[" << getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION") << "]"
         << " aggregation_taps[" << getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS")
         << "]"
         << " bank_local_peak_entries[" << pim.getBankLocalAccumulatorPeakEntries() << "]"
         << " bank_local_peak_entries_per_bank["
         << pim.getBankLocalAccumulatorPeakEntriesPerBank() << "]"
         << " bank_local_stalls[" << pim.getBankLocalAccumulatorStalls() << "]"
         << " outputs_checked[" << reference.size() << "]"
         << " partial_bursts[" << pim.getDepthwiseAccumulatorPartialBursts() << "]"
         << " final_bursts[" << pim.getDepthwiseAccumulatorFinalBursts() << "]"
         << " peak_entries[" << pim.getDepthwiseAccumulatorPeakEntries() << "]"
         << " transfer_bytes[" << pim.getDepthwiseAccumulatorTransferBytes() << "]"
         << " transfer_cycles[" << pim.getDepthwiseAccumulatorTransferCycles() << "]"
         << " overlap_cycles[" << pim.getDepthwiseAccumulatorOverlapCycles() << "]"
         << " wait_cycles[" << pim.getDepthwiseAccumulatorWaitCycles() << "]"
         << " dram_writes[" << pim.getTotalWrites() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, DepthwiseHierarchicalAccumulatorOneChannel)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_1ch.ini", ".", "example_app",
        256 * 1 * 2);
    if (!getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION")) GTEST_SKIP();

    const vector<float> input = {1, 2, 3, 4, 5, 6, 7, 8, 9};
    const vector<float> weights(9, 1.0f);
    const auto layout =
        MobileNetV4Workload::makeDepthwiseTapLayout(input, weights, 3, 3, 1, 3, 1);
    const auto reference =
        MobileNetV4Workload::depthwiseReference(input, weights, 3, 3, 1, 3, 1);
    const uint64_t paddedElements = 1ULL * 1 * 16 * 8 * 16;
    PIMKernel pim(memory, 1, 1);
    const auto output = runDepthwiseTensor(pim, layout, paddedElements);

    ASSERT_GE(output.size(), reference.size());
    for (size_t i = 0; i < reference.size(); i++) EXPECT_FLOAT_EQ(output[i], reference[i]);
    const uint64_t outputBursts = paddedElements / 16;
    const uint64_t aggregationTaps = getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS");
    EXPECT_EQ(pim.getDepthwiseAccumulatorPartialBursts(),
              outputBursts * (9 / aggregationTaps));
    EXPECT_EQ(pim.getDepthwiseAccumulatorFinalBursts(), outputBursts);
    EXPECT_EQ(pim.getDepthwiseAccumulatorPeakEntries(), outputBursts);
    EXPECT_TRUE(memory->logicDieAccumulator->empty());

    cout << "DEPTHWISE_HIERARCHICAL_ONE_CHANNEL_RESULT"
         << " outputs_checked[" << reference.size() << "]"
         << " aggregation_taps[" << aggregationTaps << "]"
         << " partial_bursts[" << pim.getDepthwiseAccumulatorPartialBursts() << "]"
         << " final_bursts[" << pim.getDepthwiseAccumulatorFinalBursts() << "]"
         << " overlap_cycles[" << pim.getDepthwiseAccumulatorOverlapCycles() << "]"
         << " wait_cycles[" << pim.getDepthwiseAccumulatorWaitCycles() << "]"
         << " remaining_entries[" << memory->logicDieAccumulator->size() << "]"
         << " dram_writes[" << pim.getTotalWrites() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
}

TEST(MobileNetV4WorkloadTest, DepthwiseHierarchicalActualShape)
{
    constexpr uint32_t height = 14;
    constexpr uint32_t width = 14;
    constexpr uint32_t channels = 192;
    const uint64_t logicalElements =
        static_cast<uint64_t>(height) * width * channels;
    const uint64_t paddedElements = 64ULL * 1 * 16 * 8 * 16;
    const vector<float> input(logicalElements, 1.0f);
    const vector<float> weights(3 * 3 * channels, 1.0f);
    const auto layout = MobileNetV4Workload::makeDepthwiseTapLayout(
        input, weights, height, width, channels, 3, 1);

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    if (!getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION")) GTEST_SKIP();
    PIMKernel pim(memory, 64, 1);
    const auto output = runDepthwiseTensor(pim, layout, paddedElements);

    uint64_t mismatches = 0;
    uint64_t firstIndex = 0;
    float firstExpected = 0;
    float firstActual = 0;
    for (uint32_t y = 0; y < height; y++)
        for (uint32_t x = 0; x < width; x++)
        {
            const bool topOrBottom = y == 0 || y == height - 1;
            const bool leftOrRight = x == 0 || x == width - 1;
            const float expected = (topOrBottom && leftOrRight)
                                       ? 4.0f
                                       : ((topOrBottom || leftOrRight) ? 6.0f : 9.0f);
            for (uint32_t channel = 0; channel < channels; channel++)
            {
                const uint64_t index =
                    (static_cast<uint64_t>(y) * width + x) * channels + channel;
                const float actual = output[index];
                if (actual != expected)
                {
                    if (mismatches == 0)
                    {
                        firstIndex = index;
                        firstExpected = expected;
                        firstActual = actual;
                    }
                    mismatches++;
                }
            }
        }

    const auto linkReplay = pim.getDepthwiseLinkReplayStats();
    pim.writeDepthwiseAccumulatorTrace(
        getConfigParam(STRING, "LOGIC_ACCUMULATOR_TRACE_FILE"));
    cout << "DEPTHWISE_HIERARCHICAL_ACTUAL_SHAPE_RESULT"
         << " outputs_checked[" << logicalElements << "]"
         << " aggregation_taps[" << getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS")
         << "]"
         << " bank_local_peak_entries[" << pim.getBankLocalAccumulatorPeakEntries() << "]"
         << " bank_local_peak_entries_per_bank["
         << pim.getBankLocalAccumulatorPeakEntriesPerBank() << "]"
         << " bank_local_stalls[" << pim.getBankLocalAccumulatorStalls() << "]"
         << " mismatches[" << mismatches << "]"
         << " first_index[" << firstIndex << "]"
         << " first_y[" << firstIndex / (width * channels) << "]"
         << " first_x[" << (firstIndex / channels) % width << "]"
         << " first_channel[" << firstIndex % channels << "]"
         << " first_expected[" << firstExpected << "]"
         << " first_actual[" << firstActual << "]"
         << " partial_bursts[" << pim.getDepthwiseAccumulatorPartialBursts() << "]"
         << " final_bursts[" << pim.getDepthwiseAccumulatorFinalBursts() << "]"
         << " overlap_cycles[" << pim.getDepthwiseAccumulatorOverlapCycles() << "]"
         << " wait_cycles[" << pim.getDepthwiseAccumulatorWaitCycles() << "]"
         << " link_replay_bursts[" << linkReplay.bursts << "]"
         << " link_replay_cycles[" << linkReplay.replayCycles << "]"
         << " link_replay_full_cycles[" << linkReplay.fullCycles << "]"
         << " link_replay_partial_cycles[" << linkReplay.partialCycles << "]"
         << " link_replay_idle_cycles[" << linkReplay.idleCycles << "]"
         << " link_replay_completion_cycle[" << linkReplay.completionCycle << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
    EXPECT_EQ(mismatches, 0u);
}

TEST(MobileNetV4WorkloadTest, DepthwiseHierarchicalExpandedShape)
{
    constexpr uint32_t height = 28;
    constexpr uint32_t width = 28;
    constexpr uint32_t channels = 192;
    const uint64_t logicalElements =
        static_cast<uint64_t>(height) * width * channels;
    const uint64_t paddedElements = 64ULL * 2 * 16 * 8 * 16;
    const vector<float> input(logicalElements, 1.0f);
    const vector<float> weights(3 * 3 * channels, 1.0f);
    const auto layout = MobileNetV4Workload::makeDepthwiseTapLayout(
        input, weights, height, width, channels, 3, 1);

    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_64ch.ini", ".", "example_app",
        256 * 64 * 2);
    if (!getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION")) GTEST_SKIP();
    PIMKernel pim(memory, 64, 1);
    const auto output = runDepthwiseTensor(pim, layout, paddedElements);

    uint64_t mismatches = 0;
    for (uint32_t y = 0; y < height; y++)
        for (uint32_t x = 0; x < width; x++)
        {
            const bool topOrBottom = y == 0 || y == height - 1;
            const bool leftOrRight = x == 0 || x == width - 1;
            const float expected = (topOrBottom && leftOrRight)
                                       ? 4.0f
                                       : ((topOrBottom || leftOrRight) ? 6.0f : 9.0f);
            for (uint32_t channel = 0; channel < channels; channel++)
            {
                const uint64_t index =
                    (static_cast<uint64_t>(y) * width + x) * channels + channel;
                if (output[index] != expected) mismatches++;
            }
        }

    cout << "DEPTHWISE_HIERARCHICAL_EXPANDED_SHAPE_RESULT"
         << " outputs_checked[" << logicalElements << "]"
         << " padded_elements[" << paddedElements << "]"
         << " aggregation_taps[" << getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS")
         << "]"
         << " accumulator_banks[" << getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_BANKS")
         << "]"
         << " tile_batch["
         << getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_TILE_BATCH") << "]"
         << " bank_local_peak_entries[" << pim.getBankLocalAccumulatorPeakEntries() << "]"
         << " bank_local_peak_entries_per_bank["
         << pim.getBankLocalAccumulatorPeakEntriesPerBank() << "]"
         << " bank_local_stalls[" << pim.getBankLocalAccumulatorStalls() << "]"
         << " mismatches[" << mismatches << "]"
         << " partial_bursts[" << pim.getDepthwiseAccumulatorPartialBursts() << "]"
         << " final_bursts[" << pim.getDepthwiseAccumulatorFinalBursts() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
    EXPECT_EQ(mismatches, 0u);
    const uint64_t entriesPerTile = 16 * 8;
    const uint64_t numTiles = paddedElements / (64 * 16 * 8 * 16);
    const uint64_t configuredTileBatch =
        getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_TILE_BATCH");
    const uint64_t liveTiles = configuredTileBatch == 0
                                   ? numTiles
                                   : min(configuredTileBatch, numTiles);
    EXPECT_EQ(pim.getBankLocalAccumulatorPeakEntries(), liveTiles * entriesPerTile);
}

TEST(MobileNetV4WorkloadTest, DepthwiseHierarchicalRandomFp16Rounding)
{
    auto memory = make_shared<MultiChannelMemorySystem>(
        "ini/HBM2_samsung_2M_16B_x64.ini", "system_hbm_1ch.ini", ".", "example_app",
        256 * 1 * 2);
    if (!getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION")) GTEST_SKIP();

    constexpr uint32_t height = 4;
    constexpr uint32_t width = 4;
    constexpr uint32_t channels = 8;
    const uint64_t logicalElements =
        static_cast<uint64_t>(height) * width * channels;
    vector<float> input(logicalElements);
    vector<float> weights(3 * 3 * channels);
    for (uint64_t i = 0; i < input.size(); i++)
        input[i] = static_cast<float>((static_cast<int>(i * 37 % 29) - 14)) / 7.0f;
    for (uint64_t i = 0; i < weights.size(); i++)
        weights[i] = static_cast<float>((static_cast<int>(i * 19 % 23) - 11)) / 9.0f;

    const auto layout = MobileNetV4Workload::makeDepthwiseTapLayout(
        input, weights, height, width, channels, 3, 1);
    const uint64_t paddedElements = 1ULL * 1 * 16 * 8 * 16;
    PIMKernel pim(memory, 1, 1);
    const auto output = runDepthwiseTensor(pim, layout, paddedElements);
    const unsigned aggregationTaps =
        getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS");

    uint64_t mismatches = 0;
    float maxFp32Error = 0;
    for (uint64_t index = 0; index < logicalElements; index++)
    {
        fp16 accumulated(0.0f);
        float fp32Reference = 0;
        for (unsigned group = 0; group < 9; group += aggregationTaps)
        {
            fp16 local(0.0f);
            for (unsigned tap = group; tap < group + aggregationTaps; tap++)
            {
                const fp16 inputValue(layout.inputTapPlanes[tap][index]);
                const fp16 weightValue(layout.weightTapPlanes[tap][index]);
                local = local + inputValue * weightValue;
                fp32Reference += layout.inputTapPlanes[tap][index] *
                                 layout.weightTapPlanes[tap][index];
            }
            accumulated = accumulated + local;
        }
        const float actual = output[index];
        if (actual != static_cast<float>(accumulated)) mismatches++;
        maxFp32Error = max(maxFp32Error, abs(actual - fp32Reference));
    }

    cout << "DEPTHWISE_FP16_ROUNDING_RESULT"
         << " aggregation_taps[" << aggregationTaps << "]"
         << " outputs_checked[" << logicalElements << "]"
         << " mismatches[" << mismatches << "]"
         << " max_fp32_error[" << maxFp32Error << "]"
         << " partial_bursts[" << pim.getDepthwiseAccumulatorPartialBursts() << "]"
         << " total_cycle[" << pim.getCycle() << "]" << endl;
    EXPECT_EQ(mismatches, 0u);
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
