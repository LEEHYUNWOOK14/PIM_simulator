# WSL 수동 ext4 복구 검색 게이트 실패 보고

## 작업 일자

- 2026-08-03

## 요청 요약

- `TestA_WSL_manual_ext4_recovery_search_prompt.md` 지시에 따라 WSL ext4 내부에서 `ControlledValidation.cpp`와 `TestA_ExactBank_MOV` 원본 후보를 검색해야 했다.
- 해당 프롬프트는 사용자가 직접 연 WSL Ubuntu 터미널 안에서만 수행하도록 명시했다.

## 수행한 게이트 확인

PowerShell에서 WSL 접근 가능 여부만 확인했다.

```powershell
wsl --status
wsl --list --verbose
wsl -- bash -lc "set -u; echo '=== WSL ACCESS GATE ==='; date -Is; uname -a; pwd; whoami; printf 'HOME=%s\n' \"$HOME\"; id"
```

## 결과

- `wsl --status`: 실패
- `wsl --list --verbose`: 실패
- `wsl -- bash -lc ...`: 실패
- 오류: `E_ACCESSDENIED`

## 판단

WSL 배포판 열거와 인스턴스 생성이 모두 거부되었다.

따라서 `/home/chandler`, `/home/chandler/projects`, VS Code Server history, WSL Git refs/reflog/stash/fsck, `/tmp`, `/var/tmp` 검색을 수행할 수 없었다.

## 수행하지 않은 것

- `ControlledValidation.cpp`를 새로 작성하지 않았다.
- `TestA_ExactBank_MOV`를 추정 복구하지 않았다.
- 생산 코드를 수정하지 않았다.
- Git reset, clean, restore를 실행하지 않았다.
- candidate를 checkout에 적용하지 않았다.
- TestA smoke를 실행하지 않았다.

## 다음 최소 조치

사용자가 WSL Ubuntu 터미널을 직접 열고, 아래 Windows 파일에 있는 수동 검색 명령을 WSL 안에서 실행해야 한다.

- `C:\Users\Chandler\Downloads\TestA_WSL_manual_ext4_recovery_search_prompt.md`

또는 이전에 만든 안내 파일을 사용할 수 있다.

- `C:\home\chandler\projects\STOB_PIM2_recovery_artifacts\missing_test_source_search\wsl_manual_search_instructions.md`

WSL 검색 결과 디렉터리 `$HOME/TestA_source_recovery_wsl/run_<timestamp>`가 생성되면, 그 결과를 바탕으로 원본 후보 발견 여부를 다시 판정할 수 있다.
