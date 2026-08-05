/***************************************************************************************************
 * Copyright (C) 2021 Samsung Electronics Co. LTD
 *
 * This software is a property of Samsung Electronics.
 * No part of this software, either material or conceptual may be copied or distributed,
 * transmitted, transcribed, stored in a retrieval system, or translated into any human
 * or computer language in any form by any means,electronic, mechanical, manual or otherwise,
 * or disclosed to third parties without the express written permission of Samsung Electronics.
 * (Use of the Software is restricted to non-commercial, personal or academic, research purpose
 * only)
 **************************************************************************************************/

#include "tests/PIMKernel.h"

#include <iomanip>
#include <deque>
#include <fstream>
#include <string>
#include <stdexcept>

#include "AddressMapping.h"
#include "tests/PIMCmdGen.h"

bool PIMKernel::usesBankSidePIM() const
{
    bool enabled = getConfigParam(BOOL, "ENABLE_BANK_SIDE_PIM");
    if (!enabled)
        return false;
    return target_ == PIMTarget::BANK_SIDE || target_ == PIMTarget::HYBRID;
}

bool PIMKernel::usesLogicDiePIM() const
{
    bool enabled = getConfigParam(BOOL, "ENABLE_LOGIC_DIE_PIM");
    if (!enabled)
        return false;
    return target_ == PIMTarget::LOGIC_DIE || target_ == PIMTarget::HYBRID;
}

void PIMKernel::executeLogicDieStub(const std::string& op_name)
{
    cout << ">> logic-die stub triggered: op=" << op_name << " target=";
    switch (target_)
    {
        case PIMTarget::BANK_SIDE:
            cout << "bank_side";
            break;
        case PIMTarget::LOGIC_DIE:
            cout << "logic_die";
            break;
        case PIMTarget::HOST:
            cout << "host";
            break;
        case PIMTarget::HYBRID:
            cout << "hybrid";
            break;
    }
    cout << endl;
    throw runtime_error("logic-die " + op_name + " path is not implemented yet");
}

void PIMKernel::runPIM()
{
    uint64_t local_cycles = 0;
    const uint64_t watchdogCycles = getConfigParam(UINT64, "PIM_RUN_WATCHDOG_CYCLES");
    const uint64_t reportInterval = watchdogCycles == 0 ? 1000000 : min<uint64_t>(10000, watchdogCycles);
    while (mem_->hasPendingTransactions())
    {
        cycle_++;
        local_cycles++;
        mem_->update();
        if ((DEBUG_CMD_TRACE || getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES") ||
             watchdogCycles != 0) && local_cycles % reportInterval == 0)
        {
            cout << "PIM_RUN_STALL cycle[" << cycle_ << "] pending["
                 << mem_->hasPendingTransactions() << "] global_busy_until["
                 << mem_->logicDieScheduler->getBusyUntil() << "]";
            for (unsigned channel = 0; channel < mem_->channels.size(); channel++)
            {
                auto* memory_system = mem_->channels[channel];
                if (memory_system->numOnTheFlyTransactions == 0) continue;
                auto* rank = memory_system->ranks->front();
                cout << " ch" << channel << "_onfly["
                     << memory_system->numOnTheFlyTransactions << "]"
                     << "_pending[" << memory_system->pendingTransactions.size() << "]"
                     << "_mcq["
                     << memory_system->memoryController->transactionQueue.size() << "]"
                     << "_returns[" << rank->readReturnCountdown.size() << "]";
                if (!rank->readReturnCountdown.empty())
                    cout << "_front[" << rank->readReturnCountdown.front() << "]";
                cout << "_bus[" << (rank->outgoingDataPacket != nullptr) << "]";
                cout << "_mode[" << static_cast<int>(rank->mode_) << "]"
                     << "_logic_mode[" << static_cast<int>(rank->logicMode_) << "]"
                     << "_mode_ready[" << rank->modeReadyCycle_ << "]"
                     << "_logic_ready[" << rank->logicModeReadyCycle_ << "]";
                cout << memory_system->memoryController->getCommandQueueDebugSummary();
            }
            cout << endl;
        }
        if (watchdogCycles != 0 && local_cycles >= watchdogCycles)
            throw runtime_error("PIM run watchdog reached while transactions remain pending");
    }
}

uint64_t PIMKernel::getCycle()
{
    return cycle_;
}

uint64_t PIMKernel::accountHierarchyTransfer(uint64_t bytes, uint64_t bytes_per_cycle)
{
    if (bytes == 0) return 0;
    const uint64_t transfer_cycles =
        bytes_per_cycle == 0 ? 0 : (bytes + bytes_per_cycle - 1) / bytes_per_cycle;
    hierarchyTransferCount_++;
    hierarchyTransferBytes_ += bytes;
    hierarchyTransferCycles_ += transfer_cycles;
    for (uint64_t i = 0; i < transfer_cycles; i++)
    {
        cycle_++;
        mem_->update();
    }
    return transfer_cycles;
}

uint64_t PIMKernel::getHierarchyTransferCount() const { return hierarchyTransferCount_; }
uint64_t PIMKernel::getHierarchyTransferBytes() const { return hierarchyTransferBytes_; }
uint64_t PIMKernel::getHierarchyTransferCycles() const { return hierarchyTransferCycles_; }
uint64_t PIMKernel::getDepthwiseAccumulatorTransferBytes() const
{
    return depthwiseAccumulatorTransferBytes_;
}
uint64_t PIMKernel::getDepthwiseAccumulatorTransferCycles() const
{
    return depthwiseAccumulatorTransferCycles_;
}
uint64_t PIMKernel::getDepthwiseAccumulatorOverlapCycles() const
{
    return depthwiseAccumulatorOverlapCycles_;
}
uint64_t PIMKernel::getDepthwiseAccumulatorWaitCycles() const
{
    return depthwiseAccumulatorWaitCycles_;
}
uint64_t PIMKernel::getDepthwiseAccumulatorPartialBursts() const
{
    return mem_->logicDieAccumulator->partialBursts();
}
uint64_t PIMKernel::getDepthwiseAccumulatorFinalBursts() const
{
    return mem_->logicDieAccumulator->finalizedBursts();
}
uint64_t PIMKernel::getDepthwiseAccumulatorPeakEntries() const
{
    return mem_->logicDieAccumulator->peakEntries();
}
uint64_t PIMKernel::getBankLocalAccumulatorStalls() const
{
    uint64_t total = 0;
    for (const MemorySystem* channel : mem_->channels)
        for (const Rank* rank : *channel->ranks)
            total += rank->pimRank->getBankLocalAccumulatorStalls();
    return total;
}
uint64_t PIMKernel::getBankLocalAccumulatorPeakEntries() const
{
    uint64_t peak = 0;
    for (const MemorySystem* channel : mem_->channels)
        for (const Rank* rank : *channel->ranks)
            peak = max(peak, rank->pimRank->getBankLocalAccumulatorPeakEntries());
    return peak;
}
uint64_t PIMKernel::getBankLocalAccumulatorPeakEntriesPerBank() const
{
    uint64_t peak = 0;
    for (const MemorySystem* channel : mem_->channels)
        for (const Rank* rank : *channel->ranks)
            peak = max(peak, rank->pimRank->getBankLocalAccumulatorPeakEntriesPerBank());
    return peak;
}
DRAMSim::LogicDieAccumulator::LinkReplayStats PIMKernel::getDepthwiseLinkReplayStats() const
{
    return mem_->logicDieAccumulator->replayTwoStageLink(num_pim_chans_, 2);
}
void PIMKernel::writeDepthwiseAccumulatorTrace(const std::string& path) const
{
    if (path.empty() || path == "none") return;
    std::ofstream output(path);
    if (!output) throw std::runtime_error("Unable to open accumulator trace: " + path);
    output << "sequence,cycle,channel,rank,pim_block,key\n";
    uint64_t sequence = 0;
    for (const auto& event : mem_->logicDieAccumulator->arrivalEvents())
        output << sequence++ << ',' << event.cycle << ',' << event.channel << ',' << event.rank
               << ',' << event.pimBlock << ',' << event.key << '\n';

    std::ofstream payload(path + ".payload.csv");
    if (!payload)
        throw std::runtime_error("Unable to open accumulator payload trace: " + path);
    payload << "sequence,cycle,channel,rank,pim_block,key,tap_index,tap_count,partial_hex,final_hex\n";
    sequence = 0;
    const auto writeBurst = [](std::ostream& stream, const BurstType& burst) {
        const auto oldFlags = stream.flags();
        const auto oldFill = stream.fill();
        stream << std::hex << std::setfill('0');
        for (int lane = 15; lane >= 0; --lane)
            stream << std::setw(4) << burst.u16Data_[lane];
        stream.flags(oldFlags);
        stream.fill(oldFill);
    };
    for (const auto& event : mem_->logicDieAccumulator->arrivalEvents())
    {
        payload << sequence++ << ',' << event.cycle << ',' << event.channel << ',' << event.rank
                << ',' << event.pimBlock << ',' << event.key << ',' << event.tapIndex << ','
                << mem_->logicDieAccumulator->expectedTaps() << ',';
        writeBurst(payload, event.partial);
        payload << ',';
        writeBurst(payload, mem_->logicDieAccumulator->finalizedResult(event.key));
        payload << '\n';
    }
}
unsigned PIMKernel::getLastPointwiseActiveChannels() const
{
    return lastPointwiseActiveChannels_;
}
unsigned PIMKernel::getLastPointwisePhysicalOutputDim() const
{
    return lastPointwisePhysicalOutputDim_;
}
unsigned PIMKernel::getLastPointwiseSpatialGroups() const
{
    return lastPointwiseSpatialGroups_;
}
unsigned PIMKernel::getLastPointwiseBatchWaves() const { return lastPointwiseBatchWaves_; }
uint64_t PIMKernel::getLogicHabEntries() const { return logicHabEntries_; }
uint64_t PIMKernel::getLogicHabExits() const { return logicHabExits_; }
uint64_t PIMKernel::getTotalReads() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->totalReads;
    return total;
}
uint64_t PIMKernel::getTotalWrites() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->totalWrites;
    return total;
}
uint64_t PIMKernel::getGlobalLogicCommandCount() const
{
    return mem_->logicDieScheduler->getCommandCount();
}
uint64_t PIMKernel::getGlobalLogicQueueCycles() const
{
    return mem_->logicDieScheduler->getQueueCycles();
}
uint64_t PIMKernel::getGlobalLogicServiceCycles() const
{
    return mem_->logicDieScheduler->getServiceCycles();
}
uint64_t PIMKernel::getGlobalLogicBusyUntil() const
{
    return mem_->logicDieScheduler->getBusyUntil();
}
uint64_t PIMKernel::getGlobalLogicDispatchCount() const
{
    return mem_->logicDieScheduler->getDispatchCount();
}
uint64_t PIMKernel::getGlobalLogicCoalescedCommandCount() const
{
    return mem_->logicDieScheduler->getCoalescedCommandCount();
}
uint64_t PIMKernel::getGlobalLogicDispatchOverheadCycles() const
{
    return mem_->logicDieScheduler->getDispatchOverheadCycles();
}

void PIMKernel::resetHierarchyActivity()
{
    mem_->logicDieScheduler->resetHierarchyActivity();
}

HierarchyActivityStats PIMKernel::getHierarchyActivityStats() const
{
    return mem_->logicDieScheduler->getHierarchyActivityStats();
}
uint64_t PIMKernel::getLogicReleaseEpochCount() const
{
    return mem_->logicDieScheduler->getReleaseEpochCount();
}
uint64_t PIMKernel::getLogicReleaseMaxStreams() const
{
    return mem_->logicDieScheduler->getMaxReleaseStreams();
}
uint64_t PIMKernel::getLogicReleaseCompleteMasks() const
{
    return mem_->logicDieScheduler->getCompletedReadyMasks();
}
uint64_t PIMKernel::getLogicReleaseIncompleteMasks() const
{
    return mem_->logicDieScheduler->getIncompleteReadyMasks();
}
uint64_t PIMKernel::getLogicBroadcastMaskCount() const
{
    return mem_->logicDieScheduler->getBroadcastMaskCount();
}
uint64_t PIMKernel::getLogicBroadcastFanout() const
{
    return mem_->logicDieScheduler->getBroadcastFanout();
}
uint64_t PIMKernel::getLogicBroadcastMinFanout() const
{
    return mem_->logicDieScheduler->getMinBroadcastFanout();
}
uint64_t PIMKernel::getLogicBroadcastMaxFanout() const
{
    return mem_->logicDieScheduler->getMaxBroadcastFanout();
}
LogicEpochStats PIMKernel::getLogicEpochStats(uint64_t epochId) const
{
    return mem_->logicDieScheduler->getEpochStats(epochId);
}
uint64_t PIMKernel::getLogicBroadcastQueueStallCycles() const
{
    return mem_->logicDieScheduler->getBroadcastQueueStallCycles();
}
uint64_t PIMKernel::getLogicBroadcastQueueFullEvents() const
{
    return mem_->logicDieScheduler->getBroadcastQueueFullEvents();
}
uint64_t PIMKernel::getLogicBroadcastQueueAppliedCycles() const
{
    return logicBroadcastQueueAppliedCycles_;
}
uint64_t PIMKernel::getLogicBroadcastQueueLastPreStallCycle() const
{
    return logicBroadcastQueueLastPreStallCycle_;
}
uint64_t PIMKernel::getLogicOnlineIssueStallCycles() const
{
    return mem_->logicDieScheduler->getOnlineIssueStallCycles();
}
uint64_t PIMKernel::getLogicOnlineIssueBusyOverlapCycles() const
{
    return mem_->logicDieScheduler->getOnlineIssueBusyOverlapCycles();
}
uint64_t PIMKernel::getLogicBlockedWallCycles() const
{
    return mem_->logicDieScheduler->getBlockedWallCycles();
}
uint64_t PIMKernel::getLogicBlockedStreamCount() const
{
    return mem_->logicDieScheduler->getBlockedStreamCount();
}
uint64_t PIMKernel::getLogicMinBlockedCyclesPerStream() const
{
    return mem_->logicDieScheduler->getMinBlockedCyclesPerStream();
}
uint64_t PIMKernel::getLogicMaxBlockedCyclesPerStream() const
{
    return mem_->logicDieScheduler->getMaxBlockedCyclesPerStream();
}
uint64_t PIMKernel::getLogicMinIssuedCommandsPerStream() const
{
    return mem_->logicDieScheduler->getMinIssuedCommandsPerStream();
}
uint64_t PIMKernel::getLogicMaxIssuedCommandsPerStream() const
{
    return mem_->logicDieScheduler->getMaxIssuedCommandsPerStream();
}
uint64_t PIMKernel::getLogicBlockedStreamMaskLow() const
{
    return mem_->logicDieScheduler->getBlockedStreamMaskLow();
}
uint64_t PIMKernel::getLogicBlockedStreamMaskHigh() const
{
    return mem_->logicDieScheduler->getBlockedStreamMaskHigh();
}
uint64_t PIMKernel::getCommandPredicateRejectCycles() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->getCommandPredicateRejectCycles();
    return total;
}
uint64_t PIMKernel::getCommandPredicateHolCycles() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->getCommandPredicateHolCycles();
    return total;
}
uint64_t PIMKernel::getCommandPredicateHolCandidates() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->getCommandPredicateHolCandidates();
    return total;
}
uint64_t PIMKernel::getCommandPredicateHolMaxCandidates() const
{
    uint64_t maximum = 0;
    for (const auto& channel : mem_->channels)
        maximum = max(maximum,
                      channel->memoryController->getCommandPredicateHolMaxCandidates());
    return maximum;
}
uint64_t PIMKernel::getCommandPredicateBypassIssues() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->getCommandPredicateBypassIssues();
    return total;
}
uint64_t PIMKernel::getIssuabilityRejectAttempts(
    CommandIssuabilityRejectReason reason) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getIssuabilityRejectAttempts(reason);
    return total;
}
uint64_t PIMKernel::getIssuabilityRejectWallCycles(
    CommandIssuabilityRejectReason reason) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getIssuabilityRejectWallCycles(reason);
    return total;
}
uint64_t PIMKernel::getIssuabilityBlockedControllerCycles(
    CommandIssuabilityRejectReason reason) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getIssuabilityBlockedControllerCycles(reason);
    return total;
}
uint64_t PIMKernel::getGlobalAnyBlockedCycles(CommandIssuabilityRejectReason reason) const
{
    return mem_->getGlobalAnyBlockedCycles(reason);
}
uint64_t PIMKernel::getGlobalAllActiveBlockedCycles(
    CommandIssuabilityRejectReason reason) const
{
    return mem_->getGlobalAllActiveBlockedCycles(reason);
}
uint64_t PIMKernel::getGlobalPeakBlockedChannels(
    CommandIssuabilityRejectReason reason) const
{
    return mem_->getGlobalPeakBlockedChannels(reason);
}
uint64_t PIMKernel::getGlobalRankModeAnyBlockedCycles() const
{
    return mem_->getGlobalRankModeAnyBlockedCycles();
}
uint64_t PIMKernel::getGlobalRankModeAllActiveBlockedCycles() const
{
    return mem_->getGlobalRankModeAllActiveBlockedCycles();
}
uint64_t PIMKernel::getGlobalRankModePeakBlockedChannels() const
{
    return mem_->getGlobalRankModePeakBlockedChannels();
}
uint64_t PIMKernel::getGlobalPredicateAnyBlockedCycles(
    HierarchyPredicateBlockReason reason) const
{
    return mem_->getGlobalPredicateAnyBlockedCycles(reason);
}
uint64_t PIMKernel::getGlobalPredicateAllActiveBlockedCycles(
    HierarchyPredicateBlockReason reason) const
{
    return mem_->getGlobalPredicateAllActiveBlockedCycles(reason);
}
uint64_t PIMKernel::getGlobalPredicatePeakBlockedChannels(
    HierarchyPredicateBlockReason reason) const
{
    return mem_->getGlobalPredicatePeakBlockedChannels(reason);
}
uint64_t PIMKernel::getGlobalHierarchyUnionAnyBlockedCycles() const
{
    return mem_->getGlobalHierarchyUnionAnyBlockedCycles();
}
uint64_t PIMKernel::getGlobalHierarchyUnionAllActiveBlockedCycles() const
{
    return mem_->getGlobalHierarchyUnionAllActiveBlockedCycles();
}
uint64_t PIMKernel::getGlobalHierarchyUnionPeakBlockedChannels() const
{
    return mem_->getGlobalHierarchyUnionPeakBlockedChannels();
}
uint64_t PIMKernel::getGlobalBankStateAllNoHierarchyCycles() const
{
    return mem_->getGlobalBankStateAllNoHierarchyCycles();
}
uint64_t PIMKernel::getGlobalBankStateAllWithHierarchyCycles() const
{
    return mem_->getGlobalBankStateAllWithHierarchyCycles();
}
uint64_t PIMKernel::getGlobalBankStateOnlyCycles() const
{
    return mem_->getGlobalBankStateOnlyCycles();
}
uint64_t PIMKernel::getGlobalHierarchyAllNoIssuabilityCycles() const
{
    return mem_->getGlobalHierarchyAllNoIssuabilityCycles();
}
uint64_t PIMKernel::getGlobalBankHierarchyAllIntersectionCycles() const
{
    return mem_->getGlobalBankHierarchyAllIntersectionCycles();
}
uint64_t PIMKernel::getGlobalBankTagAnyBlockedCycles(CommandTagClass tagClass) const
{
    return mem_->getGlobalBankTagAnyBlockedCycles(tagClass);
}
uint64_t PIMKernel::getGlobalBankTagAllActiveBlockedCycles(CommandTagClass tagClass) const
{
    return mem_->getGlobalBankTagAllActiveBlockedCycles(tagClass);
}
uint64_t PIMKernel::getGlobalBankTagPeakBlockedChannels(CommandTagClass tagClass) const
{
    return mem_->getGlobalBankTagPeakBlockedChannels(tagClass);
}
map<string, uint64_t> PIMKernel::getBankStateBlockedCyclesByRawTag() const
{
    map<string, uint64_t> total;
    for (const auto* channel : mem_->channels)
        for (const auto& entry :
             channel->memoryController->getBankStateBlockedCyclesByRawTag())
            total[entry.first] += entry.second;
    return total;
}

uint64_t PIMKernel::getEpochMismatchRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getEpochMismatchRejects();
    return total;
}

uint64_t PIMKernel::getBarrierOutstandingRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getBarrierOutstandingRejects();
    return total;
}

uint64_t PIMKernel::getWriteBusBusyRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getWriteBusBusyRejects();
    return total;
}

uint64_t PIMKernel::getRankCommandRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getRankCommandRejects();
    return total;
}
uint64_t PIMKernel::getRankModeTransitionRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getRankModeTransitionRejects();
    return total;
}
uint64_t PIMKernel::getRankLogicQueueRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getRankLogicQueueRejects();
    return total;
}
uint64_t PIMKernel::getRankBankDomainRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getRankBankDomainRejects();
    return total;
}
uint64_t PIMKernel::getRankLogicDomainRejects() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getRankLogicDomainRejects();
    return total;
}
uint64_t PIMKernel::getRankModeBlockedControllerCycles() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getRankModeBlockedControllerCycles();
    return total;
}
uint64_t PIMKernel::getRankLogicQueueBlockedControllerCycles() const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getRankLogicQueueBlockedControllerCycles();
    return total;
}
uint64_t PIMKernel::getWriteDataCompletions(WriteCompletionClass completionClass) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getWriteDataCompletions(completionClass);
    return total;
}
uint64_t PIMKernel::getWriteBarrierCompletions(WriteCompletionClass completionClass) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getWriteBarrierCompletions(completionClass);
    return total;
}
uint64_t PIMKernel::getBarrierOutstandingRejects(
    WriteCompletionClass completionClass) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getBarrierOutstandingRejects(completionClass);
    return total;
}
uint64_t PIMKernel::getEpochMismatchRejects(WriteCompletionClass completionClass) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getEpochMismatchRejects(completionClass);
    return total;
}
uint64_t PIMKernel::getBarrierOutstandingRejects(BarrierTagClass tagClass) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getBarrierOutstandingRejects(tagClass);
    return total;
}
uint64_t PIMKernel::getEpochMismatchRejects(BarrierTagClass tagClass) const
{
    uint64_t total = 0;
    for (const auto* channel : mem_->channels)
        total += channel->memoryController->getEpochMismatchRejects(tagClass);
    return total;
}
map<string, uint64_t> PIMKernel::getBarrierOutstandingRejectsByRawTag() const
{
    map<string, uint64_t> totals;
    for (const auto* channel : mem_->channels)
        for (const auto& entry :
             channel->memoryController->getBarrierOutstandingRejectsByRawTag())
            totals[entry.first] += entry.second;
    return totals;
}
map<string, uint64_t> PIMKernel::getEpochMismatchRejectsByRawTag() const
{
    map<string, uint64_t> totals;
    for (const auto* channel : mem_->channels)
        for (const auto& entry : channel->memoryController->getEpochMismatchRejectsByRawTag())
            totals[entry.first] += entry.second;
    return totals;
}
uint64_t PIMKernel::getLogicOutputBufferReservations() const
{
    return mem_->logicDieOutputBuffer->getReservations();
}
uint64_t PIMKernel::getLogicOutputBufferRetirements() const
{
    return mem_->logicDieOutputBuffer->getRetirements();
}
uint64_t PIMKernel::getLogicOutputBufferFullStalls() const
{
    return mem_->logicDieOutputBuffer->getFullStalls();
}
uint64_t PIMKernel::getLogicOutputBufferPeakEntries() const
{
    return mem_->logicDieOutputBuffer->getPeakEntries();
}
uint64_t PIMKernel::getLogicOutputBufferDrainBusyCycles() const
{
    return mem_->logicDieOutputBuffer->getDrainBusyCycles();
}
uint64_t PIMKernel::getLogicOutputBufferFullWallCycles() const
{
    return mem_->logicDieOutputBuffer->getFullWallCycles();
}
uint64_t PIMKernel::getBaselineLogicWeightBytes() const { return baselineLogicWeightBytes_; }
uint64_t PIMKernel::getPhysicalLogicWeightBytes() const { return physicalLogicWeightBytes_; }
uint64_t PIMKernel::getModeledLogicWeightBytes() const { return modeledLogicWeightBytes_; }
uint64_t PIMKernel::getSavedLogicWeightBytes() const { return savedLogicWeightBytes_; }
uint64_t PIMKernel::getModeledTotalWrites() const
{
    return getTotalWrites();
}
uint64_t PIMKernel::getLogicWeightBufferFillBursts() const
{
    return mem_->logicDieWeightBuffer->getFillBursts();
}
uint64_t PIMKernel::getLogicWeightBufferReadHits() const
{
    return mem_->logicDieWeightBuffer->getReadHits();
}
uint64_t PIMKernel::getLogicWeightBufferReadMisses() const
{
    return mem_->logicDieWeightBuffer->getReadMisses();
}
uint64_t PIMKernel::getLogicWeightFillActiveChannels() const
{
    uint64_t active = 0;
    for (const auto& channel : mem_->channels)
        if (channel->memoryController->logicWeightFillCompletedWrites > 0) active++;
    return active;
}
uint64_t PIMKernel::getLogicWeightFillCompletedWrites() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->logicWeightFillCompletedWrites;
    return total;
}
uint64_t PIMKernel::getLogicWeightFillMinWritesPerChannel() const
{
    uint64_t minimum = numeric_limits<uint64_t>::max();
    for (const auto& channel : mem_->channels)
    {
        const uint64_t writes = channel->memoryController->logicWeightFillCompletedWrites;
        if (writes > 0) minimum = min(minimum, writes);
    }
    return minimum == numeric_limits<uint64_t>::max() ? 0 : minimum;
}
uint64_t PIMKernel::getLogicWeightFillMaxWritesPerChannel() const
{
    uint64_t maximum = 0;
    for (const auto& channel : mem_->channels)
        maximum = max(maximum, channel->memoryController->logicWeightFillCompletedWrites);
    return maximum;
}
uint64_t PIMKernel::getLogicWeightFillMinCompletionCycle() const
{
    uint64_t minimum = numeric_limits<uint64_t>::max();
    for (const auto& channel : mem_->channels)
    {
        const uint64_t cycle = channel->memoryController->logicWeightFillLastCompletionCycle;
        if (cycle > 0) minimum = min(minimum, cycle);
    }
    return minimum == numeric_limits<uint64_t>::max() ? 0 : minimum;
}
uint64_t PIMKernel::getLogicWeightFillMaxCompletionCycle() const
{
    uint64_t maximum = 0;
    for (const auto& channel : mem_->channels)
        maximum = max(maximum, channel->memoryController->logicWeightFillLastCompletionCycle);
    return maximum;
}
uint64_t PIMKernel::getLogicWeightFillActivates() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->logicWeightFillActivates;
    return total;
}
uint64_t PIMKernel::getLogicWeightFillPrecharges() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->logicWeightFillPrecharges;
    return total;
}
uint64_t PIMKernel::getLogicWeightFillBarrierCycles() const
{
    return logicWeightFillBarrierCycles_;
}
uint64_t PIMKernel::getLogicWeightBufferPortWaitCycles() const
{
    return logicWeightBufferPortWaitCycles_;
}
uint64_t PIMKernel::getLogicPostFillGuardCycles() const
{
    return logicPostFillGuardCycles_;
}
uint64_t PIMKernel::getLogicWeightBufferWriteQueueCycles() const
{
    return mem_->logicDieWeightBuffer->getWriteQueueCycles();
}
uint64_t PIMKernel::getTotalRefreshes() const
{
    uint64_t total = 0;
    for (const auto& channel : mem_->channels)
        total += channel->memoryController->getTotalRefreshes();
    return total;
}

void PIMKernel::setActivePimChannels(unsigned channels, unsigned channel_start)
{
    const unsigned configured_channels = getConfigParam(UINT, "NUM_CHANS");
    if (channels == 0 || channel_start >= configured_channels ||
        channels > configured_channels - channel_start)
        throw invalid_argument("Active PIM channel count is outside the configured HBM range");
    vector<int> selected_channels;
    for (unsigned channel = 0; channel < channels; channel++)
        selected_channels.push_back(channel_start + channel);
    setActivePimChannelList(selected_channels);
}

void PIMKernel::setActivePimChannelList(const vector<int>& channels)
{
    if (channels.empty()) throw invalid_argument("At least one PIM channel must be active");
    num_pim_chans_ = channels.size();
    num_total_pim_blocks_ = num_pim_blocks_ * num_pim_chans_ * num_pim_ranks_;
    pim_chans_ = channels;
}

void PIMKernel::parkIn()
{
    addBarrier();
    for (int& ch_idx : pim_chans_)
    {
        for (int& ra_idx : pim_ranks_)
        {
            for (int bank_idx = 0; bank_idx < num_banks_ / num_bank_groups_; bank_idx++)
            {
                for (int bg_idx = 0; bg_idx < num_bank_groups_; bg_idx++)
                {
                    string str = "PARK_IN_";
                    if (bg_idx == 0 && bank_idx == 0)
                        str = "START_" + str;
                    else if (bg_idx == 3 && bank_idx == 3)
                        str = "END_" + str;
                    mem_->addTransaction(
                        false,
                        pim_addr_mgr_->addrGen(ch_idx, ra_idx, bg_idx, bank_idx, (1 << 13), 0), domainTag(str),
                        &null_bst_);
                }
            }
        }
    }
    addBarrier();
}

void PIMKernel::parkOut()
{
    for (int& ch_idx : pim_chans_)
    {
        for (int& ra_idx : pim_ranks_)
        {
            for (int bank_idx = 0; bank_idx < num_banks_ / num_bank_groups_; bank_idx++)
            {
                for (int bg_idx = 0; bg_idx < num_bank_groups_; bg_idx++)
                {
                    string str = "PARK_OUT_";
                    if (bg_idx == 0 && bank_idx == 0)
                        str = "START_" + str;
                    else if (bg_idx == 3 && bank_idx == 3)
                        str = "END_" + str;
                    mem_->addTransaction(
                        false,
                        pim_addr_mgr_->addrGen(ch_idx, ra_idx, bg_idx, bank_idx, (1 << 13), 0), domainTag(str),
                        &null_bst_);
                }
            }
        }
    }
    addBarrier();
}

void PIMKernel::addTransactionAll(bool is_write, int bg_idx, int bank_idx, int row, int col,
                                  const string tag, BurstType* bst, bool use_barrier, int num_loop,
                                  WriteCompletionClass completionClass)
{
    for (int& ch_idx : pim_chans_)
        for (int& ra_idx : pim_ranks_)
        {
            unsigned local_row = row;
            unsigned local_col = col;
            for (int i = 0; i < num_loop; i++)
            {
                uint64_t addr = pim_addr_mgr_->addrGenSafe(ch_idx, ra_idx, bg_idx, bank_idx,
                                                           local_row, local_col);
                const string tagged = domainTag(tag);
                (tagged != "") ? mem_->addTransaction(is_write, addr, tagged, bst,
                                                       completionClass)
                               : mem_->addTransaction(is_write, addr, bst);
                local_col++;
            }
        }

    if (use_barrier)
        addBarrier();
}

string PIMKernel::domainTag(const string& tag) const
{
    if (!getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES")) return tag;
    return string(logicTransactionDomain_ ? "LOGIC_DOMAIN_" : "BANK_DOMAIN_") + tag;
}

void PIMKernel::addTransactionAll(bool is_write, int bg_idx, int bank_idx, int row, int col,
                                  BurstType* bst, bool use_barrier, int num_loop)
{
    addTransactionAll(is_write, bg_idx, bank_idx, row, col, "", bst, use_barrier, num_loop);
}

void PIMKernel::addBarrier()
{
    for (int& ch_idx : pim_chans_) mem_->addBarrier(ch_idx);
}

void PIMKernel::changePIMMode(dramMode curMode, dramMode nextMode)
{
    if (curMode == dramMode::SB && nextMode == dramMode::HAB)
    {
        addTransactionAll(true, 0, 0, pim_abmr_ra_, 0x1f, "START_SB_TO_HAB_", &null_bst_, false,
                          1, WriteCompletionClass::PIM_MODE);
        addTransactionAll(true, 0, 1, pim_abmr_ra_, 0x1f, "SB_TO_HAB_BANK1", &null_bst_, false, 1,
                          WriteCompletionClass::PIM_MODE);
        if (num_banks_ >= 2)
        {
            addTransactionAll(true, 2, 0, pim_abmr_ra_, 0x1f, "SB_TO_HAB_BANK8", &null_bst_, false, 1,
                              WriteCompletionClass::PIM_MODE);
            addTransactionAll(true, 2, 1, pim_abmr_ra_, 0x1f, "END_SB_TO_HAB_", &null_bst_,
                              false, 1, WriteCompletionClass::PIM_MODE);
        }
    }
    else if (curMode == dramMode::HAB)
    {
        if (nextMode == dramMode::SB)
        {
            addTransactionAll(true, 0, 0, pim_sbmr_ra_, 0x1f, "START_HAB_TO_SB", &null_bst_,
                              false, 1, WriteCompletionClass::PIM_MODE);
            addTransactionAll(true, 0, 1, pim_sbmr_ra_, 0x1f, "END_HAB_TO_SB", &null_bst_, false,
                              1, WriteCompletionClass::PIM_MODE);
        }
        else if (nextMode == dramMode::HAB_PIM)
        {
            addTransactionAll(true, 0, 0, pim_reg_ra_, 0x0, "PIM", &bst_hab_pim_, false, 1,
                              WriteCompletionClass::PIM_MODE);
        }
    }
    else if (curMode == dramMode::HAB_PIM && nextMode == dramMode::HAB)
        addTransactionAll(true, 0, 0, pim_reg_ra_, 0x0, "PIM", &bst_hab_, false, 1,
                          WriteCompletionClass::PIM_MODE);

    addBarrier();
}

/*
void PIMKernel::preprocessBn(NumpyBurstType* mean_npbst, NumpyBurstType* var_npbst,
                             NumpyBurstType* gamma_npbst, NumpyBurstType* beta_npbst,
                             NumpyBurstType* input_npbst, fp16** params, float eps)
{
    for (int i = 0; i < input_npbst->bShape[0]; i++)
    {
        params[i][0] = 1 / sqrt((float)var_npbst->getBurst(i / 16).fp16Data_[i % 16] + eps);
        params[i][1] = gamma_npbst->getBurst(i / 16).fp16Data_[i % 16];
        params[i][2] = -mean_npbst->getBurst(i / 16).fp16Data_[i % 16] /
                       sqrt((float)var_npbst->getBurst(i / 16).fp16Data_[i % 16] + eps);
        params[i][3] = beta_npbst->getBurst(i / 16).fp16Data_[i % 16];
    }
}

// FIXME : FIX size of srf_bst_. if ch_model is bigger than memory channel, it is not defined.
void PIMKernel::preprocessSrf(NumpyBurstType* input_npbst, fp16** params, int burst_offset,
                              int num_srf_usage)
{
    int ch_idx = 0;
    int ra_idx = 0;
    int burst_idx = 0;
    int num_stride_reg = 2;
    srf_bst_ = new BurstType[num_pim_chans_ * num_pim_ranks_];

    for (int ch_model = 0; ch_model < input_npbst->bShape[0]; ch_model++)
    {
        srf_bst_[ch_idx * num_pim_ranks_ + ra_idx].fp16Data_[burst_idx] =
            params[ch_model][0]; // scale
        srf_bst_[ch_idx * num_pim_ranks_ + ra_idx].fp16Data_[burst_idx + 1] =
            params[ch_model][1]; // gamma
        srf_bst_[ch_idx * num_pim_ranks_ + ra_idx].fp16Data_[burst_idx + 8] =
            params[ch_model][2]; // shift
        srf_bst_[ch_idx * num_pim_ranks_ + ra_idx].fp16Data_[burst_idx + 9] =
            params[ch_model][3]; // beta

        ra_idx++;
        if (ra_idx >= num_pim_ranks_)
        {
            ra_idx = 0;
            ch_idx++;
        }
        if (ch_idx >= num_pim_chans_)
        {
            ch_idx = 0;
            burst_idx += num_stride_reg;
        }
        if (burst_idx >= 8)
        {
            cout << "error: this is not defined" <<endl;
        }
    }
}

void PIMKernel::programSrf()
{
    for (int ch_idx = 0; ch_idx < num_pim_chans_; ch_idx++)
    {
        for (int ra_idx = 0; ra_idx < num_pim_ranks_; ra_idx++)
        {
            mem_->addTransaction(true,
                                 pim_addr_mgr_->addrGen(pim_chans_[ch_idx], ra_idx, 0, 0,
                                                        pim_reg_ra_, 0x1),
                                 &srf_bst_[ch_idx * num_pim_ranks_ + ra_idx]);
        }
    }
    addBarrier();
}
*/

void PIMKernel::programCrf(vector<PIMCmd>& cmds, bool logic_die)
{
    crfProgramCalls_++;
    PIMCmd nop_cmd(PIMCmdType::NOP, 0);
    for (int i = 0; i < 4; i++)
    {
        if (i * 8 >= cmds.size())
            break;
        crf_bst_[i].set(nop_cmd.toInt(), nop_cmd.toInt(), nop_cmd.toInt(), nop_cmd.toInt(),
                        nop_cmd.toInt(), nop_cmd.toInt(), nop_cmd.toInt(), nop_cmd.toInt());
        for (int j = 0; j < 8; j++)
        {
            if (i * 8 + j >= cmds.size())
                break;
            crf_bst_[i].u32Data_[j] = cmds[i * 8 + j].toInt();
        }
        addTransactionAll(true, 0, 1, pim_reg_ra_, 0x4 + i,
                          logic_die ? "PROGRAM_LOGIC_CRF" : "PROGRAM_BANK_CRF",
                          &(crf_bst_[i]), false, 1, WriteCompletionClass::PIM_CONTROL);
    }
    addBarrier();
}

void PIMKernel::setControl(BurstType* bst, bool pim_op, int crf_toggle_cond, bool grfA_zero,
                           bool grfB_zero)
{
    bst->u8Data_[0] = pim_op;
    bst->u8Data_[16] = crf_toggle_cond;
    bst->u8Data_[20] = grfA_zero;
    bst->u8Data_[21] = grfB_zero;
}

unsigned PIMKernel::getResultColGemv(int input_dim, int output_dim)
{
    int num_output_tiles = ceil(((double)output_dim / (num_total_pim_blocks_)) / num_grfB_);
    int num_input_tiles = ceil((double)input_dim / (double)num_grfA_);

    return num_output_tiles * num_input_tiles / 2 * num_grfA_ * num_grfB_;
}

void PIMKernel::changeBank(pimBankType pb_type, int& ch_idx, int& ra_idx, int& bg_idx,
                           int& bank_idx, unsigned& starting_row, unsigned& starting_col,
                           unsigned& row, unsigned& col)
{
    bank_idx += (pb_type == pimBankType::ALL_BANK) ? 1 : (num_banks_ / num_pim_blocks_);

    if (bank_idx >= (num_banks_ / num_bank_groups_))
    {
        bank_idx = 0;
        if (++bg_idx >= num_bank_groups_)
        {
            bg_idx = 0;
            if (++ra_idx >= num_pim_ranks_)
            {
                ra_idx = 0;
                if (++ch_idx >= num_pim_chans_)
                {
                    ch_idx = 0;
                    starting_row = row;
                    starting_col = col;
                }
            }
        }
    }
}

void PIMKernel::preloadGemv(NumpyBurstType* operand, unsigned starting_row, unsigned starting_col,
                            bool fill_shared_weight_buffer)
{
    int input_tile_size = num_grfA_;
    int output_tile_size = num_grfB_ * num_total_pim_blocks_;

    int ch_idx = 0, ra_idx = 0, bg_idx = 0, bank_idx = 0;
    unsigned row = 0, col = 0;
    uint64_t addr;

    unsigned even_starting_row = starting_row, odd_starting_row = starting_row;
    unsigned even_starting_col = starting_col, odd_starting_col = starting_col;
    uint64_t shared_fill_burst = 0;
    const unsigned requested_fill_channels =
        min(getConfigParam(UINT, "LOGIC_WEIGHT_FILL_CHANNELS"),
            getConfigParam(UINT, "NUM_CHANS"));
    const string fill_policy = getConfigParam(STRING, "LOGIC_WEIGHT_FILL_POLICY");
    if (fill_shared_weight_buffer && requested_fill_channels > 0 &&
        fill_policy != "round_robin" && fill_policy != "bank_aware" &&
        fill_policy != "row_local" && fill_policy != "row_interleaved")
        throw invalid_argument(
            "LOGIC_WEIGHT_FILL_POLICY must be round_robin, bank_aware, row_local, or "
            "row_interleaved");
    vector<vector<uint64_t>> fill_bank_load(
        requested_fill_channels, vector<uint64_t>(num_banks_, 0));
    vector<uint64_t> fill_total_load(requested_fill_channels, 0);

    for (int y = 0; y < operand->bShape[0]; y += output_tile_size)
    {
        for (int x = 0; x < operand->bShape[1]; x += input_tile_size)
        {
            bool is_odd = ((x / input_tile_size) % 2 == 1) ? true : false;

            for (int tiled_y = 0; tiled_y < output_tile_size; tiled_y += num_grfB_)
            {
                row = (is_odd) ? odd_starting_row : even_starting_row;
                col = (is_odd) ? odd_starting_col : even_starting_col;

                for (int grfb_idx = 0; grfb_idx < num_grfB_; grfb_idx++)
                {
                    for (int grfa_idx = 0; grfa_idx < num_grfA_; grfa_idx++, col++)
                    {
                        addr = pim_addr_mgr_->addrGenSafe(pim_chans_[ch_idx], ra_idx, bg_idx,
                                                          bank_idx + is_odd, row, col);
                        int d_idx = (y + tiled_y + grfb_idx) * operand->bShape[1] + x + grfa_idx;
                        if (fill_shared_weight_buffer &&
                            !mem_->storeLogicWeight(addr, operand->bData[d_idx]))
                            throw runtime_error("Logic weight buffer capacity or mapping overflow");
                        uint64_t transaction_addr = addr;
                        if (fill_shared_weight_buffer && requested_fill_channels > 0)
                        {
                            const unsigned physical_bank = bank_idx + is_odd;
                            unsigned fill_channel = shared_fill_burst % requested_fill_channels;
                            if (fill_policy == "bank_aware")
                            {
                                for (unsigned candidate = 1;
                                     candidate < requested_fill_channels; candidate++)
                                {
                                    if (fill_bank_load[candidate][physical_bank] <
                                            fill_bank_load[fill_channel][physical_bank] ||
                                        (fill_bank_load[candidate][physical_bank] ==
                                             fill_bank_load[fill_channel][physical_bank] &&
                                         fill_total_load[candidate] <
                                             fill_total_load[fill_channel]))
                                        fill_channel = candidate;
                                }
                            }
                            shared_fill_burst++;
                            const uint64_t channel_fill_slot = fill_total_load[fill_channel];
                            fill_bank_load[fill_channel][physical_bank]++;
                            fill_total_load[fill_channel]++;
                            if (fill_policy == "row_local" ||
                                fill_policy == "row_interleaved")
                            {
                                const unsigned columns_per_row = pim_addr_mgr_->num_cols_per_bl_;
                                const unsigned banks_per_group =
                                    num_banks_ / num_bank_groups_;
                                const bool interleave_banks =
                                    fill_policy == "row_interleaved";
                                const unsigned flat_bank =
                                    interleave_banks
                                        ? channel_fill_slot % num_banks_
                                        : (channel_fill_slot / columns_per_row) % num_banks_;
                                unsigned staging_row =
                                    getConfigParam(UINT, "LOGIC_WEIGHT_STAGING_ROW") +
                                    channel_fill_slot / (columns_per_row * num_banks_);
                                unsigned staging_col =
                                    interleave_banks
                                        ? (channel_fill_slot / num_banks_) % columns_per_row
                                        : channel_fill_slot % columns_per_row;
                                transaction_addr = pim_addr_mgr_->addrGenSafe(
                                    fill_channel, ra_idx, flat_bank / banks_per_group,
                                    flat_bank % banks_per_group, staging_row, staging_col);
                            }
                            else
                            {
                                transaction_addr = pim_addr_mgr_->addrGenSafe(
                                    fill_channel, ra_idx, bg_idx, physical_bank, row, col);
                            }
                        }
                        mem_->addTransaction(true, transaction_addr, "LOGIC_WEIGHT_FILL",
                                              &operand->bData[d_idx],
                                              WriteCompletionClass::BULK_DATA);
                    }
                }
                is_odd ? changeBank(pimBankType::ODD_BANK, ch_idx, ra_idx, bg_idx, bank_idx,
                                    odd_starting_row, odd_starting_col, row, col)
                       : changeBank(pimBankType::EVEN_BANK, ch_idx, ra_idx, bg_idx, bank_idx,
                                    even_starting_row, even_starting_col, row, col);
            }
        }
    }
}

void PIMKernel::preloadNoReplacement(NumpyBurstType* operand, unsigned starting_row,
                                     unsigned starting_col)
{
    uint64_t init_addr = pim_addr_mgr_->addrGenSafe(0, 0, 0, 0, starting_row, starting_col);

    for (int x = 0; x < operand->getTotalDim(); x++)
    {
        uint64_t addr = init_addr + x * transaction_size_;
        mem_->addTransaction(true, addr, domainTag("PRELOAD_DATA"), &operand->bData[x]);
    }
}
/*
void PIMKernel::preloadEltwise(NumpyBurstType* operand, pimBankType pb_type,
                              unsigned starting_row, unsigned starting_col)
{
   int ch_idx = 0;
   int ra_idx = 0;
   int bg_idx = 0;
   int bank_idx = 0;
   int bank_offset =  (int)pb_type % 2;
   uint64_t addr_op;
   int dim_operand = operand->getTotalDim();

   for (int x=0; x < dim_operand; x+=num_grf_)
   {
       unsigned col = starting_col;
       unsigned row = starting_row;

       for (int grf_idx = 0; grf_idx < num_grf_; grf_idx++)
       {
           addr_op = pim_addr_mgr_->addrGenSafe(ch_idx, ra_idx, bg_idx, bank_idx + bank_offset, row,
                                                col);
           mem_->addTransaction(true, addr_op, &operand->bData[x + grf_idx]);
           col++;
       }
       changeBank(pb_type, ch_idx, ra_idx, bg_idx, bank_idx, starting_row, starting_col, row, col);
   }
}
*/
void PIMKernel::executeGemv(NumpyBurstType* w_data, NumpyBurstType* i_data, bool is_tree,
                            bool program_crf, bool enter_hab, bool exit_hab)
{
    const bool previous_domain = logicTransactionDomain_;
    logicTransactionDomain_ = usesLogicDiePIM() && !is_tree;
    int num_output_tiles = ceil(((double)w_data->bShape[0] / (num_total_pim_blocks_)) / num_grfB_);
    int num_input_tiles = ceil((double)w_data->bShape[1] / (double)num_grfA_);
    int num_batch = i_data->bShape[0];
    int zero_row = 1000;

    if (is_tree)
    {
        for (int ch = 0; ch < num_pim_chans_; ch++)
        {
            for (int bg_idx = 0; bg_idx < num_bank_groups_; bg_idx++)
            {
                for (int ba = 0; ba < num_banks_ / num_bank_groups_; ba++)
                {
                    for (int ca = 0; ca < num_grfA_; ca++)
                    {
                        uint64_t addr =
                            pim_addr_mgr_->addrGen(pim_chans_[ch], 0, bg_idx, ba, zero_row, ca);
                        mem_->addTransaction(true, addr, &null_bst_);
                    }
                }
            }
        }
    }

    vector<PIMCmd> pim_cmds;
    if (is_tree)
    {
        int num_jump = ceil((double)num_input_tiles / 2) - 1;
        pim_cmds = PIMCmdGen::getPIMCmds(KernelType::GEMVTREE, num_jump, 0, 0);
    }
    else
    {
        int num_jump_of_even_bank = num_grfB_ * ceil((double)num_input_tiles / 2) - 1;
        int num_jump_of_odd_bank = num_grfB_ * floor(num_input_tiles / 2) - 1;
        pim_cmds =
            PIMCmdGen::getPIMCmds(KernelType::GEMV, 0, num_jump_of_odd_bank, num_jump_of_even_bank);
    }
    setControl(&bst_hab_pim_, true, getToggleCond(), false, true);
    if (enter_hab)
    {
        logicHabEntries_++;
        parkIn();
        changePIMMode(dramMode::SB, dramMode::HAB);
    }
    else
    {
        // parkIn() normally provides the cross-channel boundary before a new
        // GEMV wave. HAB residency removes the parking commands, not that
        // dependency: every channel must retire the previous wave first.
        addBarrier();
    }
    if (program_crf) programCrf(pim_cmds, true);

    for (int j = 0; j < num_output_tiles; j++)
    {
        for (int b = 0; b < num_batch; b++)
        {
            changePIMMode(dramMode::HAB, dramMode::HAB_PIM);  // PC reset.

            int col = num_output_tiles * num_input_tiles / 2 * num_grfA_ * num_grfB_ +
                      (j + b) * num_grfB_;
            if (is_tree)
            {
                for (int i = 0; i < num_input_tiles; i++, col += num_grfB_)
                {
                    computeGemv(i_data, num_input_tiles, num_output_tiles, i, j, b,
                                (i % 2 == 0) ? pimBankType::EVEN_BANK : pimBankType::ODD_BANK);
                    addTransactionAll(true, 0, 1, 0, col, "GRFB_TO_BANK_", &null_bst_, true,
                                      num_grf_, WriteCompletionClass::PIM_WRITEBACK);
                    addTransactionAll(false, 0, 0, zero_row, 0, "RESET_GRF_B", &null_bst_, true,
                                      num_grfB_);
                }
            }
            else
            {
                for (int i = 0; i < num_input_tiles; i += 2)
                    computeGemv(i_data, num_input_tiles, num_output_tiles, i, j, b,
                                pimBankType::EVEN_BANK);
                for (int i = 1; i < num_input_tiles; i += 2)
                    computeGemv(i_data, num_input_tiles, num_output_tiles, i, j, b,
                                pimBankType::ODD_BANK);
                addTransactionAll(true, 0, 1, 0, col, "GRFB_TO_BANK_", &null_bst_, true,
                                  num_grf_, WriteCompletionClass::PIM_WRITEBACK);
            }
            changePIMMode(dramMode::HAB_PIM, dramMode::HAB);  // for grfBReset
        }
    }
    if (exit_hab)
    {
        logicHabExits_++;
        changePIMMode(dramMode::HAB, dramMode::SB);
        parkOut();
    }
    logicTransactionDomain_ = previous_domain;
}

void PIMKernel::computeGemv(NumpyBurstType* data, int num_input_tiles, int num_output_tiles,
                            int inputTile, int outputTile, int batchIdx, pimBankType pb_type)
{
    for (int ch_idx = 0; ch_idx < num_pim_chans_; ch_idx++)
    {
        for (int ra_idx = 0; ra_idx < num_pim_ranks_; ra_idx++)
        {
            // input upload to GRF
            for (int gidx = 0; gidx < num_grfA_; gidx++)
            {
                string str = "WRIO_TO_GRF_";
                uint64_t addr = pim_addr_mgr_->addrGen(pim_chans_[ch_idx], ra_idx, 0, 1,
                                                       pim_reg_ra_, 0x8 + gidx);
                int input_idx =
                    batchIdx * num_grfA_ * num_input_tiles + inputTile * num_grfA_ + gidx;
                if (DEBUG_CMD_TRACE && ch_idx == 0 && ra_idx == 0 && gidx == 0)
                {
                    cout << "GEMV_INPUT_TILE"
                         << " batch[" << batchIdx << "]"
                         << " inputTile[" << inputTile << "]"
                         << " outputTile[" << outputTile << "]"
                         << " pb[" << (int)pb_type << "]"
                         << " input_idx[" << input_idx << "]"
                         << " addr[" << addr << "]" << endl;
                }
                mem_->addTransaction(true, addr, domainTag(str), &data->bData[input_idx]);
            }
            mem_->addBarrier(pim_chans_[ch_idx]);
        }
    }

    unsigned row = 0;
    unsigned col = (num_grfA_ * num_grfB_) * (inputTile / 2 + outputTile * num_input_tiles / 2);
    if (DEBUG_CMD_TRACE)
    {
        cout << "GEMV_MAC_BASE"
             << " batch[" << batchIdx << "]"
             << " inputTile[" << inputTile << "]"
             << " outputTile[" << outputTile << "]"
             << " pb[" << (int)pb_type << "]"
             << " colBase[" << col << "]" << endl;
    }

    for (int c_idx = 0; c_idx < 64; c_idx += 8)
        addTransactionAll(false, 0, (int)pb_type, row, col + c_idx, "MAC_", &null_bst_, true,
                          num_grfA_);
}

void PIMKernel::readResult(BurstType* resultBst, pimBankType pb_type, int output_dim,
                           uint64_t base_addr, unsigned starting_row, unsigned starting_col,
                           uint64_t output_layer, uint64_t output_position)
{
    int ch_idx = 0;
    int ra_idx = 0;
    int bg_idx = 0;
    int bank_idx = 0;
    int bank_offset = (int)pb_type % 2;
    uint64_t addr;

    for (int x = 0; x < output_dim; x += num_grf_)
    {
        unsigned row = starting_row;
        unsigned col = starting_col;

        static int read_result_dbg = 0;
        if (read_result_dbg < 12)
        {
            cout << "READ_RESULT_TRACE"
                 << " x[" << x << "]"
                 << " row[" << row << "]"
                 << " col[" << col << "]"
                 << " pb[" << (int)pb_type << "]"
                 << " bankOffset[" << bank_offset << "]" << endl;
            read_result_dbg++;
        }

        for (int grf_idx = 0; grf_idx < num_grf_; grf_idx++)
        {
            addr = pim_addr_mgr_->addrGenSafe(pim_chans_[ch_idx], ra_idx, bg_idx,
                                              bank_idx + bank_offset, row, col);
            Transaction* transaction = new Transaction(
                DATA_READ, base_addr + addr, domainTag("output"), &resultBst[x + grf_idx]);
            if (output_layer != 0 && getConfigParam(BOOL, "LOGIC_OUTPUT_BUFFER_ENABLE"))
            {
                transaction->logicOutput = true;
                transaction->logicOutputDirect = true;
                transaction->tag = domainTag("LOGIC_OUTPUT_DRAIN");
                transaction->logicOutputLayer = output_layer;
                transaction->logicOutputPosition = output_position;
                transaction->logicOutputChannelTile = 0;
                transaction->logicOutputBurst = x + grf_idx;
                transaction->logicOutputExpectedBursts = output_dim;
            }
            mem_->addTransaction(transaction);
            col++;
        }
        changeBank(pb_type, ch_idx, ra_idx, bg_idx, bank_idx, starting_row, starting_col, row, col);
    }
}

void PIMKernel::executeEltwise(int dim, pimBankType pb_type, KernelType ktype, int input0_row,
                               int result_row, int input1_row)
{
    int num_tile = dim / (num_banks_ * num_pim_chans_ * num_pim_ranks_ * num_grf_);
    int num_jump_to_be_taken = num_tile - 1;
    vector<PIMCmd> pim_cmds = PIMCmdGen::getPIMCmds(ktype, num_jump_to_be_taken, 0, 0);

    setControl(&bst_hab_pim_, true, getToggleCond(pb_type), false, false);
    setControl(&bst_hab_, false, getToggleCond(pb_type), false, false);

    parkIn();
    changePIMMode(dramMode::SB, dramMode::HAB);
    programCrf(pim_cmds);
    changePIMMode(dramMode::HAB, dramMode::HAB_PIM);

    if (ktype == KernelType::ADD || ktype == KernelType::MUL)
        computeAddOrMul(num_tile, input0_row, result_row, input1_row);
    else if (ktype == KernelType::RELU)
        computeRelu(num_tile, input0_row, result_row);
    /*
       else if (ktype == KernelType::BN)
       computeBn(num_tile, input0_row, result_row);
     */

    changePIMMode(dramMode::HAB_PIM, dramMode::HAB);
    changePIMMode(dramMode::HAB, dramMode::SB);
    parkOut();
}

vector<fp16> PIMKernel::executePointwiseAndRead(NumpyBurstType* weights, NumpyBurstType* input,
                                                unsigned logical_output_dim)
{
    if (input == nullptr || input->bShape.size() != 2 || input->bShape[0] != 1)
        throw invalid_argument("Single pointwise adapter expects one input vector");
    return executePointwiseBatchAndRead(weights, input, logical_output_dim);
}

vector<fp16> PIMKernel::executePointwiseBatchAndRead(NumpyBurstType* weights,
                                                     NumpyBurstType* input,
                                                     unsigned logical_output_dim,
                                                     unsigned channel_start)
{
    if (weights == nullptr || input == nullptr || weights->bShape.size() != 2 ||
        input->bShape.size() != 2 || input->bShape[0] == 0)
        throw invalid_argument("Batch pointwise adapter expects 2D weights and input");
    if (weights->bShape[1] != input->bShape[1])
        throw invalid_argument("Pointwise input and weight dimensions do not match");
    if (logical_output_dim == 0 || logical_output_dim > weights->bShape[0])
        throw invalid_argument("Logical pointwise output exceeds the physical output tile");
    if (channel_start == 0 && usesLogicDiePIM() &&
        getConfigParam(BOOL, "LOGIC_SPATIAL_GROUPING"))
        return executePointwiseSpatialGroupsAndRead(weights, input, logical_output_dim);

    const vector<int> original_channels = pim_chans_;
    NumpyBurstType compact_weights;
    NumpyBurstType* execution_weights = weights;
    const bool use_compact_mapping =
        usesLogicDiePIM() && getConfigParam(BOOL, "LOGIC_COMPACT_OUTPUT");
    if (use_compact_mapping)
    {
        const unsigned outputs_per_channel = num_pim_blocks_ * num_pim_ranks_ * num_grfB_;
        const unsigned active_channels =
            (logical_output_dim + outputs_per_channel - 1) / outputs_per_channel;
        const unsigned compact_output_dim = active_channels * outputs_per_channel;
        compact_weights = *weights;
        compact_weights.shape[0] = compact_output_dim;
        compact_weights.bShape[0] = compact_output_dim;
        compact_weights.bData.resize(static_cast<uint64_t>(compact_output_dim) *
                                     compact_weights.bShape[1]);
        execution_weights = &compact_weights;
        setActivePimChannels(active_channels, channel_start);
    }
    else if (channel_start != 0)
        throw invalid_argument("A nonzero pointwise channel start requires compact logic mapping");
    lastPointwiseActiveChannels_ = num_pim_chans_;
    lastPointwisePhysicalOutputDim_ = execution_weights->bShape[0];
    lastPointwiseSpatialGroups_ = 1;
    lastPointwiseBatchWaves_ = input->bShape[0];

    try
    {
        preloadGemv(execution_weights);
        executeGemv(execution_weights, input, false);
        const unsigned end_col =
            getResultColGemv(input->bShape[1], execution_weights->bShape[0]);
        const unsigned batch_size = input->bShape[0];
        const unsigned read_output_dim =
            ((logical_output_dim + num_grf_ - 1) / num_grf_) * num_grf_;
        vector<vector<BurstType>> physical_output(
            batch_size, vector<BurstType>(read_output_dim));
        for (unsigned batch = 0; batch < batch_size; batch++)
            readResult(physical_output[batch].data(), pimBankType::ODD_BANK, read_output_dim, 0,
                       0, end_col + batch * num_grf_);
        runPIM();

        vector<fp16> logical_output(static_cast<uint64_t>(batch_size) * logical_output_dim);
        for (unsigned batch = 0; batch < batch_size; batch++)
            for (unsigned output = 0; output < logical_output_dim; output++)
                logical_output[static_cast<uint64_t>(batch) * logical_output_dim + output] =
                    physical_output[batch][output].fp16ReduceSum();
        setActivePimChannelList(original_channels);
        return logical_output;
    }
    catch (...)
    {
        setActivePimChannelList(original_channels);
        throw;
    }
}

vector<fp16> PIMKernel::executePointwiseSpatialGroupsAndRead(NumpyBurstType* weights,
                                                              NumpyBurstType* input,
                                                              unsigned logical_output_dim)
{
    auto handle = enqueuePointwiseSpatialGroups(weights, input, logical_output_dim);
    waitPointwiseSpatial(handle);
    return readPointwiseSpatial(handle);
}

shared_ptr<PointwiseSpatialHandle> PIMKernel::enqueuePointwiseSpatialGroups(
    NumpyBurstType* weights, NumpyBurstType* input, unsigned logical_output_dim)
{
    return enqueuePointwiseSpatialGroupsInternal(weights, input, logical_output_dim, false);
}

shared_ptr<PointwiseSpatialHandle> PIMKernel::enqueuePointwiseSpatialGroupsInternal(
    NumpyBurstType* weights, NumpyBurstType* input, unsigned logical_output_dim,
    bool reuse_shared_weight_layer, vector<bool>* crf_resident_groups)
{
    if (weights == nullptr || input == nullptr || weights->bShape.size() != 2 ||
        input->bShape.size() != 2 || input->bShape[0] == 0)
        throw invalid_argument("Spatial pointwise adapter expects 2D weights and input");
    if (!usesLogicDiePIM() || !getConfigParam(BOOL, "LOGIC_COMPACT_OUTPUT"))
        throw invalid_argument("Spatial grouping requires compact logic-die PIM mapping");
    if (weights->bShape[1] != input->bShape[1] || logical_output_dim == 0 ||
        logical_output_dim > weights->bShape[0])
        throw invalid_argument("Spatial pointwise dimensions are inconsistent");
    if (pointwiseSpatialOutstanding_)
        throw logic_error("Only one spatial pointwise handle may be outstanding");

    auto handle = make_shared<PointwiseSpatialHandle>();
    handle->logicalOutputDim = logical_output_dim;
    handle->outputLayer = ++outputLayerGeneration_;
    mem_->logicDieOutputBuffer->beginLayer(handle->outputLayer);

    const vector<int> original_channels = pim_chans_;
    const unsigned outputs_per_channel = num_pim_blocks_ * num_pim_ranks_ * num_grfB_;
    const unsigned channels_per_group =
        (logical_output_dim + outputs_per_channel - 1) / outputs_per_channel;
    const unsigned compact_output_dim = channels_per_group * outputs_per_channel;
    const unsigned batch_size = input->bShape[0];
    const unsigned group_count =
        min(static_cast<unsigned>(original_channels.size()) / channels_per_group, batch_size);
    if (group_count == 0) throw invalid_argument("Not enough HBM channels for one spatial group");
    const unsigned group_capacity =
        static_cast<unsigned>(original_channels.size()) / channels_per_group;
    if (crf_resident_groups != nullptr && crf_resident_groups->size() < group_capacity)
        crf_resident_groups->resize(group_capacity, false);

    NumpyBurstType& compact_weights = handle->compactWeights;
    compact_weights = *weights;
    compact_weights.shape[0] = compact_output_dim;
    compact_weights.bShape[0] = compact_output_dim;
    compact_weights.bData.resize(static_cast<uint64_t>(compact_output_dim) *
                                 compact_weights.bShape[1]);
    const uint64_t one_weight_copy_bytes =
        compact_weights.bData.size() * static_cast<uint64_t>(transaction_size_);
    const uint64_t baseline_weight_bytes = one_weight_copy_bytes * group_count;
    const bool shared_weight_hit = getConfigParam(BOOL, "LOGIC_SHARED_WEIGHT_BUFFER") &&
                                   getConfigParam(UINT64, "LOGIC_WEIGHT_BUFFER_BYTES") >=
                                       one_weight_copy_bytes;
    if (reuse_shared_weight_layer &&
        (!shared_weight_hit || !mem_->logicDieWeightBuffer->isActive()))
        throw logic_error("Spatial session shared weight layer is no longer resident");
    const uint64_t physical_weight_bytes =
        shared_weight_hit ? (reuse_shared_weight_layer ? 0 : one_weight_copy_bytes)
                          : baseline_weight_bytes;
    const uint64_t modeled_weight_bytes = physical_weight_bytes;
    baselineLogicWeightBytes_ += baseline_weight_bytes;
    physicalLogicWeightBytes_ += physical_weight_bytes;
    modeledLogicWeightBytes_ += modeled_weight_bytes;
    savedLogicWeightBytes_ += baseline_weight_bytes - physical_weight_bytes;
    if (shared_weight_hit && !reuse_shared_weight_layer)
        mem_->beginLogicWeightLayer(channels_per_group,
                                    getConfigParam(UINT64, "LOGIC_WEIGHT_BUFFER_BYTES"));
    else if (!shared_weight_hit)
        mem_->beginLogicWeightLayer(0, 0);

    vector<NumpyBurstType>& position_inputs = handle->positionInputs;
    position_inputs.resize(batch_size);
    const uint64_t input_bursts = input->bShape[1];
    for (unsigned position = 0; position < batch_size; position++)
    {
        position_inputs[position].shape = {1, input->shape[1]};
        position_inputs[position].bShape = {1, input->bShape[1]};
        const auto begin = input->bData.begin() + position * input_bursts;
        position_inputs[position].bData.assign(begin, begin + input_bursts);
    }

    const unsigned read_output_dim =
        ((logical_output_dim + num_grf_ - 1) / num_grf_) * num_grf_;
    vector<vector<BurstType>>& physical_output = handle->physicalOutput;
    physical_output.assign(batch_size, vector<BurstType>(read_output_dim));
    handle->batchSize = batch_size;
    vector<bool> weights_preloaded(group_count, false);
    vector<bool> hab_resident(group_count, false);
    bool shared_weights_preloaded = reuse_shared_weight_layer;
    const bool keep_hab_resident =
        getConfigParam(BOOL, "LOGIC_HAB_RESIDENCY") &&
        getConfigParam(BOOL, "LOGIC_OUTPUT_BUFFER_ENABLE");

    const auto begin_release_epoch = [&]() {
        if (!getConfigParam(BOOL, "LOGIC_EPOCH_RELEASE")) return;
        // GEMV CRF executes eight auto-repeats across eight GRF lanes per populated
        // even/odd input-tile pair; an empty odd side still executes one repeat set.
        const uint64_t input_tiles =
            (compact_weights.bShape[1] + num_grfA_ - 1) / num_grfA_;
        const uint64_t even_commands = 64 * ((input_tiles + 1) / 2);
        const uint64_t odd_commands = input_tiles / 2 == 0 ? 8 : 64 * (input_tiles / 2);
        const uint64_t commands_per_position = even_commands + odd_commands;
        vector<pair<uint64_t, uint64_t>> stream_ordinals;
        for (unsigned expected_group = 0; expected_group < group_count; expected_group++)
        {
            const uint64_t positions =
                (batch_size + group_count - 1 - expected_group) / group_count;
            for (unsigned local_channel = 0; local_channel < channels_per_group;
                 local_channel++)
                for (int rank : pim_ranks_)
                {
                    const uint64_t channel =
                        expected_group * channels_per_group + local_channel;
                    stream_ordinals.push_back(
                        {channel * getConfigParam(UINT, "NUM_RANKS") + rank,
                         positions * commands_per_position});
                }
        }
        mem_->beginLogicReleaseEpoch(stream_ordinals.size(), stream_ordinals);
    };

    try
    {
        if (reuse_shared_weight_layer) begin_release_epoch();
        for (unsigned position = 0; position < batch_size; position++)
        {
            const unsigned group = position % group_count;
            setActivePimChannels(channels_per_group, group * channels_per_group);
            if (shared_weight_hit && !shared_weights_preloaded)
            {
                preloadGemv(&compact_weights, 0, 0, true);
                shared_weights_preloaded = true;
                const uint64_t barrier_start = cycle_;
                runPIM();
                logicWeightFillBarrierCycles_ += cycle_ - barrier_start;
                while (mem_->currentClockCycle <
                       mem_->logicDieWeightBuffer->getReadyCycle())
                {
                    cycle_++;
                    logicWeightBufferPortWaitCycles_++;
                    mem_->update();
                }
                const unsigned guard_cycles =
                    getConfigParam(UINT, "LOGIC_POST_FILL_GUARD_CYCLES");
                for (unsigned guard = 0; guard < guard_cycles; guard++)
                {
                    cycle_++;
                    logicPostFillGuardCycles_++;
                    mem_->update();
                }
                begin_release_epoch();
            }
            else if (!shared_weight_hit && !weights_preloaded[group])
            {
                preloadGemv(&compact_weights);
                weights_preloaded[group] = true;
            }
            const bool program_crf =
                crf_resident_groups == nullptr || !(*crf_resident_groups)[group];
            const bool previous_domain = logicTransactionDomain_;
            logicTransactionDomain_ = true;
            const bool enter_hab = !keep_hab_resident || !hab_resident[group];
            const bool last_position_for_group = position + group_count >= batch_size;
            const bool exit_hab = !keep_hab_resident || last_position_for_group;
            executeGemv(&compact_weights, &position_inputs[position], false, program_crf,
                        enter_hab, exit_hab);
            hab_resident[group] = !exit_hab;
            if (crf_resident_groups != nullptr) (*crf_resident_groups)[group] = true;
            const unsigned end_col =
                getResultColGemv(position_inputs[position].bShape[1], compact_output_dim);
            readResult(physical_output[position].data(), pimBankType::ODD_BANK, read_output_dim, 0,
                       0, end_col, handle->outputLayer, position);
            logicTransactionDomain_ = previous_domain;
        }
        lastPointwiseActiveChannels_ = channels_per_group;
        lastPointwisePhysicalOutputDim_ = compact_output_dim;
        lastPointwiseSpatialGroups_ = group_count;
        lastPointwiseBatchWaves_ = (batch_size + group_count - 1) / group_count;
        setActivePimChannelList(original_channels);
        pointwiseSpatialOutstanding_ = true;
        return handle;
    }
    catch (...)
    {
        setActivePimChannelList(original_channels);
        throw;
    }
}

void PIMKernel::waitPointwiseSpatial(const shared_ptr<PointwiseSpatialHandle>& handle)
{
    if (!pointwiseSpatialOutstanding_ || handle == nullptr || handle->consumed)
        throw logic_error("Invalid spatial pointwise handle");
    if (handle->waited) return;
    runPIM();

    if (getConfigParam(BOOL, "LOGIC_EPOCH_RELEASE") &&
        !getConfigParam(BOOL, "LOGIC_ONLINE_QUEUE_BACKPRESSURE"))
    {
        const auto backpressure = mem_->logicDieScheduler->applyBroadcastQueueDepth(
            getConfigParam(UINT, "LOGIC_BROADCAST_QUEUE_DEPTH"));
        logicBroadcastQueueLastPreStallCycle_ = cycle_;
        for (uint64_t stall = 0; stall < backpressure.stallCycles; stall++)
        {
            cycle_++;
            logicBroadcastQueueAppliedCycles_++;
            mem_->update();
        }
    }
    handle->waited = true;
}

vector<fp16> PIMKernel::readPointwiseSpatial(
    const shared_ptr<PointwiseSpatialHandle>& handle)
{
    if (!pointwiseSpatialOutstanding_ || handle == nullptr || handle->consumed)
        throw logic_error("Invalid spatial pointwise handle");
    if (!handle->waited) throw logic_error("Spatial pointwise handle must be waited before read");

    vector<fp16> logical_output(
        static_cast<uint64_t>(handle->batchSize) * handle->logicalOutputDim);
    if (!getConfigParam(BOOL, "LOGIC_OUTPUT_BUFFER_ENABLE"))
    {
        deque<unsigned> pending_positions;
        const auto drain_tile = [&](unsigned position) {
            const LogicDieOutputBuffer::TileId tile{handle->outputLayer, position, 0};
            for (unsigned output = 0; output < handle->logicalOutputDim; output++)
            {
                BurstType buffered;
                if (!mem_->logicDieOutputBuffer->read(tile, output, buffered))
                    throw logic_error("Logic-die output buffer tile was not ready");
                logical_output[static_cast<uint64_t>(position) * handle->logicalOutputDim +
                               output] = buffered.fp16ReduceSum();
            }
            if (!mem_->logicDieOutputBuffer->retire(tile))
                throw logic_error("Logic-die output buffer retirement order was violated");
        };
        for (unsigned position = 0; position < handle->batchSize; position++)
        {
            const LogicDieOutputBuffer::TileId tile{handle->outputLayer, position, 0};
            if (!mem_->logicDieOutputBuffer->reserve(
                    tile, handle->physicalOutput[position].size()))
            {
                if (!mem_->logicDieOutputBuffer->full() || pending_positions.empty())
                    throw logic_error("Logic-die output buffer rejected a valid tile");
                drain_tile(pending_positions.front());
                pending_positions.pop_front();
                if (!mem_->logicDieOutputBuffer->reserve(
                        tile, handle->physicalOutput[position].size()))
                    throw logic_error("Logic-die output buffer retry failed after retirement");
            }
            for (size_t burst = 0; burst < handle->physicalOutput[position].size(); burst++)
                if (!mem_->logicDieOutputBuffer->write(
                        tile, burst, handle->physicalOutput[position][burst]))
                    throw logic_error("Logic-die output buffer rejected a completed burst");
            pending_positions.push_back(position);
        }
        while (!pending_positions.empty())
        {
            drain_tile(pending_positions.front());
            pending_positions.pop_front();
        }
        handle->consumed = true;
        pointwiseSpatialOutstanding_ = false;
        return logical_output;
    }

    for (unsigned position = 0; position < handle->batchSize; position++)
    {
        const LogicDieOutputBuffer::TileId tile{handle->outputLayer, position, 0};
        for (unsigned output = 0; output < handle->logicalOutputDim; output++)
        {
            BurstType buffered;
            if (!mem_->logicDieOutputBuffer->readCommitted(tile, output, buffered))
                throw logic_error("Logic-die output tile was not committed by READ completion");
            logical_output[static_cast<uint64_t>(position) * handle->logicalOutputDim + output] =
                buffered.fp16ReduceSum();
        }
        if (!mem_->logicDieOutputBuffer->releaseCommitted(tile))
            throw logic_error("Logic-die output committed tile release failed");
    }
    handle->consumed = true;
    pointwiseSpatialOutstanding_ = false;
    return logical_output;
}

shared_ptr<PointwiseSpatialSession> PIMKernel::beginPointwiseSpatialSession(
    NumpyBurstType* weights, NumpyBurstType* input, unsigned height, unsigned width,
    unsigned logical_output_dim)
{
    if (weights == nullptr || input == nullptr || height == 0 || width == 0 ||
        input->bShape.size() != 2 || input->bShape[0] != height * width ||
        logical_output_dim == 0)
        throw invalid_argument("Invalid spatial pointwise session dimensions");
    auto session = make_shared<PointwiseSpatialSession>();
    session->weights = *weights;
    session->input = *input;
    session->height = height;
    session->width = width;
    session->logicalOutputDim = logical_output_dim;
    session->output.resize(static_cast<uint64_t>(height) * width * logical_output_dim);
    return session;
}

void PIMKernel::enqueuePointwiseRows(const shared_ptr<PointwiseSpatialSession>& session,
                                     unsigned row_start, unsigned row_count)
{
    if (session != nullptr && session->activeHandle != nullptr)
        throw logic_error("Previous spatial pointwise row range is still active");
    if (session == nullptr || row_count == 0 || row_start != session->nextRow ||
        row_start + row_count > session->height)
        throw invalid_argument("Spatial pointwise rows must be nonempty and contiguous");

    const uint64_t positions = static_cast<uint64_t>(row_count) * session->width;
    const uint64_t firstPosition = static_cast<uint64_t>(row_start) * session->width;
    const uint64_t burstsPerPosition = session->input.bShape[1];
    NumpyBurstType rowInput;
    rowInput.shape = {static_cast<unsigned long>(positions), session->input.shape[1]};
    rowInput.bShape = {static_cast<unsigned long>(positions), session->input.bShape[1]};
    const auto begin = session->input.bData.begin() + firstPosition * burstsPerPosition;
    rowInput.bData.assign(begin, begin + positions * burstsPerPosition);
    if (session->weightResident &&
        session->weightLayerGeneration !=
            mem_->logicDieWeightBuffer->getLayerGeneration())
        throw logic_error("Spatial session weight layer was replaced by another operation");
    const uint64_t fill_before = mem_->logicDieWeightBuffer->getFillBursts();
    const uint64_t crf_before = crfProgramCalls_;
    const bool reused = session->weightResident;
    session->activeHandle = enqueuePointwiseSpatialGroupsInternal(
        &session->weights, &rowInput, session->logicalOutputDim, reused,
        &session->logicCrfResidentGroups);
    const uint64_t fill_after = mem_->logicDieWeightBuffer->getFillBursts();
    const uint64_t crf_after = crfProgramCalls_;
    session->weightFillBursts += fill_after - fill_before;
    session->crfProgramCalls += crf_after - crf_before;
    if (reused)
    {
        session->reusedRowRanges++;
        session->reusedWeightFillBursts += fill_after - fill_before;
        session->reusedCrfProgramCalls += crf_after - crf_before;
    }
    session->weightResident = mem_->logicDieWeightBuffer->isActive();
    session->weightLayerGeneration = mem_->logicDieWeightBuffer->getLayerGeneration();
    session->activeRowStart = row_start;
    session->activeRowCount = row_count;
}

void PIMKernel::waitPointwiseRows(const shared_ptr<PointwiseSpatialSession>& session)
{
    if (session == nullptr || session->activeHandle == nullptr)
        throw logic_error("No active spatial pointwise row range");
    waitPointwiseSpatial(session->activeHandle);
}

vector<fp16> PIMKernel::readPointwiseRows(
    const shared_ptr<PointwiseSpatialSession>& session)
{
    if (session == nullptr || session->activeHandle == nullptr)
        throw logic_error("No active spatial pointwise row range");
    vector<fp16> rows = readPointwiseSpatial(session->activeHandle);
    const uint64_t destination =
        static_cast<uint64_t>(session->activeRowStart) * session->width *
        session->logicalOutputDim;
    copy(rows.begin(), rows.end(), session->output.begin() + destination);
    session->nextRow += session->activeRowCount;
    session->activeRowStart = 0;
    session->activeRowCount = 0;
    session->activeHandle.reset();
    return rows;
}

void PIMKernel::executeDepthwiseLowered(int dim, unsigned kernel_size, int input_base_row,
                                        int weight_base_row, int product_row,
                                        int accumulator_row, int result_row, int tap_row_stride)
{
    if (getConfigParam(BOOL, "LOGIC_DEPTHWISE_ACCUMULATION"))
    {
        if (!usesBankSidePIM() || !usesLogicDiePIM())
            throw logic_error("Hierarchical depthwise accumulation requires hybrid PIM");
        executeDepthwiseHierarchical(dim, kernel_size, input_base_row, weight_base_row,
                                     result_row, tap_row_stride);
        return;
    }
    auto handle = beginDepthwiseLowered(dim, kernel_size, input_base_row, weight_base_row,
                                        product_row, accumulator_row, result_row,
                                        tap_row_stride);
    while (!handle->complete)
    {
        enqueueDepthwiseStage(handle);
        waitDepthwiseStage(handle);
    }
}

void PIMKernel::advanceDepthwiseAccumulatorTransfer(uint64_t bytes,
                                                     uint64_t overlap_window)
{
    depthwiseAccumulatorTransferBytes_ += bytes;
    const uint64_t bandwidth = getConfigParam(UINT, "LOGIC_ACCUMULATOR_BW");
    const uint64_t transferCycles = bandwidth == 0 ? 0 : (bytes + bandwidth - 1) / bandwidth;
    const uint64_t latency = getConfigParam(UINT, "LOGIC_ACCUMULATOR_LATENCY");
    const uint64_t pipelines = getConfigParam(UINT, "LOGIC_ACCUMULATOR_PIPELINES");
    uint64_t cycles = transferCycles + latency;
    if (pipelines != 0 && bytes != 0)
    {
        const uint64_t bursts = (bytes + sizeof(BurstType) - 1) / sizeof(BurstType);
        const uint64_t serviceCycles = (bursts + pipelines - 1) / pipelines;
        const uint64_t computeCycles = latency + serviceCycles - 1;
        cycles = max(transferCycles, computeCycles);
    }
    depthwiseAccumulatorTransferCycles_ += cycles;
    const uint64_t overlap = getConfigParam(BOOL, "LOGIC_ACCUMULATOR_OVERLAP")
                                 ? min(cycles, overlap_window)
                                 : 0;
    const uint64_t waitCycles = cycles - overlap;
    depthwiseAccumulatorOverlapCycles_ += overlap;
    depthwiseAccumulatorWaitCycles_ += waitCycles;
    for (uint64_t i = 0; i < waitCycles; i++)
    {
        cycle_++;
        mem_->update();
    }
}

void PIMKernel::addDepthwiseAccumulatorTransactions(int row, int col, int bank, bool final,
                                                     bool flush, int num_loop)
{
    for (int& ch_idx : pim_chans_)
        for (int& ra_idx : pim_ranks_)
        {
            unsigned localRow = row;
            unsigned localCol = col;
            for (int i = 0; i < num_loop; i++)
            {
                const uint64_t address = pim_addr_mgr_->addrGenSafe(
                    ch_idx, ra_idx, 0, bank, localRow, localCol);
                BurstType* payload = &null_bst_;
                if (final)
                {
                    depthwiseAccumulatorWritePayloads_.emplace_back();
                    payload = &depthwiseAccumulatorWritePayloads_.back();
                }
                Transaction* transaction = new Transaction(
                    DATA_WRITE, address,
                    domainTag(final ? "LOGIC_ACCUM_TO_BANK" : "BANK_TO_LOGIC_ACCUM"),
                    payload, WriteCompletionClass::PIM_WRITEBACK);
                transaction->logicAccumulatorDirect = !final;
                transaction->logicAccumulatorFinal = final;
                transaction->logicAccumulatorFlush = flush;
                mem_->addTransaction(transaction);
                localCol++;
            }
        }
    addBarrier();
}

void PIMKernel::computeMulToAccumulator(int tile_start, int tile_count, int input_row,
                                        int weight_row,
                                        int result_row, bool flush_partial, bool final_tap)
{
    for (int tile = tile_start; tile < tile_start + tile_count; tile++)
    {
        const int column = num_grf_ * tile;
        for (int bank = 0; bank < 2; bank++)
        {
            addTransactionAll(false, 0, bank, input_row, column, "BANK_TO_GRF_",
                              &null_bst_, true, num_grf_);
            addTransactionAll(false, 0, bank, weight_row, column, "MUL_ACCUM",
                              &null_bst_, true, num_grf_);
            addDepthwiseAccumulatorTransactions(result_row, column, bank, false,
                                                flush_partial, num_grf_);
        }
        if (final_tap)
            for (int bank = 0; bank < 2; bank++)
                addDepthwiseAccumulatorTransactions(result_row, column, bank, true,
                                                    false, num_grf_);
    }
}

void PIMKernel::executeDepthwiseHierarchical(int dim, unsigned kernel_size,
                                              int input_base_row, int weight_base_row,
                                              int result_row, int tap_row_stride)
{
    if (dim <= 0 || kernel_size == 0 || kernel_size % 2 == 0 || tap_row_stride <= 0)
        throw invalid_argument("Hierarchical depthwise dimensions must be positive with odd kernel");
    if (!getConfigParam(BOOL, "HIERARCHY_SOURCE_QUEUES"))
        throw logic_error("Hierarchical depthwise accumulation requires source queues");
    const unsigned taps = kernel_size * kernel_size;
    const unsigned aggregationTaps =
        getConfigParam(UINT, "BANK_LOCAL_AGGREGATION_TAPS");
    if (aggregationTaps == 0 || taps % aggregationTaps != 0)
        throw invalid_argument(
            "BANK_LOCAL_AGGREGATION_TAPS must be a nonzero divisor of depthwise taps");
    depthwiseAccumulatorWritePayloads_.clear();
    mem_->beginLogicDepthwiseAccumulation(
        taps / aggregationTaps, getConfigParam(UINT, "LOGIC_ACCUMULATOR_ENTRIES"));
    const int numTile = dim / (num_banks_ * num_pim_chans_ * num_pim_ranks_ * num_grf_);
    if (numTile <= 0) throw invalid_argument("Hierarchical depthwise requires at least one tile");
    const unsigned configuredBatch =
        getConfigParam(UINT, "BANK_LOCAL_ACCUMULATOR_TILE_BATCH");
    const int tileBatch = configuredBatch == 0
                              ? numTile
                              : min<int>(static_cast<int>(configuredBatch), numTile);
    const int burstsPerTile =
        num_banks_ * num_pim_chans_ * num_pim_ranks_ * num_grf_;

    for (int tileStart = 0; tileStart < numTile; tileStart += tileBatch)
    {
        const int batchCount = min(tileBatch, numTile - tileStart);
        const int jumps = batchCount - 1;
        vector<PIMCmd> commands = PIMCmdGen::getPIMCmds(KernelType::MUL, jumps, 0, 0);
        for (unsigned tap = 0; tap < taps; tap++)
        {
            const uint64_t tapStartCycle = cycle_;
            setControl(&bst_hab_pim_, true, getToggleCond(pimBankType::ALL_BANK), false,
                       false);
            setControl(&bst_hab_, false, getToggleCond(pimBankType::ALL_BANK), false, false);
            parkIn();
            changePIMMode(dramMode::SB, dramMode::HAB);
            programCrf(commands);
            changePIMMode(dramMode::HAB, dramMode::HAB_PIM);
            const bool flushPartial = (tap + 1) % aggregationTaps == 0;
            computeMulToAccumulator(tileStart, batchCount,
                                    input_base_row + tap * tap_row_stride,
                                    weight_base_row + tap * tap_row_stride, result_row,
                                    flushPartial, tap + 1 == taps);
            changePIMMode(dramMode::HAB_PIM, dramMode::HAB);
            changePIMMode(dramMode::HAB, dramMode::SB);
            parkOut();
            runPIM();
            if (flushPartial)
                advanceDepthwiseAccumulatorTransfer(
                    static_cast<uint64_t>(batchCount) * burstsPerTile * transaction_size_,
                    cycle_ - tapStartCycle);
        }
    }

    if (!mem_->logicDieAccumulator->empty())
        throw logic_error(
            "Hierarchical depthwise left accumulator entries pending: entries=" +
            to_string(mem_->logicDieAccumulator->size()) +
            " partial=" + to_string(mem_->logicDieAccumulator->partialBursts()) +
            " final=" + to_string(mem_->logicDieAccumulator->finalizedBursts()));
}

shared_ptr<DepthwiseLoweredHandle> PIMKernel::beginDepthwiseLowered(
    int dim, unsigned kernel_size, int input_base_row, int weight_base_row, int product_row,
    int accumulator_row, int result_row, int tap_row_stride)
{
    if (dim <= 0 || kernel_size == 0 || kernel_size % 2 == 0 || tap_row_stride <= 0)
        throw invalid_argument("Depthwise lowered dimensions must be positive with odd kernel");
    if (depthwiseLoweredOutstanding_)
        throw logic_error("Only one lowered depthwise handle may be outstanding");
    auto handle = make_shared<DepthwiseLoweredHandle>();
    handle->dim = dim;
    handle->kernelSize = kernel_size;
    handle->inputBaseRow = input_base_row;
    handle->weightBaseRow = weight_base_row;
    handle->productRow = product_row;
    handle->accumulatorRow = accumulator_row;
    handle->resultRow = result_row;
    handle->tapRowStride = tap_row_stride;
    const unsigned taps = kernel_size * kernel_size;
    handle->totalStages = 2 * taps - 1;
    depthwiseLoweredOutstanding_ = true;
    return handle;
}

void PIMKernel::enqueueDepthwiseStage(const shared_ptr<DepthwiseLoweredHandle>& handle)
{
    if (!depthwiseLoweredOutstanding_ || handle == nullptr || handle->complete)
        throw logic_error("Invalid lowered depthwise handle");
    if (handle->stagePending)
        throw logic_error("Previous lowered depthwise stage is still pending");

    unsigned tap = 0;
    bool is_add = false;
    if (handle->nextStage > 0)
    {
        const unsigned stage = handle->nextStage - 1;
        tap = 1 + stage / 2;
        is_add = stage % 2 == 1;
    }
    if (!is_add)
    {
        const int tap_product_row = tap == 0 ? handle->resultRow : handle->productRow;
        executeEltwise(handle->dim, pimBankType::ALL_BANK, KernelType::MUL,
                       handle->inputBaseRow + tap * handle->tapRowStride, tap_product_row,
                       handle->weightBaseRow + tap * handle->tapRowStride);
    }
    else
    {
        const int source_accumulator = tap % 2 == 1 ? handle->resultRow
                                                     : handle->accumulatorRow;
        const int destination_accumulator = tap % 2 == 1 ? handle->accumulatorRow
                                                          : handle->resultRow;
        executeEltwise(handle->dim, pimBankType::ALL_BANK, KernelType::ADD,
                       source_accumulator, destination_accumulator, handle->productRow);
    }
    handle->stagePending = true;
}

void PIMKernel::waitDepthwiseStage(const shared_ptr<DepthwiseLoweredHandle>& handle)
{
    if (!depthwiseLoweredOutstanding_ || handle == nullptr || handle->complete ||
        !handle->stagePending)
        throw logic_error("No pending lowered depthwise stage");
    runPIM();
    handle->stagePending = false;
    handle->nextStage++;
    if (handle->nextStage == handle->totalStages)
    {
        handle->complete = true;
        depthwiseLoweredOutstanding_ = false;
    }
}

void PIMKernel::computeAddOrMul(int num_tile, int input0_row, int result_row, int input1_row)
{
    for (int i = 0; i < num_tile; i++)
    {
        int c = num_grf_ * i;
        for (int b = 0; b < 2; b++)  // for even/odd banks, respectively
        {
            addTransactionAll(false, 0, b, input0_row, c, "BANK_TO_GRF_", &null_bst_, true,
                              num_grf_);
            addTransactionAll(false, 0, b, input1_row, c, "ADD", &null_bst_, true, num_grf_);
            addTransactionAll(true, 0, b, result_row, c, "GRF_TO_BANK", &null_bst_, true,
                              num_grf_, WriteCompletionClass::PIM_WRITEBACK);
        }
    }
}

/*
void PIMKernel::computeBn(int num_tile, int input0_row, int result_row)
{
    for (int ch_idx = 0; ch_idx < num_pim_chans_; ch_idx++)
    {
        for (int ra_idx = 0; ra_idx < num_pim_ranks_; ra_idx++)
        {
            int srf_bst_num = (input0_row != result_row)? (ch_idx * num_pim_ranks_ + ra_idx) : 0;
            mem_->addTransaction(true, pim_addr_mgr_->addrGen(ch_idx, ra_idx, 0, 0, pim_reg_ra_,
                                       0x1), &srf_bst_[srf_bst_num]);
        }
    }
    addBarrier();

    if (input0_row != result_row)
        input0_row = result_row = 0;
    for (int i = 0; i < num_tile; i++)
    {
        for (int b = 0; b < 2; b++) // for even/ddd banks, respectively
        {
            addTransactionAll(false, 0, b, input0_row, num_grf_ * i, "MAD1", &null_bst_,
                              true, num_grf_);
            addTransactionAll(false, 0, b, input0_row, num_grf_ * i, "MAD2", &null_bst_,
                              true, num_grf_);
            addTransactionAll(true , 0, b, result_row, num_grf_ * i, "GRF_TO_BANK", &null_bst_,
                              true, num_grf_, WriteCompletionClass::PIM_WRITEBACK);
        }
    }
}
*/

void PIMKernel::computeRelu(int num_tile, int input0_row, int result_row)
{
    for (int i = 0; i < num_tile; i++)
    {
        int c = num_grf_ * i;
        addTransactionAll(false, 0, 0, input0_row, c, "FILL&ReLU", &null_bst_, true, num_grf_);
        addTransactionAll(true, 0, 0, result_row, c, "GRF_A_TO_EVEN_BANK", &null_bst_, true,
                          num_grf_, WriteCompletionClass::PIM_WRITEBACK);
        addTransactionAll(false, 0, 1, input0_row, c, "FILL&ReLU", &null_bst_, true, num_grf_);
        addTransactionAll(true, 0, 1, result_row, c, "GRF_B_TO_ODD_BANK", &null_bst_, true,
                          num_grf_, WriteCompletionClass::PIM_WRITEBACK);
    }
}

void PIMKernel::readData(BurstType* bst_data, size_t bst_cnt, unsigned starting_row,
                         unsigned starting_col)
{
    uint64_t init_addr = pim_addr_mgr_->addrGenSafe(0, 0, 0, 0, starting_row, starting_col);

    for (uint64_t addr = init_addr, i = 0; i < bst_cnt; addr += transaction_size_, i++)
    {
        mem_->addTransaction(false, addr, &bst_data[i]);
    }
}

void PIMKernel::adderTree(BurstType* result, int output_dim, int num_tile, int step, fp16* temp)
{
    if (num_tile == 1)
        return;

    int iter = num_tile / 2;
    if (step == 0)
    {
        for (int i = 0; i < iter; i++)
        {
            temp[i] = result[2 * i * output_dim].fp16AdderTree() +
                      result[(2 * i + 1) * output_dim].fp16AdderTree();
        }
    }
    else
    {
        for (int i = 0; i < iter; i++) temp[i] = temp[i * 2] + temp[i * 2 + 1];

        if (num_tile % 2 == 1)
            temp[iter] = temp[num_tile];
    }

    adderTree(result, output_dim, ceil(double(num_tile) / (double)2), step + 1, temp);

    return;
}
