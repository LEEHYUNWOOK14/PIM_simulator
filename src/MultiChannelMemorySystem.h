/*********************************************************************************
 *  Copyright (c) 2010-2011, Elliott Cooper-Balis
 *                             Paul Rosenfeld
 *                             Bruce Jacob
 *                             University of Maryland
 *                             dramninjas [at] gmail [dot] com
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions are met:
 *
 *     * Redistributions of source code must retain the above copyright notice,
 *        this list of conditions and the following disclaimer.
 *
 *     * Redistributions in binary form must reproduce the above copyright notice,
 *        this list of conditions and the following disclaimer in the documentation
 *        and/or other materials provided with the distribution.
 *
 *  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 *  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 *  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 *  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
 *  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 *  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 *  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 *  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
 *  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 *  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *********************************************************************************/

#ifndef __MULTI_CHANNEL_MEMORY_SYSTEM_H__H__
#define __MULTI_CHANNEL_MEMORY_SYSTEM_H__H__

#include <string>
#include <array>
#include <vector>

#include "AddressMapping.h"
#include "CSVWriter.h"
#include "ClockDomain.h"
#include "Configuration.h"
#include "MemoryObject.h"
#include "MemorySystem.h"
#include "LogicDieScheduler.h"
#include "LogicDieWeightBuffer.h"
#include "LogicDieOutputBuffer.h"
#include "LogicDieAccumulator.h"
#include "SimulatorObject.h"
#include "SystemConfiguration.h"
#include "Transaction.h"

namespace DRAMSim
{
class MultiChannelMemorySystem : public MemoryObject
{
  public:
    MultiChannelMemorySystem(const string& dev, const string& sys, const string& pwd,
                             const string& trc, unsigned megsOfMemory, string* visFilename = NULL);
    virtual ~MultiChannelMemorySystem();

    virtual bool addTransaction(Transaction* trans);
    virtual bool addTransaction(bool isWrite, uint64_t addr, BurstType* data);
    virtual bool addTransaction(bool isWrite, uint64_t addr, const std::string& tag,
                                BurstType* data,
                                WriteCompletionClass completionClass =
                                    WriteCompletionClass::ORDERED);

    bool addBarrier(int chanId);

    void update();
    void printStats(bool finalStats = false);
    ostream& getLogFile();
    void RegisterCallbacks(TransactionCompleteCB* readDone, TransactionCompleteCB* writeDone,
                           void (*reportPower)(double bgpower, double burstpower,
                                               double refreshpower, double actprepower));
    unsigned getNumFence(int ch)
    {
        return numFence[ch];
    }

    void InitOutputFiles(string tracefilename);
    void setCPUClockSpeed(uint64_t cpuClkFreqHz);

    int hasPendingTransactions();

    uint64_t getGlobalAnyBlockedCycles(CommandIssuabilityRejectReason reason) const
    {
        return globalAnyBlockedCycles_[static_cast<size_t>(reason)];
    }
    uint64_t getGlobalAllActiveBlockedCycles(CommandIssuabilityRejectReason reason) const
    {
        return globalAllActiveBlockedCycles_[static_cast<size_t>(reason)];
    }
    uint64_t getGlobalPeakBlockedChannels(CommandIssuabilityRejectReason reason) const
    {
        return globalPeakBlockedChannels_[static_cast<size_t>(reason)];
    }
    uint64_t getGlobalRankModeAnyBlockedCycles() const
    {
        return globalRankModeAnyBlockedCycles_;
    }
    uint64_t getGlobalRankModeAllActiveBlockedCycles() const
    {
        return globalRankModeAllActiveBlockedCycles_;
    }
    uint64_t getGlobalRankModePeakBlockedChannels() const
    {
        return globalRankModePeakBlockedChannels_;
    }
    uint64_t getGlobalPredicateAnyBlockedCycles(HierarchyPredicateBlockReason reason) const
    {
        return globalPredicateAnyBlockedCycles_[static_cast<size_t>(reason)];
    }
    uint64_t getGlobalPredicateAllActiveBlockedCycles(
        HierarchyPredicateBlockReason reason) const
    {
        return globalPredicateAllActiveBlockedCycles_[static_cast<size_t>(reason)];
    }
    uint64_t getGlobalPredicatePeakBlockedChannels(
        HierarchyPredicateBlockReason reason) const
    {
        return globalPredicatePeakBlockedChannels_[static_cast<size_t>(reason)];
    }
    uint64_t getGlobalHierarchyUnionAnyBlockedCycles() const
    {
        return globalHierarchyUnionAnyBlockedCycles_;
    }
    uint64_t getGlobalHierarchyUnionAllActiveBlockedCycles() const
    {
        return globalHierarchyUnionAllActiveBlockedCycles_;
    }
    uint64_t getGlobalHierarchyUnionPeakBlockedChannels() const
    {
        return globalHierarchyUnionPeakBlockedChannels_;
    }
    uint64_t getGlobalBankStateAllNoHierarchyCycles() const
    {
        return globalBankStateAllNoHierarchyCycles_;
    }
    uint64_t getGlobalBankStateAllWithHierarchyCycles() const
    {
        return globalBankStateAllWithHierarchyCycles_;
    }
    uint64_t getGlobalBankStateOnlyCycles() const { return globalBankStateOnlyCycles_; }
    uint64_t getGlobalHierarchyAllNoIssuabilityCycles() const
    {
        return globalHierarchyAllNoIssuabilityCycles_;
    }
    uint64_t getGlobalBankHierarchyAllIntersectionCycles() const
    {
        return globalBankHierarchyAllIntersectionCycles_;
    }
    uint64_t getGlobalBankTagAnyBlockedCycles(CommandTagClass tagClass) const
    {
        return globalBankTagAnyBlockedCycles_[static_cast<size_t>(tagClass)];
    }
    uint64_t getGlobalBankTagAllActiveBlockedCycles(CommandTagClass tagClass) const
    {
        return globalBankTagAllActiveBlockedCycles_[static_cast<size_t>(tagClass)];
    }
    uint64_t getGlobalBankTagPeakBlockedChannels(CommandTagClass tagClass) const
    {
        return globalBankTagPeakBlockedChannels_[static_cast<size_t>(tagClass)];
    }

    bool willAcceptTransaction(uint64_t addr);
    bool willAcceptTransaction();

    // output file
    std::ofstream visDataOut;
    ofstream dramsimLog;
    vector<MemorySystem*> channels;
    shared_ptr<LogicDieScheduler> logicDieScheduler;
    shared_ptr<LogicDieWeightBuffer> logicDieWeightBuffer;
    shared_ptr<LogicDieOutputBuffer> logicDieOutputBuffer;
    shared_ptr<LogicDieAccumulator> logicDieAccumulator;
    AddrMapping* addrMapping;

    void beginLogicWeightLayer(unsigned groupWidth, uint64_t capacityBytes);
    bool storeLogicWeight(uint64_t addr, const BurstType& data);
    void beginLogicDepthwiseAccumulation(unsigned expectedTaps, size_t capacityEntries = 0);
    void beginLogicReleaseEpoch(
        unsigned expectedStreams,
        const std::vector<std::pair<uint64_t, uint64_t>>& streamOrdinals = {});

    void getIniBool(const std::string& field, bool* val)
    {
        *val = getConfigParam(BOOL, field);
    }

    void getIniUint(const std::string& field, unsigned int* val)
    {
        *val = getConfigParam(UINT, field);
    }

    void getIniUint64(const std::string& field, uint64_t* val)
    {
        *val = getConfigParam(UINT64, field);
    }

    void getIniFloat(const std::string& field, float* val)
    {
        *val = getConfigParam(FLOAT, field);
    }

  private:
    unsigned findChannelNumber(uint64_t addr);
    void actual_update();

    unsigned megsOfMemory;
    string deviceIniFilename;
    string systemIniFilename;
    string traceFilename;
    string pwd;
    string* visFilename;
    ClockDomain::ClockDomainCrosser clockDomainCrosser;
    static void mkdirIfNotExist(string path);
    static bool fileExists(string path);
    CSVWriter* csvOut;

    double backgroundPower;
    unsigned* numFence;

    Configuration* configuration;
    static constexpr size_t issuabilityRejectReasonCount_ =
        static_cast<size_t>(CommandIssuabilityRejectReason::COUNT);
    array<uint64_t, issuabilityRejectReasonCount_> globalAnyBlockedCycles_{};
    array<uint64_t, issuabilityRejectReasonCount_> globalAllActiveBlockedCycles_{};
    array<uint64_t, issuabilityRejectReasonCount_> globalPeakBlockedChannels_{};
    uint64_t globalRankModeAnyBlockedCycles_ = 0;
    uint64_t globalRankModeAllActiveBlockedCycles_ = 0;
    uint64_t globalRankModePeakBlockedChannels_ = 0;
    static constexpr size_t hierarchyPredicateBlockReasonCount_ =
        static_cast<size_t>(HierarchyPredicateBlockReason::COUNT);
    array<uint64_t, hierarchyPredicateBlockReasonCount_> globalPredicateAnyBlockedCycles_{};
    array<uint64_t, hierarchyPredicateBlockReasonCount_>
        globalPredicateAllActiveBlockedCycles_{};
    array<uint64_t, hierarchyPredicateBlockReasonCount_>
        globalPredicatePeakBlockedChannels_{};
    uint64_t globalHierarchyUnionAnyBlockedCycles_ = 0;
    uint64_t globalHierarchyUnionAllActiveBlockedCycles_ = 0;
    uint64_t globalHierarchyUnionPeakBlockedChannels_ = 0;
    uint64_t globalBankStateAllNoHierarchyCycles_ = 0;
    uint64_t globalBankStateAllWithHierarchyCycles_ = 0;
    uint64_t globalBankStateOnlyCycles_ = 0;
    uint64_t globalHierarchyAllNoIssuabilityCycles_ = 0;
    uint64_t globalBankHierarchyAllIntersectionCycles_ = 0;
    static constexpr size_t commandTagClassCount_ =
        static_cast<size_t>(CommandTagClass::COUNT);
    array<uint64_t, commandTagClassCount_> globalBankTagAnyBlockedCycles_{};
    array<uint64_t, commandTagClassCount_> globalBankTagAllActiveBlockedCycles_{};
    array<uint64_t, commandTagClassCount_> globalBankTagPeakBlockedChannels_{};
};
}  // namespace DRAMSim

#endif
