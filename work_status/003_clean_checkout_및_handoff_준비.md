# Clean Checkout 및 WSL Handoff 준비 보고

## 완료한 작업

- 원본 OneDrive 저장소에서 detached clean worktree를 만들었다.
- clean checkout 경로는 `C:\home\chandler\projects\STOB_PIM2_bank_validation_recovered`이다.
- clean checkout HEAD는 `7d20f19e3394bf33448e594d33b10f0d164ff8cd`이다.
- clean checkout의 `git status --short`는 비어 있어 깨끗하다.
- 원본 dirty diff와 status 증거를 `C:\home\chandler\projects\STOB_PIM2_recovery_artifacts`에 저장했다.
- WSL handoff 패키지를 `C:\home\chandler\projects\STOB_PIM2_recovery_artifacts\wsl_handoff`에 만들었다.

## 중요한 차단 조건

- clean checkout에도 `src/tests/ControlledValidation.cpp`가 없다.
- `TestA_ExactBank_MOV` 문자열도 현재 checkout과 로컬 Git history에서 발견되지 않았다.
- 따라서 현재 source만으로는 TestA smoke 재실행을 할 수 없다.

## WSL 관련 상태

- 현재 PowerShell 환경에서는 `wsl --status`, `wsl --list --verbose`가 `E_ACCESSDENIED`로 실패한다.
- WSL 안에서 수동으로 handoff source를 복사한 뒤 `resume_in_wsl.sh`를 실행해야 한다.

## 다음 최소 작업

- `ControlledValidation.cpp`가 포함된 실제 commit, archive, 또는 작업 트리를 찾아야 한다.
- 그 후 WSL에서 handoff gate script를 실행하고 TestA smoke 재실행으로 넘어갈 수 있다.
