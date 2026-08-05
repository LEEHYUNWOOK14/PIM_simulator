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

#ifndef RANK_H
#define RANK_H

#include <deque>
#include <vector>

#include "AddressMapping.h"
#include "Bank.h"
#include "BankState.h"
#include "BusPacket.h"
#include "Configuration.h"
#include "PIMRank.h"
#include "LogicDieScheduler.h"
#include "LogicDieWeightBuffer.h"
#include "LogicDieAccumulator.h"
#include "SimulatorObject.h"

using namespace std;
using namespace DRAMSim;

namespace DRAMSim
{
enum class RankCommandRejectReason
{
    NONE,
    MODE_TRANSITION,
    LOGIC_QUEUE_BACKPRESSURE,
    BANK_LOCAL_ACCUMULATOR_BACKPRESSURE
};

class MemoryController;  // forward declaration
class PIMRank;           // forward declaration
class Rank : public SimulatorObject
{
  private:
    int chanId;
    int rankId;
    ostream& dramsimLog;
    bool isPowerDown;
    Configuration& config;

  public:
    // functions
    Rank(ostream& simLog, Configuration& configuration,
         shared_ptr<LogicDieScheduler> logicScheduler,
         shared_ptr<LogicDieWeightBuffer> logicWeightBuffer,
         shared_ptr<LogicDieAccumulator> logicAccumulator);
    virtual ~Rank();

    void receiveFromBus(BusPacket* packet);
    void check(BusPacket* packet);
    void updateState(BusPacket* packet);
    void sendToBank(BusPacket* packet);
    bool canAcceptCommand(BusPacket* packet, bool recordStall = true);
    RankCommandRejectReason getLastCommandRejectReason() const
    {
        return lastCommandRejectReason_;
    }

    void checkBank(BusPacketType type, int bank, int row);
    void updateBank(BusPacketType type, int bank, int row, bool targetBank, bool targetBankgroup);
    void attachMemoryController(MemoryController* mc);
    int getChanId() const;
    void setChanId(int id);
    int getRankId() const;
    void setRankId(int id);
    void update();
    void powerUp();
    void powerDown();

    void readSb(BusPacket* packet);
    void writeSb(BusPacket* packet);
    dramMode getModeForPacket(const BusPacket* packet) const;
    void setModeForPacket(const BusPacket* packet, dramMode mode);

    // fields
    MemoryController* memoryController;
    BusPacket* outgoingDataPacket;
    shared_ptr<PIMRank> pimRank;
    unsigned dataCyclesLeft;
    bool refreshWaiting;

    // these are vectors so that each element is per-bank
    deque<BusPacket*> readReturnPacket;
    deque<unsigned> readReturnCountdown;

    vector<Bank> banks;
    vector<BankState> bankStates;

    dramMode mode_;
    bool abmr1Even_, abmr1Odd_, abmr2Even_, abmr2Odd_, sbmr1_, sbmr2_;
    dramMode logicMode_ = dramMode::SB;
    uint64_t modeReadyCycle_ = 0;
    uint64_t logicModeReadyCycle_ = 0;
    RankCommandRejectReason lastCommandRejectReason_ = RankCommandRejectReason::NONE;
    bool logicAbmr1Even_ = false, logicAbmr1Odd_ = false, logicAbmr2Even_ = false,
         logicAbmr2Odd_ = false, logicSbmr1_ = false, logicSbmr2_ = false;

    const char* getModeColor()
    {
        switch (mode_)
        {
            case dramMode::SB:
                return END;
            case dramMode::HAB:
                return GREEN;
            case dramMode::HAB_PIM:
                return CYAN;
        }
        return GRAY;
    }
};
}  // namespace DRAMSim
#endif
