# WSL ext4 TestA 소스 복구 게이트 보고

## 작업 상태

- 상태: 실패 / 중단
- 중단 단계: WSL 접근 게이트
- 작업 일자: 2026-08-03

## 수행한 확인

다음 명령으로 WSL 접근 여부를 확인했다.

```powershell
wsl --status
wsl --list --verbose
wsl -- bash -lc "set -u; uname -a; pwd; whoami; printf 'HOME=%s\n' \"$HOME\""
```

## 결과

- `wsl --status`: 실패
- `wsl --list --verbose`: 실패
- `wsl -- bash -lc ...`: 실패
- 공통 오류: `E_ACCESSDENIED`

## 판단

이번 지시서는 반드시 WSL Ubuntu shell 내부에서 `/home/chandler`와 `/home/chandler/projects`를 조사하도록 되어 있다.

현재 PowerShell에서 WSL 배포판 열거와 인스턴스 생성이 모두 거부되므로, WSL ext4 내부 검색을 수행할 수 없다.

## 수행하지 않은 것

- TestA를 새로 작성하지 않았다.
- `ControlledValidation.cpp`를 추정 복구하지 않았다.
- 생산 코드 semantics를 변경하지 않았다.
- 원본 저장소를 reset, clean, restore 하지 않았다.
- TestA smoke를 실행하지 않았다.

## 다음 최소 조치

WSL 터미널을 사용자가 직접 열 수 있는 상태에서 아래 파일의 수동 검색 명령을 실행해야 한다.

- `C:\home\chandler\projects\STOB_PIM2_recovery_artifacts\missing_test_source_search\wsl_manual_search_instructions.md`

WSL 접근이 복구되면 `$HOME/TestA_source_recovery_wsl` 아래에 조사 결과를 만들고, `ControlledValidation.cpp` 원본 후보가 있는지 다시 판정할 수 있다.
