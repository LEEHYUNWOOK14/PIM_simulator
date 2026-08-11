// Standalone GR00T normalization trace replay through the repository LogicDieScheduler.
// This intentionally does not modify the production simulator or RTL.

#include "src/LogicDieScheduler.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>

using DRAMSim::LogicCommandContext;
using DRAMSim::LogicDieScheduler;

struct Profile
{
    const char* name;
    uint64_t rows;
    uint64_t hidden;
    uint64_t calls;
    uint64_t measuredCycles;
};

static constexpr std::array<Profile, 7> kProfiles{{
    {"vlln", 280, 2048, 1, 17198},
    {"vl_self_attention_norm1_norm3", 280, 2048, 8, 17198},
    {"dit_adaln_norm1", 41, 1536, 128, 4856},
    {"dit_norm3", 41, 1536, 128, 4856},
    {"dit_norm_out", 41, 1536, 4, 4856},
    {"qwen_input_post_attention", 280, 2048, 32, 9735},
    {"qwen_query_key", 8960, 64, 32, 9735},
}};

struct Scenario
{
    const char* name;
    double requestsPerSecondPerChannel;
};

static constexpr std::array<Scenario, 3> kScenarios{{
    {"low", 500.0}, {"base", 2500.0}, {"high", 10000.0},
}};

struct Request
{
    const Profile* profile;
    uint64_t channel;
    uint64_t ordinal;
};

int main(int argc, char** argv)
{
    const std::string output = argc > 1 ? argv[1] : "gr00t_scheduler_replay.csv";
    constexpr uint64_t channels = 8;
    constexpr uint64_t frequencyHz = 100000000;
    constexpr uint64_t pcuCount = 16;
    constexpr uint64_t blocks = 8;
    constexpr uint64_t transferBytesPerCycle = 64;

    std::vector<Request> trace;
    uint64_t ordinal = 0;
    for (const auto& profile : kProfiles)
        for (uint64_t call = 0; call < profile.calls; ++call, ++ordinal)
            trace.push_back({&profile, ordinal % channels, ordinal});

    std::ofstream csv(output);
    if (!csv)
    {
        std::cerr << "cannot open output: " << output << '\n';
        return 2;
    }
    const auto dot = output.rfind(".csv");
    const std::string traceOutput = (dot == std::string::npos ? output : output.substr(0, dot)) +
                                    "_base_trace.csv";
    std::ofstream traceCsv(traceOutput);
    if (!traceCsv)
    {
        std::cerr << "cannot open trace output: " << traceOutput << '\n';
        return 2;
    }
    traceCsv << "ordinal,profile,channel,arrival_cycle,tensor_input_output_bytes,"
                "measured_compute_cycles,transfer_cycles,service_start_cycle,completion_cycle,"
                "queue_cycles,service_cycles\n";
    csv << "scenario,channel_request_rate_per_s,total_requests,total_transfer_bytes,"
           "first_arrival_cycle,last_arrival_cycle,last_completion_cycle,completion_span_cycles,"
           "scheduler_parallel_lanes,total_compute_cycles,total_transfer_cycles,total_service_cycles,"
           "total_queue_cycles,mean_queue_cycles,max_queue_cycles,compute_lane_utilization,"
           "service_lane_utilization,achieved_requests_per_s,achieved_bandwidth_gbps";
    for (uint64_t channel = 0; channel < channels; ++channel)
        csv << ",channel_" << channel << "_requests,channel_" << channel << "_bytes";
    csv << '\n';

    for (const auto& scenario : kScenarios)
    {
        LogicDieScheduler scheduler;
        std::array<uint64_t, channels> channelRequests{};
        std::array<uint64_t, channels> channelBytes{};
        const double aggregateRate = scenario.requestsPerSecondPerChannel * channels;
        const double cyclesPerArrival = static_cast<double>(frequencyHz) / aggregateRate;
        uint64_t firstArrival = 0;
        uint64_t lastArrival = 0;
        uint64_t lastCompletion = 0;
        uint64_t totalBytes = 0;
        uint64_t totalCompute = 0;
        uint64_t totalTransfer = 0;
        uint64_t totalService = 0;
        uint64_t totalQueue = 0;
        uint64_t maxQueue = 0;

        for (size_t index = 0; index < trace.size(); ++index)
        {
            const auto& request = trace[index];
            const uint64_t arrival = static_cast<uint64_t>(std::floor(index * cyclesPerArrival));
            const uint64_t tensorBytes = request.profile->rows * request.profile->hidden * 4;
            const uint64_t bytesPerBlock = (tensorBytes + blocks - 1) / blocks;
            LogicCommandContext context{1, request.ordinal, request.channel, true};
            const auto reservation = scheduler.reserve(
                arrival, blocks, pcuCount, request.profile->measuredCycles,
                transferBytesPerCycle, bytesPerBlock, request.ordinal, 0, false, context);
            if (std::string(scenario.name) == "base")
                traceCsv << request.ordinal << ',' << request.profile->name << ','
                         << request.channel << ',' << arrival << ',' << tensorBytes << ','
                         << reservation.computeCycles << ',' << reservation.transferCycles << ','
                         << arrival + reservation.queueCycles << ','
                         << arrival + reservation.completionDelay << ','
                         << reservation.queueCycles << ',' << reservation.serviceCycles << '\n';
            lastArrival = arrival;
            lastCompletion = std::max(lastCompletion, arrival + reservation.completionDelay);
            totalBytes += reservation.transferBytes;
            totalCompute += reservation.computeCycles;
            totalTransfer += reservation.transferCycles;
            totalService += reservation.serviceCycles;
            totalQueue += reservation.queueCycles;
            maxQueue = std::max(maxQueue, reservation.queueCycles);
            channelRequests[request.channel]++;
            channelBytes[request.channel] += reservation.transferBytes;
        }

        const uint64_t span = std::max<uint64_t>(1, lastCompletion - firstArrival);
        const uint64_t parallelLanes = pcuCount / blocks;
        const double computeUtilization = static_cast<double>(totalCompute) / (span * parallelLanes);
        const double serviceUtilization = static_cast<double>(totalService) / (span * parallelLanes);
        const double achievedRequests = static_cast<double>(trace.size()) * frequencyHz / span;
        const double achievedBandwidth = static_cast<double>(totalBytes) * frequencyHz / span / 1.0e9;
        csv << scenario.name << ',' << std::fixed << std::setprecision(3)
            << scenario.requestsPerSecondPerChannel << ',' << trace.size() << ',' << totalBytes << ','
            << firstArrival << ',' << lastArrival << ',' << lastCompletion << ',' << span << ','
            << parallelLanes << ',' << totalCompute << ',' << totalTransfer << ','
            << totalService << ',' << totalQueue << ','
            << static_cast<double>(totalQueue) / trace.size() << ',' << maxQueue << ','
            << computeUtilization << ',' << serviceUtilization << ','
            << achievedRequests << ',' << achievedBandwidth;
        for (uint64_t channel = 0; channel < channels; ++channel)
            csv << ',' << channelRequests[channel] << ',' << channelBytes[channel];
        csv << '\n';
    }

    std::cout << "wrote " << output << " and " << traceOutput << " with "
              << trace.size() << " requests\n";
    return 0;
}
