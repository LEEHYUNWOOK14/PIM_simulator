#ifndef HIERARCHY_PIM_ARBITER_H
#define HIERARCHY_PIM_ARBITER_H

#include <algorithm>
#include <cstdint>
#include <deque>

namespace DRAMSim
{
enum class HierarchyRequestSource
{
    BANK_SIDE,
    LOGIC_DIE
};

enum class HierarchyArbitrationPolicy
{
    BANK_PRIORITY,
    LOGIC_PRIORITY,
    ROUND_ROBIN,
    READY_BYPASS
};

struct HierarchyPIMRequest
{
    HierarchyRequestSource source;
    uint64_t arrivalCycle;
    uint64_t serviceCycles;
    uint64_t id;
};

struct HierarchyPIMArbiterStats
{
    uint64_t bankIssued = 0;
    uint64_t logicIssued = 0;
    uint64_t bankWaitCycles = 0;
    uint64_t logicWaitCycles = 0;
    uint64_t bankMaxWaitCycles = 0;
    uint64_t logicMaxWaitCycles = 0;
    uint64_t readyBypasses = 0;
    uint64_t arbitrationStallCycles = 0;
};

class HierarchyPIMArbiter
{
  public:
    explicit HierarchyPIMArbiter(HierarchyArbitrationPolicy policy)
        : policy_(policy), busyUntil_(0), lastIssued_(HierarchyRequestSource::LOGIC_DIE),
          hasIssued_(false)
    {
    }

    void enqueue(const HierarchyPIMRequest& request)
    {
        if (request.source == HierarchyRequestSource::BANK_SIDE)
            bankQueue_.push_back(request);
        else
            logicQueue_.push_back(request);
    }

    bool issue(uint64_t cycle, bool bankReady, bool logicReady,
               HierarchyPIMRequest* issued = nullptr)
    {
        if (cycle < busyUntil_) return false;
        const bool bankAvailable = available(bankQueue_, cycle);
        const bool logicAvailable = available(logicQueue_, cycle);
        const bool bankCanIssue = bankAvailable && bankReady;
        const bool logicCanIssue = logicAvailable && logicReady;
        const auto source = select(bankAvailable, logicAvailable, bankCanIssue, logicCanIssue);
        if (!source.hasValue)
        {
            if (bankAvailable || logicAvailable) stats_.arbitrationStallCycles++;
            return false;
        }

        auto& queue = source.value == HierarchyRequestSource::BANK_SIDE ? bankQueue_ : logicQueue_;
        const HierarchyPIMRequest request = queue.front();
        queue.pop_front();
        const uint64_t wait = cycle - request.arrivalCycle;
        if (request.source == HierarchyRequestSource::BANK_SIDE)
        {
            stats_.bankIssued++;
            stats_.bankWaitCycles += wait;
            stats_.bankMaxWaitCycles = std::max(stats_.bankMaxWaitCycles, wait);
        }
        else
        {
            stats_.logicIssued++;
            stats_.logicWaitCycles += wait;
            stats_.logicMaxWaitCycles = std::max(stats_.logicMaxWaitCycles, wait);
        }
        busyUntil_ = cycle + std::max<uint64_t>(1, request.serviceCycles);
        lastIssued_ = request.source;
        hasIssued_ = true;
        if (issued != nullptr) *issued = request;
        return true;
    }

    bool empty() const { return bankQueue_.empty() && logicQueue_.empty(); }
    uint64_t getBusyUntil() const { return busyUntil_; }
    const HierarchyPIMArbiterStats& getStats() const { return stats_; }

  private:
    struct Selection
    {
        bool hasValue;
        HierarchyRequestSource value;
    };

    static bool available(const std::deque<HierarchyPIMRequest>& queue, uint64_t cycle)
    {
        return !queue.empty() && queue.front().arrivalCycle <= cycle;
    }

    Selection select(bool bankAvailable, bool logicAvailable, bool bankCanIssue,
                     bool logicCanIssue)
    {
        if (policy_ == HierarchyArbitrationPolicy::BANK_PRIORITY)
        {
            if (bankCanIssue) return {true, HierarchyRequestSource::BANK_SIDE};
            if (logicCanIssue) return {true, HierarchyRequestSource::LOGIC_DIE};
            return {false, HierarchyRequestSource::BANK_SIDE};
        }
        if (policy_ == HierarchyArbitrationPolicy::LOGIC_PRIORITY)
        {
            if (logicCanIssue) return {true, HierarchyRequestSource::LOGIC_DIE};
            if (bankCanIssue) return {true, HierarchyRequestSource::BANK_SIDE};
            return {false, HierarchyRequestSource::BANK_SIDE};
        }

        const HierarchyRequestSource preferred =
            !hasIssued_ || lastIssued_ == HierarchyRequestSource::LOGIC_DIE
                ? HierarchyRequestSource::BANK_SIDE
                : HierarchyRequestSource::LOGIC_DIE;
        const bool preferredAvailable = preferred == HierarchyRequestSource::BANK_SIDE
                                            ? bankAvailable
                                            : logicAvailable;
        const bool preferredReady = preferred == HierarchyRequestSource::BANK_SIDE
                                        ? bankCanIssue
                                        : logicCanIssue;
        const bool alternateReady = preferred == HierarchyRequestSource::BANK_SIDE
                                        ? logicCanIssue
                                        : bankCanIssue;
        const HierarchyRequestSource alternate = preferred == HierarchyRequestSource::BANK_SIDE
                                                     ? HierarchyRequestSource::LOGIC_DIE
                                                     : HierarchyRequestSource::BANK_SIDE;
        if (preferredReady) return {true, preferred};
        if (!preferredAvailable && alternateReady) return {true, alternate};
        if (policy_ == HierarchyArbitrationPolicy::READY_BYPASS && alternateReady)
        {
            stats_.readyBypasses++;
            return {true, alternate};
        }
        return {false, preferred};
    }

    HierarchyArbitrationPolicy policy_;
    std::deque<HierarchyPIMRequest> bankQueue_;
    std::deque<HierarchyPIMRequest> logicQueue_;
    uint64_t busyUntil_;
    HierarchyRequestSource lastIssued_;
    bool hasIssued_;
    HierarchyPIMArbiterStats stats_;
};
}  // namespace DRAMSim

#endif
