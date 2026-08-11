#ifndef LOGIC_DIE_SCHEDULER_H
#define LOGIC_DIE_SCHEDULER_H

#include <algorithm>
#include <cstdint>
#include <limits>
#include <queue>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace DRAMSim
{
struct LogicDieReservation
{
    uint64_t queueCycles;
    uint64_t computeCycles;
    uint64_t transferBytes;
    uint64_t transferCycles;
    uint64_t serviceCycles;
    uint64_t completionDelay;
    uint64_t dispatchOverheadCycles;
    bool commandCoalesced;
};

struct LogicDieReservationEvent
{
    uint64_t arrivalCycle;
    uint64_t serviceStartCycle;
    uint64_t completionCycle;
    uint64_t dispatchSignature;
    uint64_t streamId;
    uint64_t epochId;
    uint64_t commandOrdinal;
    uint64_t blocks;
    uint64_t queueCycles;
    uint64_t computeCycles;
    uint64_t transferBytes;
    uint64_t transferCycles;
    uint64_t serviceCycles;
    bool commandCoalesced;
};

struct LogicCommandContext
{
    uint64_t epochId = 0;
    uint64_t commandOrdinal = 0;
    uint64_t streamId = 0;
    bool valid = false;
};

struct LogicBroadcastMaskState
{
    std::unordered_set<uint64_t> streams;
    uint64_t firstArrivalCycle = 0;
    uint64_t lastArrivalCycle = 0;
};

struct LogicEpochStats
{
    uint64_t epochId = 0;
    uint64_t expectedStreams = 0;
    uint64_t observedStreams = 0;
    uint64_t maskCount = 0;
    uint64_t totalFanout = 0;
    uint64_t minFanout = 0;
    uint64_t maxFanout = 0;
    uint64_t totalResidencyCycles = 0;
    uint64_t maxResidencyCycles = 0;
    uint64_t peakOpenMasks = 0;
    uint64_t onlinePeakOpenMasks = 0;
    uint64_t onlineQueueFullEvents = 0;
    uint64_t incompleteExpectedMasks = 0;
    bool readyMaskComplete = false;
};

struct LogicQueueBackpressure
{
    uint64_t stallCycles = 0;
    uint64_t fullEvents = 0;
};

struct HierarchyActivityStats
{
    uint64_t bankIssues = 0;
    uint64_t logicIssues = 0;
    uint64_t bankFirstIssue = 0;
    uint64_t bankLastIssue = 0;
    uint64_t logicFirstIssue = 0;
    uint64_t logicLastIssue = 0;
    uint64_t overlappingIssueCycles = 0;
    uint64_t overlappingWindowCycles = 0;
};

class LogicDieScheduler
{
  public:
    LogicDieScheduler()
        : busyUntil_(0),
          commandCount_(0),
          queueCycles_(0),
          computeCycles_(0),
          transferBytes_(0),
          transferCycles_(0),
          serviceCycles_(0),
          dispatchCount_(0),
          coalescedCommandCount_(0),
          dispatchOverheadCycles_(0),
          lastDispatchCycle_(std::numeric_limits<uint64_t>::max()),
          lastDispatchSignature_(0),
          releaseEpoch_(0),
          releaseEpochActive_(false),
          maxReleaseStreams_(0),
          expectedReleaseStreams_(0),
          completedReadyMasks_(0),
          incompleteReadyMasks_(0),
          finalizedBroadcastMasks_(0),
          finalizedBroadcastFanout_(0),
          minBroadcastFanout_(std::numeric_limits<uint64_t>::max()),
          maxBroadcastFanout_(0),
          lastBackpressureEpoch_(0),
          broadcastQueueStallCycles_(0),
          broadcastQueueFullEvents_(0)
    {
    }

    LogicDieReservation reserve(uint64_t currentCycle, uint64_t blocks, uint64_t units,
                                uint64_t latency, uint64_t bytesPerCycle,
                                uint64_t bytesPerBlock, uint64_t dispatchSignature,
                                uint64_t commandOverhead, bool coalescingEnabled,
                                LogicCommandContext context = LogicCommandContext())
    {
        const uint64_t totalUnits = std::max<uint64_t>(1, units);
        const uint64_t unitsPerCommand = std::min(totalUnits, blocks);
        const uint64_t parallelLanes = std::max<uint64_t>(1, totalUnits / blocks);
        if (laneBusyUntil_.size() != parallelLanes)
            laneBusyUntil_.assign(parallelLanes, 0);
        const uint64_t waves = (blocks + unitsPerCommand - 1) / unitsPerCommand;
        const uint64_t compute = waves * latency;
        const uint64_t bytes = blocks * bytesPerBlock;
        const uint64_t transfer =
            bytesPerCycle == 0 ? 0 : (bytes + bytesPerCycle - 1) / bytesPerCycle;
        bool coalesced = coalescingEnabled && currentCycle == lastDispatchCycle_ &&
                         dispatchSignature == lastDispatchSignature_;
        if (coalescingEnabled && context.valid && releaseEpochActive_ &&
            context.epochId == releaseEpoch_)
        {
            const uint64_t key = (context.commandOrdinal << 32) ^
                                 (dispatchSignature & 0xffffffffULL);
            auto& mask = epochDispatchMasks_[key];
            coalesced = !mask.streams.empty();
            if (mask.streams.empty())
            {
                mask.firstArrivalCycle = currentCycle;
                onlineOpenMasks_.insert(key);
                onlinePeakOpenMasks_ =
                    std::max<uint64_t>(onlinePeakOpenMasks_, onlineOpenMasks_.size());
                if (broadcastQueueDepth_ > 0 && onlineOpenMasks_.size() > broadcastQueueDepth_ &&
                    !onlineQueueWasFull_)
                    onlineQueueFullEvents_++;
            }
            mask.lastArrivalCycle = currentCycle;
            mask.streams.insert(context.streamId);
            const auto expected = expectedOrdinalMasks_.find(context.commandOrdinal);
            if (expected != expectedOrdinalMasks_.end() &&
                mask.streams.size() == expected->second.size())
            {
                bool exactMask = true;
                for (uint64_t expectedStream : expected->second)
                    if (mask.streams.find(expectedStream) == mask.streams.end())
                    {
                        exactMask = false;
                        break;
                    }
                if (exactMask) onlineOpenMasks_.erase(key);
            }
            onlineQueueWasFull_ = broadcastQueueDepth_ > 0 &&
                                  onlineOpenMasks_.size() > broadcastQueueDepth_;
            releaseStreams_.insert(context.streamId);
            maxReleaseStreams_ = std::max<uint64_t>(maxReleaseStreams_, releaseStreams_.size());
        }
        const uint64_t dispatchOverhead = coalesced ? 0 : commandOverhead;
        const uint64_t service = std::max(compute, transfer) + dispatchOverhead;
        const auto lane =
            std::min_element(laneBusyUntil_.begin(), laneBusyUntil_.end());
        const uint64_t start = std::max(currentCycle, *lane);
        const uint64_t queue = start - currentCycle;
        *lane = start + service;
        busyUntil_ = *std::max_element(laneBusyUntil_.begin(), laneBusyUntil_.end());

        commandCount_++;
        if (context.valid) issuedCommandsPerStream_[context.streamId]++;
        queueCycles_ += queue;
        computeCycles_ += compute;
        transferBytes_ += bytes;
        transferCycles_ += transfer;
        serviceCycles_ += service;
        dispatchOverheadCycles_ += dispatchOverhead;
        if (coalesced)
            coalescedCommandCount_++;
        else
            dispatchCount_++;
        lastDispatchCycle_ = currentCycle;
        lastDispatchSignature_ = dispatchSignature;
        reservationEvents_.push_back(
            {currentCycle, start, start + service, dispatchSignature,
             context.valid ? context.streamId : 0, context.valid ? context.epochId : 0,
             context.valid ? context.commandOrdinal : 0, blocks, queue, compute, bytes,
             transfer, service, coalesced});
        if (start > currentCycle) waitingReservationStarts_.push(start);
        return {queue, compute, bytes, transfer, service, queue + service, dispatchOverhead,
                coalesced};
    }

    bool isBusy(uint64_t cycle) const { return cycle < busyUntil_; }
    uint64_t getBusyUntil() const { return busyUntil_; }
    uint64_t getCommandCount() const { return commandCount_; }
    uint64_t getQueueCycles() const { return queueCycles_; }
    uint64_t getComputeCycles() const { return computeCycles_; }
    uint64_t getTransferBytes() const { return transferBytes_; }
    uint64_t getTransferCycles() const { return transferCycles_; }
    uint64_t getServiceCycles() const { return serviceCycles_; }
    uint64_t getDispatchCount() const { return dispatchCount_; }
    uint64_t getCoalescedCommandCount() const { return coalescedCommandCount_; }
    uint64_t getDispatchOverheadCycles() const { return dispatchOverheadCycles_; }
    const std::vector<LogicDieReservationEvent>& getReservationEvents() const
    {
        return reservationEvents_;
    }
    void resetHierarchyActivity()
    {
        bankIssueCycles_.clear();
        logicIssueCycles_.clear();
        bankIssueCount_ = 0;
        logicIssueCount_ = 0;
    }
    void recordHierarchyIssue(bool logic_die, uint64_t cycle)
    {
        if (logic_die)
        {
            logicIssueCount_++;
            logicIssueCycles_.insert(cycle);
        }
        else
        {
            bankIssueCount_++;
            bankIssueCycles_.insert(cycle);
        }
    }
    HierarchyActivityStats getHierarchyActivityStats() const
    {
        HierarchyActivityStats stats;
        stats.bankIssues = bankIssueCount_;
        stats.logicIssues = logicIssueCount_;
        if (!bankIssueCycles_.empty())
        {
            stats.bankFirstIssue = *std::min_element(bankIssueCycles_.begin(), bankIssueCycles_.end());
            stats.bankLastIssue = *std::max_element(bankIssueCycles_.begin(), bankIssueCycles_.end());
        }
        if (!logicIssueCycles_.empty())
        {
            stats.logicFirstIssue = *std::min_element(logicIssueCycles_.begin(), logicIssueCycles_.end());
            stats.logicLastIssue = *std::max_element(logicIssueCycles_.begin(), logicIssueCycles_.end());
        }
        for (uint64_t cycle : bankIssueCycles_)
            if (logicIssueCycles_.count(cycle) != 0) stats.overlappingIssueCycles++;
        if (!bankIssueCycles_.empty() && !logicIssueCycles_.empty())
        {
            const uint64_t first = std::max(stats.bankFirstIssue, stats.logicFirstIssue);
            const uint64_t last = std::min(stats.bankLastIssue, stats.logicLastIssue);
            if (last >= first) stats.overlappingWindowCycles = last - first + 1;
        }
        return stats;
    }
    void beginReleaseEpoch(uint64_t expectedStreams = 0,
                           const std::vector<std::pair<uint64_t, uint64_t>>& streamOrdinals = {},
                           uint64_t broadcastQueueDepth = 0)
    {
        finalizeReleaseEpoch();
        releaseEpoch_++;
        releaseEpochActive_ = true;
        expectedReleaseStreams_ = expectedStreams;
        broadcastQueueDepth_ = broadcastQueueDepth;
        epochDispatchMasks_.clear();
        releaseStreams_.clear();
        expectedOrdinalMasks_.clear();
        onlineOpenMasks_.clear();
        onlinePeakOpenMasks_ = 0;
        onlineQueueFullEvents_ = 0;
        onlineQueueWasFull_ = false;
        for (const auto& stream : streamOrdinals)
            for (uint64_t ordinal = 0; ordinal < stream.second; ordinal++)
                expectedOrdinalMasks_[ordinal].insert(stream.first);
    }
    uint64_t getReleaseEpochCount() const { return releaseEpoch_; }
    uint64_t getMaxReleaseStreams() const { return maxReleaseStreams_; }
    uint64_t getCompletedReadyMasks() const
    {
        return completedReadyMasks_ + (currentReadyMaskComplete() ? 1 : 0);
    }
    uint64_t getIncompleteReadyMasks() const
    {
        return incompleteReadyMasks_ +
               (releaseEpochActive_ && !currentReadyMaskComplete() ? 1 : 0);
    }
    uint64_t getBroadcastMaskCount() const
    {
        return finalizedBroadcastMasks_ + epochDispatchMasks_.size();
    }
    uint64_t getBroadcastFanout() const
    {
        uint64_t total = finalizedBroadcastFanout_;
        for (const auto& mask : epochDispatchMasks_) total += mask.second.streams.size();
        return total;
    }
    uint64_t getMinBroadcastFanout() const
    {
        uint64_t minimum = minBroadcastFanout_;
        for (const auto& mask : epochDispatchMasks_)
            minimum = std::min<uint64_t>(minimum, mask.second.streams.size());
        return minimum == std::numeric_limits<uint64_t>::max() ? 0 : minimum;
    }
    uint64_t getMaxBroadcastFanout() const
    {
        uint64_t maximum = maxBroadcastFanout_;
        for (const auto& mask : epochDispatchMasks_)
            maximum = std::max<uint64_t>(maximum, mask.second.streams.size());
        return maximum;
    }
    LogicEpochStats getEpochStats(uint64_t epochId) const
    {
        if (releaseEpochActive_ && epochId == releaseEpoch_) return buildCurrentEpochStats();
        for (const auto& stats : epochStats_)
            if (stats.epochId == epochId) return stats;
        return LogicEpochStats();
    }
    LogicQueueBackpressure applyBroadcastQueueDepth(uint64_t depth)
    {
        LogicQueueBackpressure result;
        if (!releaseEpochActive_ || depth == 0 || lastBackpressureEpoch_ == releaseEpoch_)
            return result;
        lastBackpressureEpoch_ = releaseEpoch_;

        std::vector<std::pair<uint64_t, uint64_t>> intervals;
        intervals.reserve(epochDispatchMasks_.size());
        for (const auto& item : epochDispatchMasks_)
            intervals.push_back({item.second.firstArrivalCycle, item.second.lastArrivalCycle});
        std::sort(intervals.begin(), intervals.end());

        std::priority_queue<uint64_t, std::vector<uint64_t>, std::greater<uint64_t>> openUntil;
        uint64_t accumulatedStall = 0;
        for (const auto& interval : intervals)
        {
            uint64_t start = interval.first + accumulatedStall;
            uint64_t end = interval.second + accumulatedStall;
            while (!openUntil.empty() && openUntil.top() < start) openUntil.pop();
            if (openUntil.size() >= depth)
            {
                const uint64_t stall = openUntil.top() - start + 1;
                accumulatedStall += stall;
                result.stallCycles += stall;
                result.fullEvents++;
                start += stall;
                end += stall;
                while (!openUntil.empty() && openUntil.top() < start) openUntil.pop();
            }
            openUntil.push(end);
        }
        broadcastQueueStallCycles_ += result.stallCycles;
        broadcastQueueFullEvents_ += result.fullEvents;
        return result;
    }
    uint64_t getBroadcastQueueStallCycles() const { return broadcastQueueStallCycles_; }
    uint64_t getBroadcastQueueFullEvents() const { return broadcastQueueFullEvents_; }
    bool canAccept(uint64_t dispatchSignature, const LogicCommandContext& context,
                   uint64_t currentCycle = 0, uint64_t pcuQueueDepth = 0,
                   uint64_t distributedAdmissionBurst = 1)
    {
        while (!waitingReservationStarts_.empty() &&
               waitingReservationStarts_.top() <= currentCycle)
            waitingReservationStarts_.pop();
        bool broadcastAccepted = true;
        if (context.valid && broadcastQueueDepth_ != 0)
        {
            const uint64_t key = (context.commandOrdinal << 32) ^
                                 (dispatchSignature & 0xffffffffULL);
            broadcastAccepted = onlineOpenMasks_.find(key) != onlineOpenMasks_.end() ||
                                onlineOpenMasks_.size() < broadcastQueueDepth_;
        }
        if (!broadcastAccepted) return false;
        if (pcuQueueDepth > 0)
        {
            const uint64_t burst = std::max<uint64_t>(1, distributedAdmissionBurst);
            const uint64_t lowWatermark = pcuQueueDepth >= burst
                                              ? pcuQueueDepth - burst + 1
                                              : 1;
            if (waitingReservationStarts_.size() >= lowWatermark) return false;
        }
        return true;
    }
    void recordOnlineIssueStall(uint64_t streamId, uint64_t cycle)
    {
        onlineIssueStallCycles_++;
        blockedCyclesPerStream_[streamId]++;
        blockedWallCycles_.insert(cycle);
        if (isBusy(cycle)) onlineIssueBusyOverlapCycles_++;
    }
    uint64_t getOnlineIssueStallCycles() const { return onlineIssueStallCycles_; }
    uint64_t getOnlineIssueBusyOverlapCycles() const { return onlineIssueBusyOverlapCycles_; }
    uint64_t getBlockedWallCycles() const { return blockedWallCycles_.size(); }
    uint64_t getBlockedStreamCount() const { return blockedCyclesPerStream_.size(); }
    uint64_t getMinBlockedCyclesPerStream() const
    {
        uint64_t minimum = std::numeric_limits<uint64_t>::max();
        for (const auto& stream : blockedCyclesPerStream_)
            minimum = std::min(minimum, stream.second);
        return minimum == std::numeric_limits<uint64_t>::max() ? 0 : minimum;
    }
    uint64_t getMaxBlockedCyclesPerStream() const
    {
        uint64_t maximum = 0;
        for (const auto& stream : blockedCyclesPerStream_)
            maximum = std::max(maximum, stream.second);
        return maximum;
    }
    uint64_t getMinIssuedCommandsPerStream() const
    {
        uint64_t minimum = std::numeric_limits<uint64_t>::max();
        for (const auto& stream : issuedCommandsPerStream_)
            minimum = std::min(minimum, stream.second);
        return minimum == std::numeric_limits<uint64_t>::max() ? 0 : minimum;
    }
    uint64_t getMaxIssuedCommandsPerStream() const
    {
        uint64_t maximum = 0;
        for (const auto& stream : issuedCommandsPerStream_)
            maximum = std::max(maximum, stream.second);
        return maximum;
    }
    uint64_t getBlockedStreamMaskLow() const
    {
        uint64_t mask = 0;
        for (const auto& stream : blockedCyclesPerStream_)
            if (stream.first < 64) mask |= uint64_t(1) << stream.first;
        return mask;
    }
    uint64_t getBlockedStreamMaskHigh() const
    {
        uint64_t mask = 0;
        for (const auto& stream : blockedCyclesPerStream_)
            if (stream.first >= 64 && stream.first < 128)
                mask |= uint64_t(1) << (stream.first - 64);
        return mask;
    }

    void submitCentralRequest(uint64_t streamId)
    {
        centralRequests_.insert(streamId);
    }

    uint64_t buildCentralGrants(uint64_t currentCycle, uint64_t queueDepth,
                                uint64_t streamCount)
    {
        while (!waitingReservationStarts_.empty() &&
               waitingReservationStarts_.top() <= currentCycle)
            waitingReservationStarts_.pop();

        centralGrants_.clear();
        if (centralRequests_.empty() || queueDepth == 0 || streamCount == 0)
        {
            centralRequests_.clear();
            return 0;
        }

        const uint64_t occupied = waitingReservationStarts_.size();
        const uint64_t available = occupied < queueDepth ? queueDepth - occupied : 0;
        if (available == 0)
        {
            centralRequests_.clear();
            return 0;
        }

        std::vector<uint64_t> orderedRequests(centralRequests_.begin(),
                                              centralRequests_.end());
        std::sort(orderedRequests.begin(), orderedRequests.end());
        auto start = std::lower_bound(orderedRequests.begin(), orderedRequests.end(),
                                      centralRoundRobinCursor_);
        const size_t startIndex = start == orderedRequests.end()
                                      ? 0
                                      : static_cast<size_t>(start - orderedRequests.begin());
        const uint64_t grantCount =
            std::min<uint64_t>(available, orderedRequests.size());
        uint64_t lastGranted = 0;
        for (uint64_t offset = 0; offset < grantCount; offset++)
        {
            lastGranted = orderedRequests[(startIndex + offset) % orderedRequests.size()];
            centralGrants_.insert(lastGranted);
        }
        centralRoundRobinCursor_ = (lastGranted + 1) % streamCount;
        centralRequests_.clear();
        centralGrantBuilds_++;
        centralGrantedRequests_ += grantCount;
        return grantCount;
    }

    bool hasCentralGrant(uint64_t streamId) const
    {
        return centralGrants_.find(streamId) != centralGrants_.end();
    }

    bool consumeCentralGrant(uint64_t streamId)
    {
        return centralGrants_.erase(streamId) != 0;
    }

    uint64_t getCentralGrantBuilds() const { return centralGrantBuilds_; }
    uint64_t getCentralGrantedRequests() const { return centralGrantedRequests_; }

  private:
    uint64_t busyUntil_;
    uint64_t commandCount_;
    uint64_t queueCycles_;
    uint64_t computeCycles_;
    uint64_t transferBytes_;
    uint64_t transferCycles_;
    uint64_t serviceCycles_;
    std::vector<uint64_t> laneBusyUntil_;
    uint64_t dispatchCount_;
    uint64_t coalescedCommandCount_;
    uint64_t dispatchOverheadCycles_;
    uint64_t lastDispatchCycle_;
    uint64_t lastDispatchSignature_;
    uint64_t releaseEpoch_;
    bool releaseEpochActive_;
    uint64_t maxReleaseStreams_;
    uint64_t expectedReleaseStreams_;
    uint64_t completedReadyMasks_;
    uint64_t incompleteReadyMasks_;
    uint64_t finalizedBroadcastMasks_;
    uint64_t finalizedBroadcastFanout_;
    uint64_t minBroadcastFanout_;
    uint64_t maxBroadcastFanout_;
    std::unordered_map<uint64_t, LogicBroadcastMaskState> epochDispatchMasks_;
    std::unordered_set<uint64_t> releaseStreams_;
    std::vector<LogicEpochStats> epochStats_;
    std::unordered_map<uint64_t, std::unordered_set<uint64_t>> expectedOrdinalMasks_;
    std::unordered_set<uint64_t> onlineOpenMasks_;
    uint64_t onlinePeakOpenMasks_ = 0;
    uint64_t onlineQueueFullEvents_ = 0;
    uint64_t broadcastQueueDepth_ = 0;
    bool onlineQueueWasFull_ = false;
    uint64_t onlineIssueStallCycles_ = 0;
    uint64_t onlineIssueBusyOverlapCycles_ = 0;
    std::unordered_map<uint64_t, uint64_t> blockedCyclesPerStream_;
    std::unordered_map<uint64_t, uint64_t> issuedCommandsPerStream_;
    std::unordered_set<uint64_t> blockedWallCycles_;
    uint64_t lastBackpressureEpoch_;
    uint64_t broadcastQueueStallCycles_;
    uint64_t broadcastQueueFullEvents_;
    uint64_t bankIssueCount_ = 0;
    uint64_t logicIssueCount_ = 0;
    std::unordered_set<uint64_t> bankIssueCycles_;
    std::unordered_set<uint64_t> logicIssueCycles_;
    std::vector<LogicDieReservationEvent> reservationEvents_;
    std::priority_queue<uint64_t, std::vector<uint64_t>, std::greater<uint64_t>>
        waitingReservationStarts_;
    std::unordered_set<uint64_t> centralRequests_;
    std::unordered_set<uint64_t> centralGrants_;
    uint64_t centralRoundRobinCursor_ = 0;
    uint64_t centralGrantBuilds_ = 0;
    uint64_t centralGrantedRequests_ = 0;

    bool currentReadyMaskComplete() const
    {
        return releaseEpochActive_ && expectedReleaseStreams_ > 0 &&
               releaseStreams_.size() == expectedReleaseStreams_;
    }
    void finalizeReleaseEpoch()
    {
        if (!releaseEpochActive_) return;
        if (currentReadyMaskComplete())
            completedReadyMasks_++;
        else
            incompleteReadyMasks_++;
        const LogicEpochStats stats = buildCurrentEpochStats();
        epochStats_.push_back(stats);
        finalizedBroadcastMasks_ += epochDispatchMasks_.size();
        for (const auto& mask : epochDispatchMasks_)
        {
            finalizedBroadcastFanout_ += mask.second.streams.size();
            minBroadcastFanout_ =
                std::min<uint64_t>(minBroadcastFanout_, mask.second.streams.size());
            maxBroadcastFanout_ =
                std::max<uint64_t>(maxBroadcastFanout_, mask.second.streams.size());
        }
    }

    LogicEpochStats buildCurrentEpochStats() const
    {
        LogicEpochStats stats;
        stats.epochId = releaseEpoch_;
        stats.expectedStreams = expectedReleaseStreams_;
        stats.observedStreams = releaseStreams_.size();
        stats.maskCount = epochDispatchMasks_.size();
        stats.minFanout = std::numeric_limits<uint64_t>::max();
        stats.readyMaskComplete = currentReadyMaskComplete();
        stats.onlinePeakOpenMasks = onlinePeakOpenMasks_;
        stats.onlineQueueFullEvents = onlineQueueFullEvents_;
        std::vector<std::pair<uint64_t, int>> events;
        events.reserve(epochDispatchMasks_.size() * 2);
        for (const auto& item : epochDispatchMasks_)
        {
            const auto& mask = item.second;
            const uint64_t fanout = mask.streams.size();
            const uint64_t residency = mask.lastArrivalCycle - mask.firstArrivalCycle;
            stats.totalFanout += fanout;
            stats.minFanout = std::min(stats.minFanout, fanout);
            stats.maxFanout = std::max(stats.maxFanout, fanout);
            stats.totalResidencyCycles += residency;
            stats.maxResidencyCycles = std::max(stats.maxResidencyCycles, residency);
            events.push_back({mask.firstArrivalCycle, 1});
            events.push_back({mask.lastArrivalCycle, -1});
        }
        if (stats.maskCount == 0) stats.minFanout = 0;
        stats.incompleteExpectedMasks = onlineOpenMasks_.size();
        std::sort(events.begin(), events.end(), [](const auto& lhs, const auto& rhs) {
            return lhs.first != rhs.first ? lhs.first < rhs.first : lhs.second > rhs.second;
        });
        uint64_t open = 0;
        for (const auto& event : events)
        {
            if (event.second > 0)
            {
                open++;
                stats.peakOpenMasks = std::max(stats.peakOpenMasks, open);
            }
            else if (open > 0)
                open--;
        }
        return stats;
    }
};
}  // namespace DRAMSim

#endif
