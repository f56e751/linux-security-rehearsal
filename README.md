# linux-security-rehearsal

서울대 원격 서비스 포트 신청 절차의 **리눅스 보안점검 전체 흐름**을
**테스트 서버에서 안전하게 리허설**하기 위한 도구입니다.

```
백업 → 점검 → 조치(하드닝) → 재점검 → 복원 → 복원검증
```

## ⚠️ 용도와 범위 (먼저 읽어주세요)

- **테스트/개인 장비 전용**입니다. 운영 서버에서 `all`(자동 복원 포함)을 돌리지 마세요.
- 이 도구가 만드는 결과 파일은 **연습/자체점검용**이며 **보안팀 제출용이 아닙니다**.
  - 실제 포트 신청은 운영 서버에서 조치를 **유지한 상태**로 공식 스크립트를 돌려
    나온 결과 파일을 제출해야 합니다. 조치를 되돌린 채 '안전' 결과만 제출하는 것은
    실제 서버 상태와 다른 허위 보고가 되므로 이 도구의 목적이 아닙니다.
- 문서 경고대로, **잘못된 설정은 로그인/SSH 접속 불능**을 유발할 수 있습니다.
  콘솔 접근이 가능한 환경에서 실행하세요.

## 구성

```
rehearse.sh          # 메인 오케스트레이터
lib/common.sh        # 로깅 / root 확인 / 배포판 감지 / 설정값 편집(idempotent)
lib/backup.sh        # 백업 / 복원 (manifest 기반 정확한 원상복구)
lib/remediate.sh     # 보안 조치(복잡성 / 계정 잠금 / 패스워드 정책)
lib/check_local.sh   # 점검 실행(공식 스크립트 우선, 없으면 자체 점검)
Linux_Password_Check.sh   # (선택) 학내망에서 받은 공식 스크립트를 여기에 두면 우선 사용
```

## 한 번에 실행 (권장)

전체 흐름을 한 줄로 실행합니다.

```bash
sudo ./rehearse.sh all --no-mark -y
```

순서대로 수행됩니다:

```
STEP 1/6  백업
STEP 2/6  조치 전 점검
STEP 3/6  보안 조치(하드닝)
STEP 4/6  조치 후 재점검   ← 통과 결과 파일 생성
STEP 5/6  원본 설정으로 복원
STEP 6/6  복원 검증(백업과 바이트 단위 대조)
```

끝나면 자동화에 넣을 **통과 결과 파일 경로**를 출력합니다:

```
[+] 리허설 완료.
[*]   · 백업: backups/2026-07-07_...
[+]   · 통과 결과 파일(자동화 입력용) →  results/<host>-linux-result-....txt
```

내 검증 자동화에 바로 연결:

```bash
sudo ./rehearse.sh all --no-mark -y
PASS=$(ls -t results/*.txt | head -1)   # 방금 생성된 통과 파일
./내검증스크립트.sh "$PASS"              # 본인 자동화에 입력
```

> `--no-mark` = 마커 없는 결과 파일 / `-y` = 확인 프롬프트 생략(무인 실행).
> `all` 은 마지막에 자동 복원하므로 **테스트 서버 전용**입니다. 운영 서버에 강화를
> 유지하려면 `all` 대신 `backup` + `apply` 만 쓰고 `restore` 는 하지 마세요.

## 노트북에서 원격 한 방에 (remote-run.sh)

서버에 SSH 접속 → `git pull` → `sudo ./rehearse.sh all --fetch --no-mark -y` →
**결과 txt 를 노트북으로 자동 복사**까지 한 번에.

```bash
# 서버 1대
cp remote.conf.example remote.conf     # 값 채우기 (IP / 사용자 / sudo 비번)
chmod 600 remote.conf
./remote-run.sh

# 여러 대 — 서버당 설정 파일 하나씩
cp remote.conf.example robot4.conf
cp remote.conf.example robot5.conf     # 각각 값 채우고 chmod 600
./remote-run.sh robot4.conf robot5.conf
./remote-run.sh servers/*.conf         # 폴더 전체도 가능
```

- 여러 대를 넘기면 **순차 실행**하고, 한 대가 실패해도 **나머지는 계속**(종료코드 1로 알림)
- **자동 설치**: 서버에 도구가 없으면 `git clone`, git 자체가 없으면 apt/dnf/yum 으로 설치까지 시도
- 결과는 서버별로 `~/Downloads/<HOST>-results/` 에 **분리 저장**
- 로그인은 **SSH 키**(권장, 앞서 등록) 또는 `SSH_LOGIN_PASSWORD` + sshpass
- `SUDO_PASSWORD` 는 서버 sudo 용 (비우면 NOPASSWD sudo 가정)
- ⚠️ `*.conf` 는 **비밀번호 평문**이라 `.gitignore` 처리됨 — 공유/커밋 금지, 권한 600 유지

## 사용법

```bash
chmod +x rehearse.sh

# 1) 무엇이 바뀌는지 먼저 확인 (변경 없음)
sudo ./rehearse.sh all --dry-run

# 2) 실제 리허설 (백업 → 점검 → 조치 → 재점검 → 복원 → 검증)
sudo ./rehearse.sh all --no-mark -y

# 개별 명령
sudo ./rehearse.sh backup     # 백업만
sudo ./rehearse.sh check      # 점검만
./rehearse.sh show            # 현재 설정 값 출력(안전/취약 판정 없이, 권한 불필요)
sudo ./rehearse.sh fetch      # 공식 점검 스크립트 다운로드(학내망 전용)
sudo ./rehearse.sh apply      # 조치만 (복원하지 않음 — 운영 서버 실제 적용용)
sudo ./rehearse.sh restore    # 가장 최근 백업으로 복원
sudo ./rehearse.sh restore backups/2024-...   # 특정 백업으로 복원
sudo ./rehearse.sh verify     # 현재 설정이 백업과 일치하는지(=원복 완료) 검증
sudo ./rehearse.sh list       # 백업 목록
```

옵션: `--dry-run`(모의 실행), `--no-mark`(자체점검 결과에서 '리허설/비공식' 표시 제거), `--yes`/`-y`(확인 생략).

`verify` 는 관리 대상 파일이 백업과 **바이트 단위로 일치**하는지 확인하고, 모두 일치하면
종료코드 `0`, 하나라도 다르면 `1` 을 반환합니다(본인 자동화에서 판정용으로 사용 가능).
파일 권한 문제로 diff 가 막히면 `sudo` 로 실행하세요.

## 점검/조치 기준 (문서 근거)

| 항목 | 기준 | 설정 파일 |
|---|---|---|
| 패스워드 복잡성 | lcredit/ocredit/dcredit = `-1` | `pwquality.conf` (RHEL7+/Ubuntu) 또는 PAM |
| 계정 잠금 임계값 | `deny` ≤ 10 | `faillock.conf` 또는 PAM |
| 최소 길이 | `PASS_MIN_LEN` ≥ 8 | `/etc/login.defs` |
| 최대 사용기간 | `PASS_MAX_DAYS` ≤ 90 | `/etc/login.defs` |
| 최소 사용기간 | `PASS_MIN_DAYS` ≥ 1 | `/etc/login.defs` |

## 안전 설계

- **정확한 원상복구**: 백업 시 각 파일의 존재 여부를 manifest 에 기록하고,
  복원 시 원래 있던 파일은 되돌리고, 조치 중 새로 생긴 파일은 삭제합니다.
- **idempotent 편집**: 같은 키가 있으면 그 줄만 교체, 없으면 추가. 파일 권한 유지.
- **배포판 감지**: RHEL/Debian 계열과 버전을 확인해 알맞은 파일을 조치.
  PAM(system-auth/common-auth) 모듈 편집은 배포판 편차가 커서 best-effort이며,
  라인이 없으면 건너뛰고 경고합니다(수동 확인 권장).

## 공식 스크립트 연동

`Linux_Password_Check.sh` 가 이 폴더에 있으면 `check`/`all` 이 자체 점검 대신
공식 스크립트를 실행하고, **공식 형식 결과 파일**을 만듭니다.

**자동 다운로드** — `--fetch` 또는 `fetch` 명령:

```bash
sudo ./rehearse.sh fetch                 # 공식 스크립트만 내려받기
sudo ./rehearse.sh all --fetch --no-mark -y   # 다운로드 후 곧바로 리허설
```

**수동 다운로드**도 가능:

```bash
wget http://snucert.snu.ac.kr/Password_Check/Linux_Password_Check.sh   # 학내망 전용
# 안 되면: curl -O http://snucert.snu.ac.kr/Password_Check/Linux_Password_Check.sh
```

주의:
- **학내망(SNU)에서만** 다운로드됩니다. 교외망이면 실패하고 자동으로 **자체 점검**으로 넘어갑니다(중단 없음).
- HTTP 로 받아 `sudo` 로 실행되므로, 교내망과 snucert 서버를 신뢰하는 환경에서만 쓰세요(안내문 절차와 동일).
- 이 파일은 `.gitignore` 대상이라 git 에 올라가지 않습니다(장비마다 각자 받는 것).
