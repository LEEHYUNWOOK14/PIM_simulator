#ifndef HIERARCHY_TILE_PIPELINE_H
#define HIERARCHY_TILE_PIPELINE_H

#include <algorithm>
#include <cstdint>
#include <vector>

namespace DRAMSim
{
struct HierarchyTilePipelineResult
{
    uint64_t sequentialCycles = 0;
    uint64_t pipelinedCycles = 0;
    uint64_t overlapGainCycles = 0;
    uint64_t firstDepthwiseStart = 0;
    uint64_t lastExpandEnd = 0;
    uint64_t firstProjectStart = 0;
    uint64_t logicResourceCycles = 0;
    uint64_t bankResourceCycles = 0;
};

class HierarchyTilePipeline
{
  public:
    static HierarchyTilePipelineResult schedule(
        uint32_t height, uint32_t width, uint64_t expandCycles,
        uint64_t depthwiseCycles, uint64_t projectCycles, uint64_t addCycles,
        uint64_t reluCycles)
    {
        const uint64_t tiles = static_cast<uint64_t>(height) * width;
        if (tiles == 0) return {};
        const auto expandDuration = distribute(expandCycles, tiles);
        const auto depthwiseDuration = distribute(depthwiseCycles, tiles);
        const auto projectDuration = distribute(projectCycles, tiles);
        const auto addDuration = distribute(addCycles, tiles);
        const auto reluDuration = distribute(reluCycles, tiles);
        std::vector<uint64_t> expandEnd(tiles);
        std::vector<uint64_t> depthwiseEnd(tiles);
        std::vector<uint64_t> projectEnd(tiles);

        uint64_t logicBusy = 0;
        for (uint64_t tile = 0; tile < tiles; tile++)
        {
            logicBusy += expandDuration[tile];
            expandEnd[tile] = logicBusy;
        }

        uint64_t bankBusy = 0;
        uint64_t firstDepthwiseStart = 0;
        for (uint32_t y = 0; y < height; y++)
        {
            for (uint32_t x = 0; x < width; x++)
            {
                const uint64_t tile = static_cast<uint64_t>(y) * width + x;
                uint64_t haloReady = 0;
                const uint32_t maxY = std::min(height - 1, y + 1);
                const uint32_t maxX = std::min(width - 1, x + 1);
                for (uint32_t inputY = y == 0 ? 0 : y - 1; inputY <= maxY; inputY++)
                    for (uint32_t inputX = x == 0 ? 0 : x - 1; inputX <= maxX; inputX++)
                        haloReady = std::max(
                            haloReady,
                            expandEnd[static_cast<uint64_t>(inputY) * width + inputX]);
                const uint64_t start = std::max(bankBusy, haloReady);
                if (tile == 0) firstDepthwiseStart = start;
                bankBusy = start + depthwiseDuration[tile];
                depthwiseEnd[tile] = bankBusy;
            }
        }

        uint64_t firstProjectStart = 0;
        for (uint64_t tile = 0; tile < tiles; tile++)
        {
            const uint64_t start = std::max(logicBusy, depthwiseEnd[tile]);
            if (tile == 0) firstProjectStart = start;
            logicBusy = start + projectDuration[tile];
            projectEnd[tile] = logicBusy;
        }

        for (uint64_t tile = 0; tile < tiles; tile++)
        {
            bankBusy = std::max(bankBusy, projectEnd[tile]) + addDuration[tile];
            bankBusy += reluDuration[tile];
        }

        HierarchyTilePipelineResult result;
        result.sequentialCycles =
            expandCycles + depthwiseCycles + projectCycles + addCycles + reluCycles;
        result.pipelinedCycles = std::max(logicBusy, bankBusy);
        result.overlapGainCycles = result.sequentialCycles > result.pipelinedCycles
                                       ? result.sequentialCycles - result.pipelinedCycles
                                       : 0;
        result.firstDepthwiseStart = firstDepthwiseStart;
        result.lastExpandEnd = expandEnd.back();
        result.firstProjectStart = firstProjectStart;
        result.logicResourceCycles = expandCycles + projectCycles;
        result.bankResourceCycles = depthwiseCycles + addCycles + reluCycles;
        return result;
    }

  private:
    static std::vector<uint64_t> distribute(uint64_t total, uint64_t count)
    {
        std::vector<uint64_t> durations(count, total / count);
        for (uint64_t index = 0; index < total % count; index++) durations[index]++;
        return durations;
    }
};
}  // namespace DRAMSim

#endif
