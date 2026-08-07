# Power/Performance 파이프라인

## 목적

열 모델에 공급된 전력, DRAM 명령 이벤트, HBM2 인터페이스 사양 및 workload 처리량을 결합해 에너지와 성능을 동시에 평가한다.

## 지표

```text
theoretical_bandwidth_GBs = stacks × bus_width_bits/8 × pin_rate_Gbps
bandwidth_utilization = measured_or_simulated_bandwidth / theoretical_bandwidth
energy_per_bit_pJ = total_power_W / transferred_bits_per_second × 1e12
energy_per_operation = total_energy / completed_useful_operations
performance_per_watt = completed_useful_operations_per_second / total_power_W
speedup = candidate_execution_time^-1 / baseline_execution_time^-1
```

성능/비용 순위에는 workload 최소 메모리 용량을 hard constraint로 적용한다. 8Gb die를 1GB로 환산한 공개 제품 구성을 기준으로 기본 workload는 8GB를 요구한다. 따라서 4Hi는 비용 참고값은 출력하지만 기본 8GB workload의 feasible 후보에서는 제외된다.

HBM2의 1,024 data I/O와 제품별 pin rate는 제조사 공개자료로 검증할 수 있다. 예를 들어 Samsung Aquabolt는 2.4 Gbps/pin, 1.2 V, 307 GB/s/stack을 공개한다. 이는 특정 프로젝트 RTL의 달성 대역폭이 아니라 이론 상한 검증점이다.

## 전력 출처 계층

1. 측정 또는 보정된 전력 trace
2. post-layout activity 기반 power
3. RTL VCD/SAIF + library power
4. DRAMsim3 공개 IDD/명령 모델
5. synthetic architectural profile

분모가 다른 지표를 섞지 않는다. `operation` 정의, 포함한 전력 범위(DRAM only/package/system), 시간구간을 출력에 기록한다. 대역폭이 0이면 energy/bit를 계산하지 않는다.

## 열 제약 결합

온도는 비용에 중복 가산하지 않고 feasibility constraint로 사용한다.

```text
feasible = peak_temperature <= configured_limit
thermal_throttle_penalty = achieved_performance / unthrottled_performance
```

현재 thermal 결과가 synthetic이면 penalty도 illustrative로 유지한다.

## 검증

- `bus_width/8 × rate`로 제조사 공개 대역폭 재현
- 음수 전력·시간·트랜잭션 거부
- 총 에너지와 interval power 적분 보존
- 이론 대역폭 초과 시 실패 또는 명시적 overcommit 경고
- 동일 workload에서 완료 작업 수 보존
