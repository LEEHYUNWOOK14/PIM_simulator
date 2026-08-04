#ifndef LOGIC_DIE_SCHEDULER_H
#define LOGIC_DIE_SCHEDULER_H

#include <algorithm>
#include <cstdint>
#include <limits>
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
          lastDispatchSignature_(0)
    {
    }

    LogicDieReservation reserve(uint64_t currentCycle, uint64_t blocks, uint64_t units,
                                uint64_t latency, uint64_t bytesPerCycle,
                                uint64_t bytesPerBlock, uint64_t dispatchSignature,
                                uint64_t commandOverhead, bool coalescingEnabled)
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
        const bool coalesced = coalescingEnabled && currentCycle == lastDispatchCycle_ &&
                               dispatchSignature == lastDispatchSignature_;
        const uint64_t dispatchOverhead = coalesced ? 0 : commandOverhead;
        const uint64_t service = std::max(compute, transfer) + dispatchOverhead;
        const auto lane =
            std::min_element(laneBusyUntil_.begin(), laneBusyUntil_.end());
        const uint64_t start = std::max(currentCycle, *lane);
        const uint64_t queue = start - currentCycle;
        *lane = start + service;
        busyUntil_ = *std::max_element(laneBusyUntil_.begin(), laneBusyUntil_.end());

        commandCount_++;
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
};
}  // namespace DRAMSim

#endif
