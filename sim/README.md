# LSD Simulation — Makefile 사용법

이 디렉토리의 `Makefile` 은 대규모 RTL 설계 (`rtl/`) 를 UVM 테스트벤치 (`tb/`) 와
함께 **Questasim 2025.3** 에서 컴파일·최적화·시뮬레이션하는 전체 플로우를 감쌉니다.
모든 단계는 한 번의 `make` 명령으로 돌아가고, 엔진·디버그 모드·시뮬 길이 등
주요 노브는 CLI 변수로 조절할 수 있습니다.

---

## 1. 사전 준비

| 항목 | 필요 버전 | 비고 |
|---|---|---|
| Questasim | 2025.3 이상 | `vlog`, `vopt`, `vsim`, `qopt`, `qsim`, `qrun`, `vlib`, `vmap` 이 PATH에 있어야 함 |
| Python | 3.7+ | `gen_bloat.py` 가 파일 생성 |
| Make | GNU Make 4+ | Windows면 Git-Bash / MSYS / WSL 권장 |
| UVM | 1.2 (precompiled) | Questa 가 `mtiUvm` 라이브러리로 기본 제공 — 별도 설치 불필요 |

Windows (PowerShell / Git-Bash) 에서 그대로 동작합니다.

---

## 2. Quick start

```bash
cd sim

# 가장 빠른 경로 — 짧은 스모크 테스트, 기본 엔진(vsim), 기본 디버그 모드(vis)
make smokesim

# 전체 스트레스 테스트
make sim

# 다음-세대 Questa One Sim 엔진으로 동일 워크로드
make sim ENGINE=qsim

# 현재 노브 값 확인
make info

# 빌드 산출물 정리
make clean
```

시뮬레이션이 끝나면 아래 "파형 열기" 섹션을 참고해서 Visualizer 또는
ModelSim GUI 로 파형을 로드합니다.

---

## 3. 주요 변수 (CLI로 override)

| 변수 | 기본값 | 의미 | 예시 |
|---|---|---|---|
| `ENGINE` | `vsim` | 시뮬레이션 엔진. `vsim` (전통), `qsim` (Questa One), `qrun` (1-step) | `make sim ENGINE=qsim` |
| `TEST` | `lsd_smoke_test` | UVM 테스트 이름 (`+UVM_TESTNAME` 으로 전달) | `make run TEST=lsd_stress_test` |
| `DEBUG` | `vis` | 디버그/파형 모드. `wlf` (classic) 또는 `vis` (Visualizer) | `make sim DEBUG=wlf` |
| `RUN` | `-all` | vsim `-do "run ..."` 에 들어갈 run 표현식 | `make smokesim RUN="1 us"` |
| `SEED` | `1` | `-sv_seed` 로 전달되는 난수 seed | `make sim SEED=42` |
| `VERB` | `UVM_MEDIUM` | `+UVM_VERBOSITY` | `make sim VERB=UVM_HIGH` |
| `BLOAT_COUNT` | `2000` | 자동 생성되는 유니크 RTL 모듈 개수 | `make sim BLOAT_COUNT=10000` |
| `HEARTBEAT` | `10000` | tb_top 진척 로그 주기 (시뮬 ns) | `make sim HEARTBEAT=1000` |

조합 예:
```bash
make sim ENGINE=qsim TEST=lsd_stress_test SEED=777 HEARTBEAT=5000
make smokesim RUN="500 ns" VERB=UVM_HIGH
make stress BLOAT_COUNT=30000 DEBUG=vis
```

### 변수 간 제약
- `ENGINE=qsim` 또는 `ENGINE=qrun` 일 때 `DEBUG=wlf` 는 불가 → 자동으로
  `DEBUG=vis` 로 승격되면서 경고를 출력합니다.
- `RUN` 에 공백이 들어가면 **쉘 따옴표 필수**: `RUN="1 us"` (따옴표 없으면
  `us` 가 make 타겟으로 파싱됨).

---

## 4. 타겟 목록

| 타겟 | 설명 |
|---|---|
| `make sim` | 스트레스 테스트 (`lsd_stress_test`) 전체 플로우 — 컴파일 → 최적화 → 실행 |
| `make smokesim` | 짧은 스모크 테스트 (`lsd_smoke_test`) |
| `make bmtsim` | 기본 블록 테스트 (`lsd_bmt_test`) |
| `make stress` | 스트레스 테스트 (sim 과 동일) |
| `make compile` | `vlog` 만 실행 — RTL + TB 컴파일 |
| `make optimize` | `compile` 후 `vopt` / `qopt` 실행 |
| `make run` | `optimize` 후 `vsim` / `qsim` / `qrun` 실행 |
| `make run_vsim` / `run_qsim` / `run_qrun` | 엔진별 run 타겟 (상위에서 dispatch) |
| `make gen` | bloat-farm 자동 생성 (`BLOAT_COUNT` 반영) |
| `make workdir` | `vlib work` / `vmap` 초기화 |
| `make info` | 현재 설정된 모든 노브 값 출력 |
| `make clean` | 빌드 산출물 전부 삭제 |
| `make all` | `sim` 과 동일 (기본 타겟) |

---

## 5. 디버그/파형 모드

파형은 **항상 덤프됩니다**. 종료 후 별도로 뷰어를 열어 확인합니다.

### `DEBUG=wlf` — 전통 WLF 플로우
- `vopt` 플래그: `+acc=npr` (net/port/register 가시화)
- `vsim` 플래그: `-wlf vsim.wlf`
- **ENGINE=vsim 에서만 유효**
- 시뮬 후 확인:
  ```bash
  vsim -view vsim.wlf
  ```
  또는 ModelSim GUI 에서 File > Open > WLF.

### `DEBUG=vis` — Visualizer 플로우 (기본)
- `vopt` 플래그: `-debug +designfile` (→ `design.bin` 자동 생성)
- `vsim` 플래그: `-qwavedb=+signal+class`
- **ENGINE 무관** — qsim / qrun 에서는 이 모드만 가능
- `+acc` 옵션과 **동시 사용 불가** (Questa 제약)
- 시뮬 후 확인: Siemens Visualizer 실행 후 `design.bin` + `*.qwavedb` open.

### 모드별 차이 요약
| 항목 | `DEBUG=wlf` | `DEBUG=vis` |
|---|---|---|
| vopt 플래그 | `+acc=npr` | `-debug +designfile` |
| vsim 플래그 | `-wlf vsim.wlf` | `-qwavedb=+signal+class` |
| 파형 파일 | `vsim.wlf` | `design.bin` + `*.qwavedb` |
| 지원 엔진 | vsim only | vsim / qsim / qrun |
| 뷰어 | ModelSim GUI / `vsim -view` | Siemens Visualizer |
| 성능 부하 | 낮음 | 중간 (class 객체까지 캡처) |

---

## 6. 시뮬레이션 진척 로그 (heartbeat)

긴 테스트가 살아있는지 확인할 수 있도록 `tb_top` 이 주기적으로 진척 로그를
stdout / log 파일에 출력합니다.

```
[tb_top] heartbeat period = 10000 ns (override with +heartbeat=<ns>)
[tb_top] HB#1 t=10100000  cmd=843  rsp=840  in=1987 out=102  d_cmd=843
[tb_top] HB#2 t=20100000  cmd=2016 rsp=2010 in=3978 out=249  d_cmd=1173
[tb_top] HB#3 t=30100000  cmd=2016 rsp=2010 in=3978 out=249  d_cmd=0   [STALL?]
...
[tb_top] FINAL t=92100000 cmd=10000 rsp=9998 in=16384 out=1402 heartbeats=10
```

- `cmd` / `rsp` / `in` / `out` : cmd path · response · input stream · output stream 핸드셰이크 누적 카운트
- `d_cmd` : 이전 heartbeat 이후 cmd 증가량. 연속으로 0이면 `[STALL?]` 태그 자동 첨부
- 주기 변경: `make sim HEARTBEAT=1000` (1µs 간격) 또는 `HEARTBEAT=100000` (100µs 간격)

UVM 시퀀스도 5% 간격으로 `UVM_INFO` 로 진행률을 찍습니다:
```
UVM_INFO @ 21100: [HEAVY]  progress 500/10000 (5%)
UVM_INFO @ 31100: [STREAM] beat 1000/16384 (6%)
```

---

## 7. 자주 쓰는 사용 시나리오

### (a) 기능 sanity — 짧고 빠르게
```bash
make smokesim
```

### (b) 짧은 시간만 돌려서 리그레션 체크
```bash
make sim RUN="100 us" SEED=1
make sim RUN="100 us" SEED=2
make sim RUN="100 us" SEED=3
```

### (c) 전부 실행 (시뮬이 자연 종료할 때까지)
```bash
make sim                     # RUN=-all
```

### (d) 시뮬레이터 킬러 — 많은 유니크 모듈 + 긴 실행
```bash
make sim BLOAT_COUNT=30000 RUN="1 ms"
```

### (e) 디버그용 — Visualizer에서 전체 class 객체까지 dump
```bash
make sim DEBUG=vis TEST=lsd_smoke_test VERB=UVM_HIGH
# 종료 후 Visualizer 실행 → design.bin 로드 → qwavedb 추가
```

### (f) qrun 1-step 플로우로 원샷 실행
```bash
make sim ENGINE=qrun
```

### (g) 기존 vlib/work 재사용 (gen 건너뛰고 재컴파일만)
```bash
make compile
make optimize
make run
```

---

## 8. 산출물/로그 파일

`make` 실행 후 `sim/` 아래 생성되는 파일들:

| 파일 | 단계 | 내용 |
|---|---|---|
| `work/` | vlib | Questa working library |
| `vlog.log` | vlog (RTL) | RTL 컴파일 로그 |
| `vlog_tb.log` | vlog (TB) | UVM TB 컴파일 로그 |
| `vopt.log` / `qopt.log` | vopt/qopt | 최적화 로그 |
| `vsim.log` / `qsim.log` / `qrun.log` | run | 시뮬레이션 런타임 로그 (heartbeat 포함) |
| `tb_top_opt` | vopt | 최적화된 탑 모듈 (vsim이 로드) |
| `vsim.wlf` | run (`DEBUG=wlf`) | classic 파형 |
| `design.bin` | vopt (`DEBUG=vis`) | Visualizer 디자인 DB |
| `*.qwavedb` | run (`DEBUG=vis`) | Visualizer 파형 DB |
| `covhtmlreport/` | coverage 실행 | 커버리지 리포트 (옵션) |
| `transcript` | vsim | ModelSim 트랜스크립트 |

`make clean` 으로 모두 제거됩니다.

---

## 9. BLOAT_COUNT 와 스케일

`BLOAT_COUNT` 는 `rtl/gen/` 아래 자동 생성되는 유니크 모듈 개수입니다.
각 모듈은 구조적으로 다른 LFSR polynomial / 파이프 깊이 / mix 상수 / 연산 시퀀스를
가지므로 elaborator가 merge 할 수 없습니다 — 설계 전체 규모를 임의로 키울 수 있습니다.

실용 가이드 (약 16-core / 32 GB 워크스테이션 기준):

| Value   | Compile   | vopt      | 실행 성능   | 용도 |
|---------|-----------|-----------|------------|------|
| 500     | ~5 s      | ~15 s     | 빠름       | 디버그 / 반복 |
| 2000    | ~30 s     | ~60 s     | 보통       | 기본 스트레스 |
| 10000   | ~5-10 min | ~5 min    | 느림       | 실제 스트레스 |
| 30000   | ~30 min   | ~20 min   | 매우 느림  | 극한 스트레스 |
| 100000  | 수 시간   | 수 시간   | grinding   | simulator-killer |

`BLOAT_COUNT > 9999` 로 가려면 `tools/gen_bloat.py` 의 파일명 포맷
`{idx:04d}` 를 `{idx:06d}` 로 수정하길 권장 (정렬 순서 유지).

---

## 10. 트러블슈팅

### `vlog` 에러에서 "-uvm is not a valid option"
- `vlog` 는 `-uvm` 플래그가 없습니다. 이 Makefile은 `-L mtiUvm` 으로 UVM 을 링크합니다.
  직접 vlog 를 호출하려면 `-L mtiUvm` 을 붙이세요.

### `vopt` 에러 "Illegal assignment to type 'enum ...' from type 'bit'"
- enum 필드를 가진 packed struct를 `'{default:'0}` 으로 초기화하면 안 됩니다.
  `'0` (integral zero-fill) 또는 멤버를 명시적으로 적으세요.

### `vsim` 에러 vsim-8754 / vsim-12460 (analysis imp 타입 충돌)
- 스코어보드에 서로 다른 타입의 `uvm_analysis_imp` 를 여러 개 두려면
  `uvm_analysis_imp_decl(_suffix)` 로 decorator 매크로를 선언해야 합니다.
  (이미 `lsd_uvm_pkg.sv` 에 적용됨.)

### 시뮬이 진행되는지 불확실할 때
- heartbeat 주기를 짧게: `make sim HEARTBEAT=1000` (1µs)
- `d_cmd=0` 이 연속으로 찍히면 cmd path 블록, `in=...` 만 증가하면 특정 subsystem backpressure.

### qsim 에서 `DEBUG=wlf` 로 돌리고 싶은데 안 된다
- qsim / qrun 은 Visualizer 플로우만 지원 → 자동으로 `DEBUG=vis` 로 승격됩니다.

### filelist에서 `-f` 로 include한 하위 filelist의 경로
- Questa는 하위 filelist의 **cwd (sim/) 기준 상대경로** 로 해석합니다.
  `rtl/gen/gen_filelist.f` 도 `../rtl/gen/` 접두사가 붙은 경로를 사용합니다.

### `make clean` 후에도 `modelsim.ini` 가 남아있다
- `modelsim.ini` 는 Questa가 런타임에 생성합니다. 정상 동작에 영향 없음.

---

## 11. 디렉토리 관계

```
test_lsd/
├── rtl/              # 설계 소스 (common, cnn, crypto, graphics, calu, eccd, gen, top)
├── tb/               # UVM 테스트벤치 (pkg, seq, tests, top)
└── sim/              # ← 여기. Makefile, 파일리스트, 실행
    ├── Makefile
    ├── README.md           (이 문서)
    ├── rtl_filelist.f
    ├── tb_filelist.f
    └── tools/
        └── gen_bloat.py    # 유니크 모듈 자동 생성 스크립트
```

---

## 12. 기본 워크플로우 요약

```
make gen            →  rtl/gen/ 에 BLOAT_COUNT 개의 유니크 SV 모듈 생성
make compile        →  vlog (RTL + TB) → work/
make optimize       →  vopt/qopt → tb_top_opt
make run            →  vsim/qsim/qrun 실행 → 파형 + 로그
make clean          →  모든 빌드 산출물 제거
```

상위 타겟(`sim`, `smokesim`, `bmtsim`, `stress`)은 위 4단계를 자동으로 연결해서
한 번에 실행합니다. CLI 변수로 필요한 부분만 override 하면 됩니다.
