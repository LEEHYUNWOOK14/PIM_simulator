# TestA 원본 소스 출처 조사 시작

## 작업 목표

- `ControlledValidation.cpp`와 `TestA_ExactBank_MOV`의 실제 출처를 찾는다.
- Git refs, stash, reflog, dangling object, 인접 worktree, archive/patch, VS Code/Codex history를 조사한다.
- 후보가 발견되어도 clean checkout에 바로 적용하지 않는다.

## 현재 원칙

- 원본 dirty tree는 수정하지 않는다.
- TestA를 새로 작성하지 않는다.
- 생산 코드 semantics는 변경하지 않는다.
- TestA smoke는 실행하지 않는다.

## 산출물 위치

- `C:\home\chandler\projects\STOB_PIM2_recovery_artifacts\missing_test_source_search`

## 조사 완료 요약

- Git refs, stash, reflog, dangling object에서 원본 후보를 찾지 못했다.
- 등록된 worktree와 제한된 filesystem 검색에서도 실제 `ControlledValidation.cpp` 후보는 없었다.
- Downloads와 Codex 기록에는 관련 문자열이 있었지만, 모두 작업 지시/대화/보고 흔적이었다.
- `run_testa_timeoutdiag.sh`는 TestA 이름을 알고 있던 보조 증거지만 테스트 구현 파일은 아니다.
- WSL 접근은 여전히 `E_ACCESSDENIED`라서 WSL ext4 내부에만 남아 있을 가능성은 배제할 수 없다.

## 결론

- Windows 쪽에서 복구 가능한 원본 소스 provenance는 발견되지 않았다.
- 다음 최소 작업은 WSL 안에서 `/home/chandler/projects`를 직접 검색하는 것이다.
