# 라우팅 검증 실행 파일 설명

이 파일은 [run_routing_checks.sh](./run_routing_checks.sh)의 사용법과 동작을 설명한다.

## 이 스크립트가 하는 일

1. `system_hbm.ini`와 `system_hbm_64ch.ini`를 백업한다.
2. bank-side only, logic-die only, hybrid 순서로 설정을 바꾼다.
3. 각 모드에서 지정한 `PIMKernelFixture` 테스트를 실행한다.
4. 끝나면 원래 설정 파일로 복원한다.

즉, 사람이 직접 ini 파일을 세 번 바꾸지 않아도
모드별 실행을 한 번에 재현할 수 있게 해주는 도구다.

## 실행 순서

### 1. bank-side only

설정:

- `ENABLE_BANK_SIDE_PIM=true`
- `ENABLE_LOGIC_DIE_PIM=false`
- `PIM_TARGET=bank_side`

실행 테스트:

- `PIMKernelFixture.add`
- `PIMKernelFixture.relu`
- `PIMKernelFixture.mul`
- `PIMKernelFixture.gemv`
- `PIMKernelFixture.gemv_tree`

의미:

- 기존 bank-side 경로가 아직 정상인지 확인한다.

### 2. logic-die only

설정:

- `ENABLE_BANK_SIDE_PIM=false`
- `ENABLE_LOGIC_DIE_PIM=true`
- `PIM_TARGET=logic_die`

실행 테스트:

- `PIMKernelFixture.gemv`
- `PIMKernelFixture.gemv_tree`

의미:

- logic-die 경로가 분리 인식되는지 확인한다.
- 현재 구현상 logic-die 연산은 stub 예외로 멈출 수 있다.

### 3. hybrid

설정:

- `ENABLE_BANK_SIDE_PIM=true`
- `ENABLE_LOGIC_DIE_PIM=true`
- `PIM_TARGET=hybrid`

실행 테스트:

- `PIMKernelFixture.add`
- `PIMKernelFixture.relu`
- `PIMKernelFixture.mul`
- `PIMKernelFixture.gemv`

의미:

- bank-side와 logic-die가 같은 설정에서 어떻게 갈리는지 본다.

## 실행 방법

WSL 터미널에서 아래처럼 실행한다.

```bash
bash experiment/run_routing_checks.sh
```

필요하면 실행 권한을 줄 수 있다.

```bash
chmod +x experiment/run_routing_checks.sh
./experiment/run_routing_checks.sh
```

## 주의점

- 이 스크립트는 실행 중 ini 파일을 수정한다.
- 그러나 종료 시 원래 파일로 복구하도록 되어 있다.
- `./sim`이 이미 빌드되어 있어야 한다.

