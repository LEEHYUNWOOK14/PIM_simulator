/***************************************************************************************************
 * Copyright (C) 2021 Samsung Electronics Co. LTD
 *
 * This software is a property of Samsung Electronics.
 * No part of this software, either material or conceptual may be copied or distributed,
 * transmitted, transcribed, stored in a retrieval system, or translated into any human
 * or computer language in any form by any means,electronic, mechanical, manual or otherwise,
 * or disclosed to third parties without the express written permission of Samsung Electronics.
 * (Use of the Software is restricted to non-commercial, personal or academic, research purpose
 * only)
 **************************************************************************************************/

#include "PIMRank.h"

#include <bitset>
#include <iostream>
#include <stdexcept>

#include "AddressMapping.h"
#include "PIMCmd.h"
#include "tests/PIMCmdGen.h"

using namespace std;
using namespace DRAMSim;

PIMRank::PIMRank(ostream& simLog, Configuration& configuration,
                 shared_ptr<LogicDieScheduler> logicScheduler,
                 shared_ptr<LogicDieWeightBuffer> logicWeightBuffer)
    : chanId(-1),
      rankId(-1),
      dramsimLog(simLog),
      pimPC_(0),
      lastJumpIdx_(-1),
      numJumpToBeTaken_(-1),
      lastRepeatIdx_(-1),
      numRepeatToBeDone_(-1),
      crfExit_(false),
      config(configuration),
      logicScheduler_(logicScheduler),
      logicWeightBuffer_(logicWeightBuffer),
      pimBlocks(getConfigParam(UINT, "NUM_PIM_BLOCKS"),
                PIMBlock(PIMConfiguration::getPIMPrecision()))
{
    logicPimBlocks.assign(getConfigParam(UINT, "NUM_PIM_BLOCKS"),
                           PIMBlock(PIMConfiguration::getPIMPrecision()));
    currentClockCycle = 0;
    logicBusyUntil_ = 0;
    logicCommandCount_ = 0;
    logicComputeCycles_ = 0;
    logicTransferBytes_ = 0;
    logicTransferCycles_ = 0;
    logicServiceCycles_ = 0;
    lastLogicServiceCycles_ = 0;

    if (config.ENABLE_LOGIC_DIE_PIM && config.NUM_LOGIC_PIM_UNITS == 0)
        throw invalid_argument("NUM_LOGIC_PIM_UNITS must be greater than zero when logic-die PIM is enabled");
}

bool PIMRank::isBankSideEnabled() const
{
    return config.ENABLE_BANK_SIDE_PIM;
}

bool PIMRank::isLogicDieEnabled() const
{
    return config.ENABLE_LOGIC_DIE_PIM;
}

bool PIMRank::isHybridEnabled() const
{
    return isBankSideEnabled() && isLogicDieEnabled();
}

PIMRank::PIMRouteMode PIMRank::getRouteMode() const
{
    if (isHybridEnabled())
        return PIMRouteMode::HYBRID;
    if (isLogicDieEnabled() && !isBankSideEnabled())
        return PIMRouteMode::LOGIC_ONLY;
    return PIMRouteMode::BANK_ONLY;
}

const char* PIMRank::routeModeToStr(PIMRouteMode mode) const
{
    switch (mode)
    {
        case PIMRouteMode::BANK_ONLY:
            return "BANK_ONLY";
        case PIMRouteMode::LOGIC_ONLY:
            return "LOGIC_ONLY";
        case PIMRouteMode::HYBRID:
            return "HYBRID";
        default:
            return "UNKNOWN";
    }
}

bool PIMRank::shouldRouteToLogicDie(PIMCmd cCmd) const
{
    if (!isLogicDieEnabled())
        return false;

    if (cCmd.type_ != PIMCmdType::MAC && cCmd.type_ != PIMCmdType::MAD)
        return false;

    return getRouteMode() != PIMRouteMode::BANK_ONLY;
}

unsigned PIMRank::reserveLogicDie(PIMCmd cCmd)
{
    if (!shouldRouteToLogicDie(cCmd))
        return 0;

    const uint64_t blocks = config.NUM_PIM_BLOCKS;
    if (config.LOGIC_GLOBAL_SCHEDULER)
    {
        const LogicDieReservation reservation = logicScheduler_->reserve(
            currentClockCycle, blocks, config.NUM_LOGIC_PIM_UNITS, config.LOGIC_PIM_LATENCY,
            config.LOGIC_PIM_BW, sizeof(BurstType), cCmd.toInt(), config.LOGIC_CMD_OVERHEAD,
            config.LOGIC_CMD_COALESCING);
        logicCommandCount_++;
        logicComputeCycles_ += reservation.computeCycles;
        logicTransferBytes_ += reservation.transferBytes;
        logicTransferCycles_ += reservation.transferCycles;
        logicServiceCycles_ += reservation.serviceCycles;
        lastLogicServiceCycles_ = static_cast<unsigned>(min<uint64_t>(
            reservation.completionDelay, numeric_limits<unsigned>::max()));
        return lastLogicServiceCycles_;
    }
    const uint64_t units = min<uint64_t>(config.NUM_LOGIC_PIM_UNITS, blocks);
    const uint64_t waves = (blocks + units - 1) / units;
    const uint64_t compute_cycles = waves * config.LOGIC_PIM_LATENCY;
    const uint64_t transfer_bytes = blocks * sizeof(BurstType);
    const uint64_t transfer_cycles =
        (config.LOGIC_PIM_BW == 0)
            ? 0
            : (transfer_bytes + config.LOGIC_PIM_BW - 1) / config.LOGIC_PIM_BW;
    const uint64_t service_cycles = max(compute_cycles, transfer_cycles);
    const uint64_t start_cycle = max(currentClockCycle, logicBusyUntil_);

    logicBusyUntil_ = start_cycle + service_cycles;
    logicCommandCount_++;
    logicComputeCycles_ += compute_cycles;
    logicTransferBytes_ += transfer_bytes;
    logicTransferCycles_ += transfer_cycles;
    logicServiceCycles_ += service_cycles;
    lastLogicServiceCycles_ = static_cast<unsigned>(service_cycles);

    static int reserve_trace_count = 0;
    if (DEBUG_CMD_TRACE && reserve_trace_count < 24)
    {
        cout << "LOGIC_DIE_RESERVE"
             << " cmd[" << cCmd.toStr() << "]"
             << " units[" << units << "]"
             << " waves[" << waves << "]"
             << " compute_cycles[" << compute_cycles << "]"
             << " transfer_bytes[" << transfer_bytes << "]"
             << " transfer_cycles[" << transfer_cycles << "]"
             << " busy_until[" << logicBusyUntil_ << "]" << endl;
        reserve_trace_count++;
    }

    return static_cast<unsigned>(service_cycles);
}

unsigned PIMRank::consumeLastLogicServiceCycles()
{
    unsigned cycles = lastLogicServiceCycles_;
    lastLogicServiceCycles_ = 0;
    return cycles;
}

bool PIMRank::isLogicDieBusy(uint64_t cycle) const
{
    if (!isLogicDieEnabled()) return false;
    return config.LOGIC_GLOBAL_SCHEDULER ? logicScheduler_->isBusy(cycle)
                                         : cycle < logicBusyUntil_;
}

uint64_t PIMRank::getLogicCommandCount() const { return logicCommandCount_; }
uint64_t PIMRank::getLogicComputeCycles() const { return logicComputeCycles_; }
uint64_t PIMRank::getLogicTransferBytes() const { return logicTransferBytes_; }
uint64_t PIMRank::getLogicTransferCycles() const { return logicTransferCycles_; }
uint64_t PIMRank::getLogicServiceCycles() const { return logicServiceCycles_; }

vector<PIMBlock>& PIMRank::getActivePIMBlocks(bool use_logic_die)
{
    return use_logic_die ? logicPimBlocks : pimBlocks;
}

const vector<PIMBlock>& PIMRank::getActivePIMBlocks(bool use_logic_die) const
{
    return use_logic_die ? logicPimBlocks : pimBlocks;
}

void PIMRank::dispatchLogicDieStub(PIMCmd cCmd, BusPacket* packet)
{
    if (DEBUG_CMD_TRACE)
    {
        PRINTC(YELLOW, OUTLOG_ALL("LOGIC_DIE_STUB")
                           << " mode[" << routeModeToStr(getRouteMode()) << "] cmd["
                           << cCmd.toStr() << "]");
    }
    (void)packet;
    throw runtime_error("logic-die execution is not implemented yet in mode " +
                        string(routeModeToStr(getRouteMode())) + " for cmd " + cCmd.toStr());
}

void PIMRank::executeLogicDieCmd(BusPacket* packet, PIMCmd cCmd, int pimblock_id)
{
    BurstType dstBst;
    BurstType src0Bst;
    BurstType src1Bst;

    if (cCmd.type_ == PIMCmdType::MAC)
    {
        static int mac_debug_count = 0;
        if (mac_debug_count < 8)
        {
            cout << "LOGIC_DIE_MAC"
                 << " mode[" << routeModeToStr(getRouteMode()) << "]"
                 << " pb[" << pimblock_id << "]"
                 << " row[" << packet->row << "]"
                 << " col[" << packet->column << "]"
                 << " cmd[" << cCmd.toStr() << "]" << endl;
            mac_debug_count++;
        }
        readOpd(pimblock_id, src0Bst, cCmd.src0_, packet, cCmd.src0Idx_, cCmd.isAuto_, true,
                true);
        readOpd(pimblock_id, src1Bst, cCmd.src1_, packet, cCmd.src1Idx_, cCmd.isAuto_, true,
                true);
        readOpd(pimblock_id, dstBst, cCmd.dst_, packet, cCmd.dstIdx_, cCmd.isAuto_, true, true);
        logicPimBlocks[pimblock_id].mac(dstBst, src0Bst, src1Bst);
        writeOpd(pimblock_id, dstBst, cCmd.dst_, packet, cCmd.dstIdx_, cCmd.isAuto_, true,
                 true);
        return;
    }

    if (cCmd.type_ == PIMCmdType::MAD)
    {
        BurstType dstBst;
        BurstType src0Bst;
        BurstType src1Bst;
        BurstType src2Bst;

        readOpd(pimblock_id, src0Bst, cCmd.src0_, packet, cCmd.src0Idx_, cCmd.isAuto_, true,
                true);
        readOpd(pimblock_id, src1Bst, cCmd.src1_, packet, cCmd.src1Idx_, cCmd.isAuto_, true,
                true);
        readOpd(pimblock_id, src2Bst, cCmd.src2_, packet, cCmd.src2Idx_, cCmd.isAuto_, true,
                true);

        static int mad_debug_count = 0;
        if (mad_debug_count < 4)
        {
            cout << "LOGIC_DIE_MAD"
                 << " mode[" << routeModeToStr(getRouteMode()) << "]"
                 << " pb[" << pimblock_id << "]"
                 << " row[" << packet->row << "]"
                 << " col[" << packet->column << "]"
                 << " cmd[" << cCmd.toStr() << "]" << endl;
            mad_debug_count++;
        }

        logicPimBlocks[pimblock_id].mad(dstBst, src0Bst, src1Bst, src2Bst);
        writeOpd(pimblock_id, dstBst, cCmd.dst_, packet, cCmd.dstIdx_, cCmd.isAuto_, true,
                 true);
        return;
    }

    if (cCmd.type_ == PIMCmdType::MUL)
    {
        BurstType src0Bst;
        BurstType src1Bst;

        if (DEBUG_CMD_TRACE)
        {
            static int mul_debug_count = 0;
            if (mul_debug_count < 8)
            {
                cout << "LOGIC_DIE_MUL"
                     << " mode[" << routeModeToStr(getRouteMode()) << "]"
                     << " pb[" << pimblock_id << "]"
                     << " row[" << packet->row << "]"
                     << " col[" << packet->column << "]"
                     << " cmd[" << cCmd.toStr() << "]" << endl;
                mul_debug_count++;
            }
        }

        readOpd(pimblock_id, src0Bst, cCmd.src0_, packet, cCmd.src0Idx_, cCmd.isAuto_, false,
                true);
        readOpd(pimblock_id, src1Bst, cCmd.src1_, packet, cCmd.src1Idx_, cCmd.isAuto_, false,
                true);
        static int mul_value_debug_count = 0;
        if (mul_value_debug_count < 12)
        {
            cout << "LOGIC_DIE_MUL_VALUES"
                 << " mode[" << routeModeToStr(getRouteMode()) << "]"
                 << " pb[" << pimblock_id << "]"
                 << " row[" << packet->row << "]"
                 << " col[" << packet->column << "]"
                 << " src0[" << src0Bst.fp16Data_[0] << "]"
                 << " src1[" << src1Bst.fp16Data_[0] << "]"
                 << " dst_before[" << dstBst.fp16Data_[0] << "]"
                 << " cmd[" << cCmd.toStr() << "]" << endl;
            mul_value_debug_count++;
        }
        logicPimBlocks[pimblock_id].mul(dstBst, src0Bst, src1Bst);
        writeOpd(pimblock_id, dstBst, cCmd.dst_, packet, cCmd.dstIdx_, cCmd.isAuto_, false,
                 true);
        return;
    }

    throw runtime_error("logic-die execution received unsupported cmd " + cCmd.toStr());
}

void PIMRank::attachRank(Rank* r)
{
    this->rank = r;
}

void PIMRank::setChanId(int id)
{
    this->chanId = id;
}

void PIMRank::setRankId(int id)
{
    this->rankId = id;
}

int PIMRank::getChanId() const
{
    return this->chanId;
}

int PIMRank::getRankId() const
{
    return this->rankId;
}

void PIMRank::update() {}

void PIMRank::controlPIM(BusPacket* packet)
{
    uint8_t grf_a_zeroize = packet->data->u8Data_[20];
    if (grf_a_zeroize)
    {
        if (DEBUG_CMD_TRACE)
        {
            PRINTC(RED, OUTLOG_CH_RA("GRF_A_ZEROIZE"));
        }
        BurstType burst_zero;
        for (int pb = 0; pb < config.NUM_PIM_BLOCKS; pb++)
            for (int i = 0; i < 8; i++)
            {
                if (isBankSideEnabled()) pimBlocks[pb].grfA[i] = burst_zero;
                if (isLogicDieEnabled()) logicPimBlocks[pb].grfA[i] = burst_zero;
            }
    }
    uint8_t grf_b_zeroize = packet->data->u8Data_[21];
    if (grf_b_zeroize)
    {
        if (DEBUG_CMD_TRACE)
        {
            PRINTC(RED, OUTLOG_CH_RA("GRF_B_ZEROIZE"));
        }
        BurstType burst_zero;
        for (int pb = 0; pb < config.NUM_PIM_BLOCKS; pb++)
            for (int i = 0; i < 8; i++)
            {
                if (isBankSideEnabled()) pimBlocks[pb].grfB[i] = burst_zero;
                if (isLogicDieEnabled()) logicPimBlocks[pb].grfB[i] = burst_zero;
            }
    }
    pimOpMode_ = packet->data->u8Data_[0] & 1;
    toggleEvenBank_ = !(packet->data->u8Data_[16] & 1);
    toggleOddBank_ = !(packet->data->u8Data_[16] & 2);
    toggleRa13h_ = (packet->data->u8Data_[16] & 4);

    if (pimOpMode_)
    {
        rank->mode_ = dramMode::HAB_PIM;
        pimPC_ = 0;
        lastJumpIdx_ = numJumpToBeTaken_ = lastRepeatIdx_ = numRepeatToBeDone_ = -1;
        crfExit_ = false;
        PRINTC(RED, OUTLOG_CH_RA("HAB_PIM"));
    }
    else
    {
        rank->mode_ = dramMode::HAB;
        PRINTC(RED, OUTLOG_CH_RA("HAB mode"));
    }
}

bool PIMRank::isToggleCond(BusPacket* packet)
{
    if (pimOpMode_ && !crfExit_)
    {
        if (toggleRa13h_)
        {
            if (toggleEvenBank_ && ((packet->bank & 1) == 0))
                return true;
            else if (toggleOddBank_ && ((packet->bank & 1) == 1))
                return true;
            return false;
        }
        else if (!toggleRa13h_ && !isReservedRA(packet->row))
        {
            if (toggleEvenBank_ && ((packet->bank & 1) == 0))
                return true;
            else if (toggleOddBank_ && ((packet->bank & 1) == 1))
                return true;
            return false;
        }
        return false;
    }
    else
    {
        return false;
    }
}

void PIMRank::readHab(BusPacket* packet)
{
    if (isReservedRA(packet->row))  // ignored
    {
        PRINTC(GRAY, OUTLOG_ALL("READ"));
    }
    else
    {
        PRINTC(GRAY, OUTLOG_ALL("BANK_TO_PIM"));
#ifndef NO_STORAGE
        int grf_id = getGrfIdx(packet->column);
        auto& activeBlocks = getActivePIMBlocks(getRouteMode() == PIMRouteMode::LOGIC_ONLY);
        for (int pb = 0; pb < config.NUM_PIM_BLOCKS; pb++)
        {
            rank->banks[pb * 2 + packet->bank].read(packet);
            activeBlocks[pb].grfB[grf_id] = *(packet->data);
        }
#endif
    }
}

void PIMRank::writeHab(BusPacket* packet)
{
    if (DEBUG_CMD_TRACE)
    {
        PRINTC(GREEN, OUTLOG_ALL("WRITE")
                          << " mode[" << routeModeToStr(getRouteMode()) << "]"
                          << " tag[" << packet->tag << "]"
                          << " row[" << packet->row << "]"
                          << " col[" << packet->column << "]"
                          << " bank[" << packet->bank << "]");
    }

    if (packet->row == config.PIM_REG_RA)  // WRIO to PIM Broadcasting
    {
        if (packet->column == 0x00)
            controlPIM(packet);
        if ((0x08 <= packet->column && packet->column <= 0x0f) ||
            (0x18 <= packet->column && packet->column <= 0x1f))
        {
            if (DEBUG_CMD_TRACE)
            {
                if (packet->column - 8 < 8)
                    PRINTC(GREEN, OUTLOG_B_GRF_A("BWRITE_GRF_A"));
                else
                    PRINTC(GREEN, OUTLOG_B_GRF_B("BWRITE_GRF_B"));
            }
#ifndef NO_STORAGE
            for (int pb = 0; pb < config.NUM_PIM_BLOCKS; pb++)
            {
                if (packet->column - 8 < 8)
                {
                    if (isBankSideEnabled())
                        pimBlocks[pb].grfA[packet->column - 0x8] = *(packet->data);
                    if (isLogicDieEnabled())
                        logicPimBlocks[pb].grfA[packet->column - 0x8] = *(packet->data);
                }
                else
                {
                    if (isBankSideEnabled())
                        pimBlocks[pb].grfB[packet->column - 0x18] = *(packet->data);
                    if (isLogicDieEnabled())
                        logicPimBlocks[pb].grfB[packet->column - 0x18] = *(packet->data);
                }
            }
#endif
        }
        else if (0x04 <= packet->column && packet->column <= 0x07)
        {
            if (DEBUG_CMD_TRACE)
                PRINTC(GREEN, OUTLOG_B_CRF("BWRITE_CRF"));
            crf.bst[packet->column - 0x04] = *(packet->data);
        }
        else if (packet->column == 0x1)
        {
            if (DEBUG_CMD_TRACE)
                PRINTC(GREEN, OUTLOG_CH_RA("BWRITE_SRF"));
            for (int pb = 0; pb < config.NUM_PIM_BLOCKS; pb++)
            {
                if (isBankSideEnabled()) pimBlocks[pb].srf = *(packet->data);
                if (isLogicDieEnabled()) logicPimBlocks[pb].srf = *(packet->data);
            }
        }
    }
    else if (isReservedRA(packet->row))
    {
        PRINTC(GRAY, OUTLOG_ALL("WRITE"));
    }
    else  // PIM (only GRF) to Bank Move
    {
        PRINTC(GREEN, OUTLOG_ALL("PIM_TO_BANK"));

#ifndef NO_STORAGE
        int grf_id = getGrfIdx(packet->column);
        auto& activeBlocks = getActivePIMBlocks(getRouteMode() == PIMRouteMode::LOGIC_ONLY);
        if (packet->tag.find("GRFB_TO_BANK_") != std::string::npos)
        {
            static int logic_wb_dbg = 0;
            if (logic_wb_dbg < 24)
            {
                cout << "LOGIC_DIE_WRITEBACK"
                     << " mode[" << routeModeToStr(getRouteMode()) << "]"
                     << " pb[all]"
                     << " bank[" << packet->bank << "]"
                     << " row[" << packet->row << "]"
                     << " col[" << packet->column << "]"
                     << " grf[" << grf_id << "]"
                     << " tag[" << packet->tag << "]" << endl;
                logic_wb_dbg++;
            }
        }
        for (int pb = 0; pb < config.NUM_PIM_BLOCKS; pb++)
        {
            if (packet->bank == 0)
            {
                *(packet->data) = activeBlocks[pb].grfA[grf_id];
                rank->banks[pb * 2].write(packet);  // basically read from bank;
            }
            else if (packet->bank == 1)
            {
                *(packet->data) = activeBlocks[pb].grfB[grf_id];
                rank->banks[pb * 2 + 1].write(packet);  // basically read from bank.
            }
        }
#endif
    }
}

void PIMRank::readOpd(int pb, BurstType& bst, PIMOpdType type, BusPacket* packet, int idx,
                      bool is_auto, bool is_mac, bool use_logic_die)
{
    idx = getGrfIdx(idx);
    auto& activeBlocks = getActivePIMBlocks(use_logic_die);

    switch (type)
    {
        case PIMOpdType::A_OUT:
            bst = activeBlocks[pb].aOut;
            return;
        case PIMOpdType::M_OUT:
            bst = activeBlocks[pb].mOut;
            return;
        case PIMOpdType::EVEN_BANK:
            if (packet->bank % 2 != 0)
                PRINT("Warning, CRF bank coding and bank id from packet are inconsistent");
            if (!(use_logic_die && config.LOGIC_SHARED_WEIGHT_BUFFER &&
                  logicWeightBuffer_->isActive() &&
                  logicWeightBuffer_->read(chanId, rankId, pb * 2, packet->row, packet->column,
                                           bst)))
            {
                rank->banks[pb * 2].read(packet);  // basically read from bank.
                bst = *(packet->data);
            }
            return;
        case PIMOpdType::ODD_BANK:
            if (packet->bank % 2 == 0)
                PRINT("Warning, CRF bank coding and bank id from packet are inconsistent");
            if (!(use_logic_die && config.LOGIC_SHARED_WEIGHT_BUFFER &&
                  logicWeightBuffer_->isActive() &&
                  logicWeightBuffer_->read(chanId, rankId, pb * 2 + 1, packet->row,
                                           packet->column, bst)))
            {
                rank->banks[pb * 2 + 1].read(packet);  // basically read from bank.
                bst = *(packet->data);
            }
            return;
        case PIMOpdType::GRF_A:
            bst = activeBlocks[pb].grfA[(is_auto) ? getGrfIdx(packet->column) : idx];
            return;
        case PIMOpdType::GRF_B:
            if (is_auto)
            {
                int grf_id = (is_mac) ? getGrfIdxHigh(packet->row, packet->column)
                                      : getGrfIdx(packet->column);
                if (DEBUG_CMD_TRACE && use_logic_die)
                {
                    PRINTC(MAGENTA, OUTLOG_GRF_B("LD_READ_GRF_B")
                                         << " grf[" << grf_id << "]"
                                         << " auto[" << is_auto << "]"
                                         << " mac[" << is_mac << "]");
                }
                bst = activeBlocks[pb].grfB[grf_id];
            }
            else
                bst = activeBlocks[pb].grfB[idx];
            return;
        case PIMOpdType::SRF_M:
            bst.set(activeBlocks[pb].srf.fp16Data_[idx]);
            return;
        case PIMOpdType::SRF_A:
            bst.set(activeBlocks[pb].srf.fp16Data_[idx + 8]);
            return;
    }
}

void PIMRank::writeOpd(int pb, BurstType& bst, PIMOpdType type, BusPacket* packet, int idx,
                       bool is_auto, bool is_mac, bool use_logic_die)
{
    idx = getGrfIdx(idx);
    auto& activeBlocks = getActivePIMBlocks(use_logic_die);

    switch (type)
    {
        case PIMOpdType::A_OUT:
            activeBlocks[pb].aOut = bst;
            return;
        case PIMOpdType::M_OUT:
            activeBlocks[pb].mOut = bst;
            return;
        case PIMOpdType::EVEN_BANK:
            if (packet->bank % 2 != 0)
            {
                PRINT("CRF bank coding and bank id from packet are inconsistent");
            }
            if (!use_logic_die)
            {
                static int bank_side_write_dbg = 0;
                if (bank_side_write_dbg < 12)
                {
                    cout << "BANK_SIDE_BANK_WRITE"
                         << " pb[" << pb << "]"
                         << " bank[" << packet->bank << "]"
                         << " row[" << packet->row << "]"
                         << " col[" << packet->column << "]"
                         << " v0[" << bst.fp16Data_[0] << "]" << endl;
                    bank_side_write_dbg++;
                }
            }
            *(packet->data) = bst;
            rank->banks[pb * 2].write(packet);  // basically read from bank.
            return;
        case PIMOpdType::ODD_BANK:
            if (packet->bank % 2 == 0)
            {
                PRINT("CRF bank coding and bank id from packet are inconsistent");
                exit(-1);
            }
            *(packet->data) = bst;
            rank->banks[pb * 2 + 1].write(packet);  // basically read from bank.
            return;
        case PIMOpdType::GRF_A:
            activeBlocks[pb].grfA[(is_auto) ? getGrfIdx(packet->column) : idx] = bst;
            return;
        case PIMOpdType::GRF_B:
            if (is_auto)
            {
                int grf_id = (is_mac) ? getGrfIdxHigh(packet->row, packet->column)
                                      : getGrfIdx(packet->column);
                if (!use_logic_die)
                {
                    static int bank_side_grf_dbg = 0;
                    if (bank_side_grf_dbg < 12)
                    {
                        cout << "BANK_SIDE_GRF_B_WRITE"
                             << " pb[" << pb << "]"
                             << " grf[" << grf_id << "]"
                             << " auto[" << is_auto << "]"
                             << " mac[" << is_mac << "]"
                             << " row[" << packet->row << "]"
                             << " col[" << packet->column << "]"
                             << " v0[" << bst.fp16Data_[0] << "]" << endl;
                        bank_side_grf_dbg++;
                    }
                }
                if (DEBUG_CMD_TRACE && use_logic_die)
                {
                    PRINTC(MAGENTA, OUTLOG_GRF_B("LD_WRITE_GRF_B")
                                         << " grf[" << grf_id << "]"
                                         << " auto[" << is_auto << "]"
                                         << " mac[" << is_mac << "]");
                }
                activeBlocks[pb].grfB[grf_id] = bst;
            }
            else
                activeBlocks[pb].grfB[idx] = bst;
            return;
        case PIMOpdType::SRF_M:
            activeBlocks[pb].srf = bst;
            return;
        case PIMOpdType::SRF_A:
            activeBlocks[pb].srf = bst;
            return;
    }
}

void PIMRank::doPIM(BusPacket* packet)
{
    PIMCmd cCmd;
    packet->row = masked2accessibleRA(packet->row);
    do
    {
        cCmd.fromInt(crf.data[pimPC_]);
        if (DEBUG_CMD_TRACE)
        {
            PRINTC(CYAN, string((packet->busPacketType == READ) ? "READ ch" : "WRITE ch")
                             << getChanId() << " ra" << getRankId() << " bg"
                             << config.addrMapping.bankgroupId(packet->bank) << " b" << packet->bank
                             << " r" << packet->row << " c" << packet->column << "|| [" << pimPC_
                             << "] " << cCmd.toStr() << " @ " << currentClockCycle);
        }

        if (cCmd.type_ == PIMCmdType::EXIT)
        {
            crfExit_ = true;
            break;
        }
        else if (cCmd.type_ == PIMCmdType::JUMP)
        {
            if (lastJumpIdx_ != pimPC_)
            {
                if (cCmd.loopCounter_ > 0)
                {
                    lastJumpIdx_ = pimPC_;
                    numJumpToBeTaken_ = cCmd.loopCounter_;
                }
            }
            if (numJumpToBeTaken_ > 0)
            {
                pimPC_ -= cCmd.loopOffset_;
                numJumpToBeTaken_--;
            }
        }
        else
        {
            reserveLogicDie(cCmd);
            if (cCmd.type_ == PIMCmdType::FILL || cCmd.isAuto_)
            {
                if (lastRepeatIdx_ != pimPC_)
                {
                    lastRepeatIdx_ = pimPC_;
                    numRepeatToBeDone_ = 8 - 1;
                }

                if (numRepeatToBeDone_ > 0)
                {
                    pimPC_ -= 1;
                    numRepeatToBeDone_--;
                }
                else
                    lastRepeatIdx_ = -1;
            }
            else if (cCmd.type_ == PIMCmdType::NOP)
            {
                if (lastRepeatIdx_ != pimPC_)
                {
                    lastRepeatIdx_ = pimPC_;
                    numRepeatToBeDone_ = cCmd.loopCounter_;
                }

                if (numRepeatToBeDone_ > 0)
                {
                    pimPC_ -= 1;
                    numRepeatToBeDone_--;
                }
                else
                    lastRepeatIdx_ = -1;
            }

            for (int pimblock_id = 0; pimblock_id < config.NUM_PIM_BLOCKS; pimblock_id++)
            {
                doPIMBlock(packet, cCmd, pimblock_id);

                if (DEBUG_PIM_BLOCK && pimblock_id == 0)
                {
                    PRINT("[BANK_R]" << packet->data->fp16ToStr());
                    PRINT("[CMD]" << bitset<32>(cCmd.toInt()) << "(" << cCmd.toStr() << ")");
                    PRINT(pimBlocks[pimblock_id].print());
                    PRINT("----------");
                }
            }
        }
        pimPC_++;
        // EXIT check
        PIMCmd next_cmd;
        next_cmd.fromInt(crf.data[pimPC_]);
        if (next_cmd.type_ == PIMCmdType::EXIT)
            crfExit_ = true;
    } while (cCmd.type_ == PIMCmdType::JUMP);
}

void PIMRank::doPIMBlock(BusPacket* packet, PIMCmd cCmd, int pimblock_id)
{
    auto isEltwiseWritebackTag = [](const std::string& tag) {
        return tag.find("GRF_TO_BANK") != std::string::npos ||
               tag.find("GRF_A_TO_EVEN_BANK") != std::string::npos ||
               tag.find("GRF_B_TO_ODD_BANK") != std::string::npos ||
               tag.find("GRFB_TO_BANK_") != std::string::npos;
    };

    static int block_trace_count = 0;
    if (block_trace_count < 24)
    {
        cout << "PIMBLOCK_DISPATCH"
             << " mode[" << routeModeToStr(getRouteMode()) << "]"
             << " pb[" << pimblock_id << "]"
             << " busType[" << ((packet->busPacketType == READ) ? "READ" : "WRITE") << "]"
             << " row[" << packet->row << "]"
             << " col[" << packet->column << "]"
             << " cmd[" << cCmd.toStr() << "]"
             << " logicEnabled[" << isLogicDieEnabled() << "]"
             << " bankEnabled[" << isBankSideEnabled() << "]" << endl;
        block_trace_count++;
    }

    if (packet->busPacketType == WRITE &&
        packet->tag.find("GRFB_TO_BANK_") != std::string::npos)
    {
        const int grf_id = getGrfIdx(packet->column);
        const bool use_logic_die = getRouteMode() != PIMRouteMode::BANK_ONLY;
        auto& activeBlocks = getActivePIMBlocks(use_logic_die);
        *(packet->data) = activeBlocks[pimblock_id].grfB[grf_id];
        rank->banks[pimblock_id * 2 + 1].write(packet);
        return;
    }

    if (shouldRouteToLogicDie(cCmd))
    {
        static int route_debug_count = 0;
        if (route_debug_count < 12)
        {
            cout << "ROUTE_LOGIC_DIE"
                 << " mode[" << routeModeToStr(getRouteMode()) << "]"
                 << " pb[" << pimblock_id << "]"
                 << " cmd[" << cCmd.toStr() << "]" << endl;
            route_debug_count++;
        }
        executeLogicDieCmd(packet, cCmd, pimblock_id);
        return;
    }

    if (cCmd.type_ == PIMCmdType::NOP)
    {
        static int logic_nop_enter_count = 0;
        if (logic_nop_enter_count < 20)
        {
            cout << "LOGIC_DIE_NOP_ENTER"
                 << " mode[" << routeModeToStr(getRouteMode()) << "]"
                 << " pb[" << pimblock_id << "]"
                 << " busType[" << ((packet->busPacketType == READ) ? "READ" : "WRITE") << "]"
                 << " row[" << packet->row << "]"
                 << " col[" << packet->column << "]"
                 << " cmd[" << cCmd.toStr() << "]" << endl;
            logic_nop_enter_count++;
        }
        if (DEBUG_CMD_TRACE)
        {
            PRINTC(YELLOW, OUTLOG_ALL("LOGIC_DIE_NOP")
                               << " mode[" << routeModeToStr(getRouteMode()) << "] cmd["
                               << cCmd.toStr() << "]");
        }
        if (packet->busPacketType == WRITE && isEltwiseWritebackTag(packet->tag))
        {
            int grf_id = getGrfIdx(packet->column);
            bool logic_writeback =
                packet->tag.find("GRFB_TO_BANK_") != std::string::npos &&
                getRouteMode() != PIMRouteMode::BANK_ONLY;
            auto& activeBlocks = getActivePIMBlocks(logic_writeback);
            static int bank_nop_eltwise_wb_dbg = 0;
            if (bank_nop_eltwise_wb_dbg < 24)
            {
                cout << "BANK_SIDE_NOP_WRITEBACK"
                     << " mode[" << routeModeToStr(getRouteMode()) << "]"
                     << " pb[" << pimblock_id << "]"
                     << " bank[" << packet->bank << "]"
                     << " row[" << packet->row << "]"
                     << " col[" << packet->column << "]"
                     << " grf[" << grf_id << "]"
                     << " tag[" << packet->tag << "]" << endl;
                bank_nop_eltwise_wb_dbg++;
            }
            if (packet->bank == 0)
            {
                *(packet->data) = activeBlocks[pimblock_id].grfA[grf_id];
                rank->banks[pimblock_id * 2].write(packet);
            }
            else if (packet->bank == 1)
            {
                *(packet->data) = activeBlocks[pimblock_id].grfB[grf_id];
                rank->banks[pimblock_id * 2 + 1].write(packet);
            }
            return;
        }
        if (isLogicDieEnabled() && packet->busPacketType == WRITE)
        {
            int grf_id = getGrfIdx(packet->column);
            auto& activeBlocks = getActivePIMBlocks(getRouteMode() == PIMRouteMode::LOGIC_ONLY);
            static int logic_nop_debug_count = 0;
            if (logic_nop_debug_count < 12)
            {
                cout << "LOGIC_DIE_NOP_WRITE"
                     << " mode[" << routeModeToStr(getRouteMode()) << "]"
                     << " row[" << packet->row << "]"
                     << " col[" << packet->column << "]"
                     << " bank[" << packet->bank << "]"
                     << " grf[" << grf_id << "]"
                     << " cmd[" << cCmd.toStr() << "]" << endl;
                logic_nop_debug_count++;
            }
            if (packet->bank == 0)
            {
                *(packet->data) = activeBlocks[pimblock_id].grfA[grf_id];
                rank->banks[pimblock_id * 2].write(packet);
            }
            else if (packet->bank == 1)
            {
                *(packet->data) = activeBlocks[pimblock_id].grfB[grf_id];
                rank->banks[pimblock_id * 2 + 1].write(packet);
            }

            if (isLogicDieEnabled() && !isBankSideEnabled())
            {
                BusPacket mirror_packet(*packet);
                if (packet->bank == 0)
                {
                    *(mirror_packet.data) = activeBlocks[pimblock_id].grfA[grf_id];
                    mirror_packet.bank = 1;
                    rank->banks[pimblock_id * 2 + 1].write(&mirror_packet);
                }
                else if (packet->bank == 1)
                {
                    *(mirror_packet.data) = activeBlocks[pimblock_id].grfB[grf_id];
                    mirror_packet.bank = 0;
                    rank->banks[pimblock_id * 2].write(&mirror_packet);
                }
            }
        }
        return;
    }

    if (!isBankSideEnabled())
    {
        throw runtime_error("bank-side PIM path is disabled for cmd " + cCmd.toStr());
    }

    if (cCmd.type_ == PIMCmdType::FILL || cCmd.type_ == PIMCmdType::MOV)
    {
        BurstType bst;
        bool is_auto = (cCmd.type_ == PIMCmdType::FILL) ? true : false;

        if (packet->busPacketType == WRITE && isEltwiseWritebackTag(packet->tag))
        {
            int grf_id = getGrfIdx(packet->column);
            static int eltwise_wb_dbg = 0;
            if (eltwise_wb_dbg < 24)
            {
                cout << "BANK_SIDE_ELTWISE_WRITEBACK"
                     << " pb[" << pimblock_id << "]"
                     << " bank[" << packet->bank << "]"
                     << " row[" << packet->row << "]"
                     << " col[" << packet->column << "]"
                     << " grf[" << grf_id << "]"
                     << " tag[" << packet->tag << "]" << endl;
                eltwise_wb_dbg++;
            }
            if (packet->bank == 0)
                rank->banks[pimblock_id * 2].write(packet);
            else if (packet->bank == 1)
                rank->banks[pimblock_id * 2 + 1].write(packet);
            return;
        }

        readOpd(pimblock_id, bst, cCmd.src0_, packet, cCmd.src0Idx_, is_auto, false, false);
        if (cCmd.isRelu_)
        {
            for (int i = 0; i < 16; i++)
                bst.u16Data_[i] = (bst.u16Data_[i] & (1 << 15)) ? 0 : bst.u16Data_[i];
        }
        writeOpd(pimblock_id, bst, cCmd.dst_, packet, cCmd.dstIdx_, is_auto, false, false);
    }
    else if (cCmd.type_ == PIMCmdType::ADD || cCmd.type_ == PIMCmdType::MUL)
    {
        BurstType dstBst;
        BurstType src0Bst;
        BurstType src1Bst;

        if (packet->busPacketType == WRITE && isEltwiseWritebackTag(packet->tag))
        {
            int grf_id = getGrfIdx(packet->column);
            auto& activeBlocks = getActivePIMBlocks(false);
            static int eltwise_wb_dbg = 0;
            if (eltwise_wb_dbg < 24)
            {
                cout << "BANK_SIDE_ELTWISE_WRITEBACK"
                     << " pb[" << pimblock_id << "]"
                     << " bank[" << packet->bank << "]"
                     << " row[" << packet->row << "]"
                     << " col[" << packet->column << "]"
                     << " grf[" << grf_id << "]"
                     << " tag[" << packet->tag << "]" << endl;
                eltwise_wb_dbg++;
            }
            if (packet->bank == 0)
            {
                *(packet->data) = activeBlocks[pimblock_id].grfA[grf_id];
                rank->banks[pimblock_id * 2].write(packet);
            }
            else if (packet->bank == 1)
            {
                *(packet->data) = activeBlocks[pimblock_id].grfB[grf_id];
                rank->banks[pimblock_id * 2 + 1].write(packet);
            }
            return;
        }

        readOpd(pimblock_id, src0Bst, cCmd.src0_, packet, cCmd.src0Idx_, cCmd.isAuto_, false,
                false);
        readOpd(pimblock_id, src1Bst, cCmd.src1_, packet, cCmd.src1Idx_, cCmd.isAuto_, false,
                false);

        if (cCmd.type_ == PIMCmdType::ADD)
            // dstBst = src0Bst + src1Bst;
            pimBlocks[pimblock_id].add(dstBst, src0Bst, src1Bst);
        else if (cCmd.type_ == PIMCmdType::MUL)
            // dstBst = src0Bst * src1Bst;
            pimBlocks[pimblock_id].mul(dstBst, src0Bst, src1Bst);

        writeOpd(pimblock_id, dstBst, cCmd.dst_, packet, cCmd.dstIdx_, cCmd.isAuto_, false,
                 false);
    }
    else if (cCmd.type_ == PIMCmdType::MAC || cCmd.type_ == PIMCmdType::MAD)
    {
        BurstType dstBst;
        BurstType src0Bst;
        BurstType src1Bst;
        bool is_mac = (cCmd.type_ == PIMCmdType::MAC) ? true : false;

        readOpd(pimblock_id, src0Bst, cCmd.src0_, packet, cCmd.src0Idx_, cCmd.isAuto_, is_mac,
                false);
        readOpd(pimblock_id, src1Bst, cCmd.src1_, packet, cCmd.src1Idx_, cCmd.isAuto_, is_mac,
                false);
        if (is_mac)
        {
            readOpd(pimblock_id, dstBst, cCmd.dst_, packet, cCmd.dstIdx_, cCmd.isAuto_, is_mac,
                    false);
            // dstBst = src0Bst * src1Bst + dstBst;
            pimBlocks[pimblock_id].mac(dstBst, src0Bst, src1Bst);
        }
        else
        {
            BurstType src2Bst;
            readOpd(pimblock_id, src2Bst, cCmd.src2_, packet, cCmd.src2Idx_, cCmd.isAuto_,
                    is_mac, false);
            // dstBst = src0Bst * src1Bst + src2Bst;
            pimBlocks[pimblock_id].mad(dstBst, src0Bst, src1Bst, src2Bst);
        }

        writeOpd(pimblock_id, dstBst, cCmd.dst_, packet, cCmd.dstIdx_, cCmd.isAuto_, is_mac,
                 false);

        if (getRouteMode() != PIMRouteMode::LOGIC_ONLY &&
            cCmd.type_ == PIMCmdType::MAC && packet->busPacketType == WRITE)
        {
            int grf_id = getGrfIdxHigh(packet->row, packet->column);
            static int bank_mac_wb_dbg = 0;
            if (bank_mac_wb_dbg < 16)
            {
                cout << "BANK_SIDE_MAC_WRITEBACK"
                     << " pb[" << pimblock_id << "]"
                     << " bank[" << packet->bank << "]"
                     << " grf[" << grf_id << "]"
                     << " row[" << packet->row << "]"
                     << " col[" << packet->column << "]"
                     << " v0[" << dstBst.fp16Data_[0] << "]" << endl;
                bank_mac_wb_dbg++;
            }
            BusPacket wb_packet(*packet);
            *(wb_packet.data) = getActivePIMBlocks(false)[pimblock_id].grfB[grf_id];
            if (packet->bank == 0)
            {
                rank->banks[pimblock_id * 2].write(&wb_packet);
            }
            else if (packet->bank == 1)
            {
                rank->banks[pimblock_id * 2 + 1].write(&wb_packet);
            }
        }
    }
}
