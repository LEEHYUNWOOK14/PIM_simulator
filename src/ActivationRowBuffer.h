#ifndef ACTIVATION_ROW_BUFFER_H
#define ACTIVATION_ROW_BUFFER_H

#include <algorithm>
#include <cstdint>
#include <deque>
#include <stdexcept>
#include <vector>

#include "Burst.h"

namespace DRAMSim
{
struct ActivationRowWindow
{
    unsigned outputRow = 0;
    std::vector<fp16> rows;
};

class ActivationRowBuffer
{
  public:
    ActivationRowBuffer(unsigned height, unsigned row_elements, unsigned kernel_size)
        : height_(height), rowElements_(row_elements), kernelSize_(kernel_size),
          radius_(kernel_size / 2)
    {
        if (height == 0 || row_elements == 0 || kernel_size == 0 || kernel_size % 2 == 0)
            throw std::invalid_argument("Activation row buffer requires nonzero odd kernel");
    }

    void pushRow(unsigned row, const std::vector<fp16>& values)
    {
        if (row != completedRows_ || row >= height_ || values.size() != rowElements_)
            throw std::invalid_argument("Activation rows must be complete and contiguous");
        evictUnusedRows();
        if (rows_.size() == kernelSize_)
            throw std::overflow_error("Activation row buffer is full; release a ready row");
        rows_.push_back({row, values});
        completedRows_++;
        peakRows_ = std::max<unsigned>(peakRows_, rows_.size());
    }

    bool canRelease() const
    {
        if (nextOutputRow_ >= height_) return false;
        const unsigned lastRequired =
            std::min(height_ - 1, nextOutputRow_ + radius_);
        return completedRows_ > lastRequired;
    }

    ActivationRowWindow release()
    {
        if (!canRelease())
            throw std::logic_error("Depthwise output row halo is not complete");
        ActivationRowWindow window;
        window.outputRow = nextOutputRow_;
        window.rows.assign(static_cast<uint64_t>(kernelSize_) * rowElements_, fp16(0.0f));
        for (unsigned tap = 0; tap < kernelSize_; tap++)
        {
            const int inputRow = static_cast<int>(nextOutputRow_) + tap - radius_;
            if (inputRow < 0 || inputRow >= static_cast<int>(height_)) continue;
            const auto stored = std::find_if(
                rows_.begin(), rows_.end(),
                [inputRow](const StoredRow& row) { return row.index == inputRow; });
            if (stored == rows_.end())
                throw std::logic_error("Required activation row was evicted before release");
            std::copy(stored->values.begin(), stored->values.end(),
                      window.rows.begin() + static_cast<uint64_t>(tap) * rowElements_);
        }
        nextOutputRow_++;
        evictUnusedRows();
        return window;
    }

    unsigned completedRows() const { return completedRows_; }
    unsigned releasedRows() const { return nextOutputRow_; }
    unsigned residentRows() const { return rows_.size(); }
    unsigned peakRows() const { return peakRows_; }

  private:
    struct StoredRow
    {
        unsigned index;
        std::vector<fp16> values;
    };

    void evictUnusedRows()
    {
        const unsigned firstRequired =
            nextOutputRow_ > radius_ ? nextOutputRow_ - radius_ : 0;
        while (!rows_.empty() && rows_.front().index < firstRequired) rows_.pop_front();
    }

    unsigned height_;
    unsigned rowElements_;
    unsigned kernelSize_;
    unsigned radius_;
    unsigned completedRows_ = 0;
    unsigned nextOutputRow_ = 0;
    unsigned peakRows_ = 0;
    std::deque<StoredRow> rows_;
};
}  // namespace DRAMSim

#endif
