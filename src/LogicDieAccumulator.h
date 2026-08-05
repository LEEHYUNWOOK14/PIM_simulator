#ifndef LOGIC_DIE_ACCUMULATOR_H
#define LOGIC_DIE_ACCUMULATOR_H

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <stdexcept>
#include <unordered_map>
#include <vector>

#include "Burst.h"

namespace DRAMSim
{
class LogicDieAccumulator
{
  public:
    struct ArrivalEvent
    {
        uint64_t cycle;
        unsigned channel;
        unsigned rank;
        unsigned pimBlock;
        uint64_t key;
        unsigned tapIndex;
        BurstType partial;
    };

    struct LinkReplayStats
    {
        uint64_t bursts = 0;
        uint64_t bytes = 0;
        uint64_t firstArrival = 0;
        uint64_t lastArrival = 0;
        uint64_t completionCycle = 0;
        uint64_t replayCycles = 0;
        uint64_t fullCycles = 0;
        uint64_t partialCycles = 0;
        uint64_t idleCycles = 0;
    };
    static uint64_t makeKey(unsigned channel, unsigned rank, unsigned pimBlock,
                            unsigned bankParity, unsigned row, unsigned column)
    {
        if (channel >= 256 || rank >= 16 || pimBlock >= 16 || bankParity >= 2 ||
            row >= (1u << 16) || column >= (1u << 16))
            throw std::out_of_range("Logic accumulator key field exceeds packed width");
        return (static_cast<uint64_t>(channel) << 41) |
               (static_cast<uint64_t>(rank) << 37) |
               (static_cast<uint64_t>(pimBlock) << 33) |
               (static_cast<uint64_t>(bankParity) << 32) |
               (static_cast<uint64_t>(row) << 16) | column;
    }

    void beginLayer(unsigned expectedTaps, size_t capacityEntries = 0)
    {
        if (expectedTaps == 0) throw std::invalid_argument("Accumulator layer needs taps");
        entries_.clear();
        tapCounts_.clear();
        expectedTaps_ = expectedTaps;
        capacityEntries_ = capacityEntries;
        partialBursts_ = 0;
        finalizedBursts_ = 0;
        peakEntries_ = 0;
        arrivalEvents_.clear();
        finalizedResults_.clear();
    }

    void accumulate(uint64_t key, const BurstType& partial)
    {
        if (expectedTaps_ == 0)
            throw std::logic_error("Logic accumulator layer was not initialized");
        BurstType& destination = entries_[key];
        if (capacityEntries_ != 0 && entries_.size() > capacityEntries_)
        {
            entries_.erase(key);
            throw std::overflow_error("Logic accumulator capacity exceeded");
        }
        for (unsigned lane = 0; lane < 16; lane++)
            destination.fp16Data_[lane] = destination.fp16Data_[lane] + partial.fp16Data_[lane];
        tapCounts_[key]++;
        partialBursts_++;
        peakEntries_ = std::max<uint64_t>(peakEntries_, entries_.size());
    }

    void recordArrival(uint64_t cycle, unsigned channel, unsigned rank, unsigned pimBlock,
                       uint64_t key, const BurstType& partial)
    {
        const auto count = tapCounts_.find(key);
        const unsigned tapIndex = count == tapCounts_.end() ? 1 : count->second + 1;
        arrivalEvents_.push_back(
            {cycle, channel, rank, pimBlock, key, tapIndex, partial});
    }

    const std::vector<ArrivalEvent>& arrivalEvents() const { return arrivalEvents_; }

    LinkReplayStats replayTwoStageLink(unsigned channels, unsigned outputLanes = 2) const
    {
        LinkReplayStats stats;
        if (arrivalEvents_.empty()) return stats;
        if (channels == 0 || outputLanes == 0)
            throw std::invalid_argument("Link replay dimensions must be non-zero");

        std::vector<ArrivalEvent> events = arrivalEvents_;
        std::stable_sort(events.begin(), events.end(), [](const ArrivalEvent& lhs,
                                                          const ArrivalEvent& rhs) {
            if (lhs.cycle != rhs.cycle) return lhs.cycle < rhs.cycle;
            if (lhs.channel != rhs.channel) return lhs.channel < rhs.channel;
            return lhs.pimBlock < rhs.pimBlock;
        });
        std::vector<uint64_t> queued(channels, 0);
        size_t event = 0;
        uint64_t queuedTotal = 0;
        unsigned roundRobin = 0;
        uint64_t cycle = events.front().cycle;
        stats.firstArrival = cycle;
        stats.lastArrival = events.back().cycle;
        stats.bursts = events.size();
        stats.bytes = stats.bursts * sizeof(BurstType);

        while (event < events.size() || queuedTotal != 0)
        {
            while (event < events.size() && events[event].cycle <= cycle)
            {
                const unsigned channel = events[event].channel;
                if (channel >= channels)
                    throw std::out_of_range("Arrival trace channel exceeds replay channels");
                queued[channel]++;
                queuedTotal++;
                event++;
            }

            unsigned sent = 0;
            unsigned lastChannel = roundRobin;
            for (unsigned offset = 0; offset < channels && sent < outputLanes; offset++)
            {
                const unsigned channel = (roundRobin + offset) % channels;
                if (queued[channel] == 0) continue;
                queued[channel]--;
                queuedTotal--;
                sent++;
                lastChannel = channel;
            }
            if (sent == outputLanes)
                stats.fullCycles++;
            else if (sent != 0)
                stats.partialCycles++;
            else
                stats.idleCycles++;
            if (sent != 0) roundRobin = (lastChannel + 1) % channels;
            cycle++;
        }
        stats.completionCycle = cycle - 1;
        stats.replayCycles = stats.completionCycle - stats.firstArrival + 1;
        return stats;
    }

    BurstType finalize(uint64_t key)
    {
        const auto entry = entries_.find(key);
        if (entry == entries_.end())
            throw std::logic_error("Finalized a missing logic accumulator entry");
        const auto taps = tapCounts_.find(key);
        if (taps == tapCounts_.end() || taps->second != expectedTaps_)
            throw std::logic_error("Logic accumulator entry has an incomplete tap count");
        BurstType result = entry->second;
        finalizedResults_[key] = result;
        entries_.erase(entry);
        tapCounts_.erase(key);
        finalizedBursts_++;
        return result;
    }

    bool empty() const { return entries_.empty(); }
    size_t size() const { return entries_.size(); }
    uint64_t partialBursts() const { return partialBursts_; }
    uint64_t finalizedBursts() const { return finalizedBursts_; }
    uint64_t peakEntries() const { return peakEntries_; }
    unsigned expectedTaps() const { return expectedTaps_; }
    const BurstType& finalizedResult(uint64_t key) const
    {
        const auto result = finalizedResults_.find(key);
        if (result == finalizedResults_.end())
            throw std::logic_error("Missing finalized logic accumulator result");
        return result->second;
    }

  private:
    std::unordered_map<uint64_t, BurstType> entries_;
    std::unordered_map<uint64_t, unsigned> tapCounts_;
    unsigned expectedTaps_ = 0;
    size_t capacityEntries_ = 0;
    uint64_t partialBursts_ = 0;
    uint64_t finalizedBursts_ = 0;
    uint64_t peakEntries_ = 0;
    std::vector<ArrivalEvent> arrivalEvents_;
    std::unordered_map<uint64_t, BurstType> finalizedResults_;
};
}  // namespace DRAMSim

#endif
