#ifndef LOGIC_DIE_WEIGHT_BUFFER_H
#define LOGIC_DIE_WEIGHT_BUFFER_H

#include <cstdint>
#include <algorithm>
#include <unordered_map>
#include <vector>

#include "Burst.h"

namespace DRAMSim
{
class LogicDieWeightBuffer
{
  public:
    struct Key
    {
        unsigned channel;
        unsigned rank;
        unsigned bank;
        unsigned row;
        unsigned column;

        bool operator==(const Key& other) const
        {
            return channel == other.channel && rank == other.rank && bank == other.bank &&
                   row == other.row && column == other.column;
        }
    };

    struct KeyHash
    {
        size_t operator()(const Key& key) const
        {
            size_t value = key.channel;
            value = value * 131 + key.rank;
            value = value * 131 + key.bank;
            value = value * 131 + key.row;
            return value * 131 + key.column;
        }
    };

    LogicDieWeightBuffer()
        : active_(false), groupWidth_(0), capacityBytes_(0), storedBytes_(0), fillBursts_(0),
          readHits_(0), readMisses_(0), writeLatency_(1), readyCycle_(0),
          completedFillBursts_(0), writeQueueCycles_(0), layerGeneration_(0)
    {
    }

    void beginLayer(unsigned group_width, uint64_t capacity_bytes, unsigned write_ports,
                    unsigned write_latency)
    {
        layerGeneration_++;
        entries_.clear();
        active_ = group_width > 0 && capacity_bytes >= sizeof(BurstType);
        groupWidth_ = group_width;
        capacityBytes_ = capacity_bytes;
        storedBytes_ = 0;
        writeLatency_ = write_latency;
        writePortBusyUntil_.assign(write_ports, 0);
        readyCycle_ = 0;
        completedFillBursts_ = 0;
    }

    bool store(unsigned physical_channel, unsigned rank, unsigned bank, unsigned row,
               unsigned column, const BurstType& data)
    {
        if (!active_) return false;
        const Key key{physical_channel % groupWidth_, rank, bank, row, column};
        const auto existing = entries_.find(key);
        if (existing == entries_.end())
        {
            if (storedBytes_ + sizeof(BurstType) > capacityBytes_) return false;
            entries_.emplace(key, data);
            storedBytes_ += sizeof(BurstType);
            fillBursts_++;
        }
        else
        {
            existing->second = data;
        }
        return true;
    }

    bool read(unsigned physical_channel, unsigned rank, unsigned bank, unsigned row,
              unsigned column, BurstType& data)
    {
        if (!active_)
        {
            readMisses_++;
            return false;
        }
        const Key key{physical_channel % groupWidth_, rank, bank, row, column};
        const auto entry = entries_.find(key);
        if (entry == entries_.end())
        {
            readMisses_++;
            return false;
        }
        data = entry->second;
        readHits_++;
        return true;
    }

    uint64_t completeFill(uint64_t source_ready_cycle)
    {
        uint64_t completion = source_ready_cycle;
        if (!writePortBusyUntil_.empty())
        {
            auto lane = std::min_element(writePortBusyUntil_.begin(), writePortBusyUntil_.end());
            const uint64_t start = std::max(source_ready_cycle, *lane);
            writeQueueCycles_ += start - source_ready_cycle;
            completion = start + writeLatency_;
            *lane = completion;
        }
        readyCycle_ = std::max(readyCycle_, completion);
        completedFillBursts_++;
        return completion;
    }

    bool isActive() const { return active_; }
    uint64_t getStoredBytes() const { return storedBytes_; }
    uint64_t getFillBursts() const { return fillBursts_; }
    uint64_t getReadHits() const { return readHits_; }
    uint64_t getReadMisses() const { return readMisses_; }
    uint64_t getReadyCycle() const { return readyCycle_; }
    uint64_t getCompletedFillBursts() const { return completedFillBursts_; }
    uint64_t getWriteQueueCycles() const { return writeQueueCycles_; }
    uint64_t getLayerGeneration() const { return layerGeneration_; }

  private:
    bool active_;
    unsigned groupWidth_;
    uint64_t capacityBytes_;
    uint64_t storedBytes_;
    uint64_t fillBursts_;
    uint64_t readHits_;
    uint64_t readMisses_;
    unsigned writeLatency_;
    uint64_t readyCycle_;
    uint64_t completedFillBursts_;
    uint64_t writeQueueCycles_;
    uint64_t layerGeneration_;
    std::vector<uint64_t> writePortBusyUntil_;
    std::unordered_map<Key, BurstType, KeyHash> entries_;
};
}  // namespace DRAMSim

#endif
