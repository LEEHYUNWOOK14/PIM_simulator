#ifndef LOGIC_DIE_OUTPUT_BUFFER_H
#define LOGIC_DIE_OUTPUT_BUFFER_H

#include <algorithm>
#include <cstdint>
#include <deque>
#include <unordered_map>
#include <vector>

#include "Burst.h"

namespace DRAMSim
{
class LogicDieOutputBuffer
{
  public:
    struct TileId
    {
        uint64_t layer;
        uint64_t position;
        uint64_t channelTile;

        bool operator==(const TileId& other) const
        {
            return layer == other.layer && position == other.position &&
                   channelTile == other.channelTile;
        }
    };

    struct TileIdHash
    {
        size_t operator()(const TileId& tile) const
        {
            size_t value = std::hash<uint64_t>{}(tile.layer);
            value ^= std::hash<uint64_t>{}(tile.position) + 0x9e3779b9 + (value << 6) +
                     (value >> 2);
            value ^= std::hash<uint64_t>{}(tile.channelTile) + 0x9e3779b9 + (value << 6) +
                     (value >> 2);
            return value;
        }
    };

    explicit LogicDieOutputBuffer(size_t capacity = 2, uint64_t drainLatency = 0,
                                  uint64_t drainBandwidth = 0)
        : capacity_(std::max<size_t>(1, capacity)),
          drainLatency_(drainLatency),
          drainBandwidth_(drainBandwidth)
    {
    }

    void beginLayer(uint64_t layer)
    {
        activeLayer_ = layer;
        entries_.clear();
        retirementOrder_.clear();
        committed_.clear();
    }

    bool reserve(const TileId& tile, size_t expectedBursts)
    {
        if (expectedBursts == 0 || tile.layer != activeLayer_ || entries_.count(tile) != 0)
            return false;
        if (entries_.size() >= capacity_)
        {
            fullStalls_++;
            return false;
        }
        Entry entry;
        entry.data.resize(expectedBursts);
        entry.valid.assign(expectedBursts, false);
        entries_.emplace(tile, std::move(entry));
        retirementOrder_.push_back(tile);
        peakEntries_ = std::max<uint64_t>(peakEntries_, entries_.size());
        reservations_++;
        return true;
    }

    bool write(const TileId& tile, size_t burst, const BurstType& data)
    {
        auto found = entries_.find(tile);
        if (found == entries_.end() || burst >= found->second.data.size()) return false;
        Entry& entry = found->second;
        entry.data[burst] = data;
        if (!entry.valid[burst])
        {
            entry.valid[burst] = true;
            entry.completedBursts++;
            writes_++;
            if (entry.completedBursts == entry.data.size()) completedTiles_++;
        }
        return true;
    }

    bool isReady(const TileId& tile) const
    {
        const auto found = entries_.find(tile);
        return found != entries_.end() &&
               found->second.completedBursts == found->second.data.size();
    }

    bool contains(const TileId& tile) const { return entries_.count(tile) != 0; }

    bool commitReadyFront()
    {
        if (retirementOrder_.empty()) return false;
        const TileId tile = retirementOrder_.front();
        const auto found = entries_.find(tile);
        if (found == entries_.end() || !isReady(tile)) return false;
        committed_[tile] = std::move(found->second.data);
        retirementOrder_.pop_front();
        entries_.erase(found);
        retirements_++;
        return true;
    }

    void advance(uint64_t cycle)
    {
        if (retirementOrder_.empty()) return;
        const TileId tile = retirementOrder_.front();
        auto found = entries_.find(tile);
        if (found == entries_.end() || !isReady(tile)) return;
        Entry& entry = found->second;
        if (!entry.drainStarted)
        {
            const uint64_t transferCycles =
                drainBandwidth_ == 0
                    ? 0
                    : (entry.data.size() + drainBandwidth_ - 1) / drainBandwidth_;
            entry.drainReadyCycle = cycle + drainLatency_ + transferCycles;
            entry.drainStarted = true;
            drainBusyCycles_ += drainLatency_ + transferCycles;
        }
        if (cycle >= entry.drainReadyCycle) commitReadyFront();
    }

    bool readCommitted(const TileId& tile, size_t burst, BurstType& data) const
    {
        const auto found = committed_.find(tile);
        if (found == committed_.end() || burst >= found->second.size()) return false;
        data = found->second[burst];
        return true;
    }

    bool releaseCommitted(const TileId& tile) { return committed_.erase(tile) == 1; }

    void recordFullWallCycle(uint64_t cycle)
    {
        if (lastFullWallCycle_ == cycle) return;
        lastFullWallCycle_ = cycle;
        fullWallCycles_++;
    }

    bool read(const TileId& tile, size_t burst, BurstType& data) const
    {
        const auto found = entries_.find(tile);
        if (found == entries_.end() || !isReady(tile) || burst >= found->second.data.size())
            return false;
        data = found->second.data[burst];
        return true;
    }

    bool retire(const TileId& tile)
    {
        if (retirementOrder_.empty() || !(retirementOrder_.front() == tile) || !isReady(tile))
            return false;
        retirementOrder_.pop_front();
        entries_.erase(tile);
        retirements_++;
        return true;
    }

    size_t size() const { return entries_.size(); }
    size_t capacity() const { return capacity_; }
    bool full() const { return entries_.size() >= capacity_; }
    bool hasPendingDrain() const { return !entries_.empty(); }
    uint64_t getReservations() const { return reservations_; }
    uint64_t getWrites() const { return writes_; }
    uint64_t getCompletedTiles() const { return completedTiles_; }
    uint64_t getRetirements() const { return retirements_; }
    uint64_t getFullStalls() const { return fullStalls_; }
    uint64_t getPeakEntries() const { return peakEntries_; }
    uint64_t getDrainBusyCycles() const { return drainBusyCycles_; }
    uint64_t getFullWallCycles() const { return fullWallCycles_; }

  private:
    struct Entry
    {
        std::vector<BurstType> data;
        std::vector<bool> valid;
        size_t completedBursts = 0;
        bool drainStarted = false;
        uint64_t drainReadyCycle = 0;
    };

    size_t capacity_;
    uint64_t activeLayer_ = 0;
    uint64_t reservations_ = 0;
    uint64_t writes_ = 0;
    uint64_t completedTiles_ = 0;
    uint64_t retirements_ = 0;
    uint64_t fullStalls_ = 0;
    uint64_t peakEntries_ = 0;
    uint64_t drainLatency_ = 0;
    uint64_t drainBandwidth_ = 0;
    uint64_t drainBusyCycles_ = 0;
    uint64_t fullWallCycles_ = 0;
    uint64_t lastFullWallCycle_ = UINT64_MAX;
    std::unordered_map<TileId, Entry, TileIdHash> entries_;
    std::deque<TileId> retirementOrder_;
    std::unordered_map<TileId, std::vector<BurstType>, TileIdHash> committed_;
};
}  // namespace DRAMSim

#endif
