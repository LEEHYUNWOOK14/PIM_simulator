# AUD-001~008 RTL 수정 계약

이 문서는 2026-08-07 production RTL 수정의 판정 기준이다. 우선순위는 C++ simulator, 기존 명령 encoding, 명시적인 ready/valid 안전 규칙 순이다.

1. **AUD-001 FP16**: `fp16_mul`은 repository `lib/half.h`의 round-to-nearest-even 결과와 bit 단위로 일치해야 한다. NaN payload는 canonical quiet NaN `0x7e00`을 허용한다. MAC/MAD는 C++ `PIMBlock.cpp`처럼 rounded multiply 후 rounded add다.
2. **AUD-002 DRAM response**: `read_valid_o && !read_ready_i` 동안 `read_valid_o`와 `read_data_o`가 안정적이어야 하며 새 RD는 승인하지 않는다.
3. **AUD-003 bank operand**: 명령이 참조하는 EVEN/ODD bank operand마다 `pim_read_valid`가 참이어야만 모든 local PIM block이 원자적으로 commit한다. register-only 명령은 bank open을 요구하지 않는다.
4. **AUD-004 CRF JUMP**: C++ `PIMRank.cpp`와 같이 JUMP PC를 처음 만났을 때 count를 load하고 정확히 count회 backward jump한 뒤 다음 PC로 진행한다.
5. **AUD-005 illegal command**: illegal CRF word는 architectural state/result를 변경하지 않고 한 cycle error를 보고한 뒤 retire하여 CRF 전체를 deadlock시키지 않는다.
6. **AUD-006 epoch**: logic command는 matching epoch가 begin되고 expected fill mask가 완성되어 release된 뒤에만 dispatch한다. release authorization은 execution completion까지 유지된다.
7. **AUD-007 metadata**: transaction tag와 source channel은 독립 metadata다. tag 하위 bit로 channel을 재구성하지 않는다. bank context key도 logic 경로에서 보존한다.
8. **AUD-008 end-to-end**: coalesced logic command의 PCU partial은 내부 arbiter를 거쳐 expected channel mask 기반 FP16 reduction으로 들어가며, 완료 결과는 ISA destination에 따라 bank 또는 host result interface로 전달된다. shared weight buffer는 적어도 context-valid/read-response가 dispatch gate와 operand 선택에 실제로 참여해야 한다.

기존 raw/debug output을 유지하더라도 reduction handshake와 충돌하거나 같은 partial을 두 번 소비해서는 안 된다. 모든 수정은 기존 감사 반례가 더 이상 결함을 재현하지 못하도록 하고, 별도의 positive regression으로 기대 동작을 증명해야 한다.
