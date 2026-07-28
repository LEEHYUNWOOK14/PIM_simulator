# Emulator API

## 개요

`emulator_api`는 실제 장치에서 PIM 커널을 실행하는 대신, PIM 커널이 생성하는 메모리 접근 trace를 기록하고 이를 PIMSimulator에 입력하기 위한 소스 코드다.

즉, 호스트 또는 PIM SDK에서 발생한 메모리 요청을 시뮬레이터의 메모리 트랜잭션으로 변환해, 실제 실행 환경과 유사한 PIM 동작을 사이클 단위로 분석할 수 있다.

이 API는 기본 빌드에 포함된다. Emulator API가 필요하지 않으면 다음과 같이 제외할 수 있다.

```bash
scons NO_EMUL=1
```

자세한 사용 방법은 루트의 [PIMSimulator 프로젝트 설명서](../../PIMSimulator_GUIDE.md)를 참고한다.
