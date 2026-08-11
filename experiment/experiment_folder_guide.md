# 실험 폴더 안내

이 폴더에는 실제 실험에 필요한 파일만 둔다.

현재 들어있는 파일:

- [실험계획서.md](./experiment_plan.md)
- [run_first_experiments.sh](./run_first_experiments.sh)
- [run_routing_checks.sh](./run_routing_checks.sh)
- [run_routing_checks.md](./run_routing_checks.md)
- [gr00t_placement/README.md](./gr00t_placement/README.md)

## 왜 스크립트가 필요한가

계획서만 있으면 읽는 데는 좋지만, 바로 실행하기는 어렵다.  
그래서 실험 폴더에는 계획서와 함께 실제 실행 스크립트를 두는 것이 맞다.

## 실행 방법

WSL Ubuntu 터미널에서 아래처럼 실행한다.

```bash
bash experiment/run_first_experiments.sh
```

라우팅 모드 검증은 아래처럼 실행한다.

```bash
bash experiment/run_routing_checks.sh
```

또는 실행 권한을 준 뒤 직접 실행할 수 있다.

```bash
chmod +x experiment/run_first_experiments.sh
./experiment/run_first_experiments.sh
```



