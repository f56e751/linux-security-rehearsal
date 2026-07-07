#!/usr/bin/env bash
#
# remote-run.sh — 노트북에서 실행하는 원격 러너 (여러 서버 지원)
#   각 서버에 SSH 접속 → git pull → sudo ./rehearse.sh <ARGS> → 결과 txt 를 노트북으로 가져옴.
#
#   준비:  서버마다 설정 파일 하나씩
#          cp remote.conf.example robot4.conf   (값 채우고 chmod 600)
#          cp remote.conf.example robot5.conf
#   실행:  ./remote-run.sh robot4.conf robot5.conf     # 여러 대
#          ./remote-run.sh                              # 인자 없으면 remote.conf 하나
#          ./remote-run.sh servers/*.conf               # 폴더 전체
#
# 로그인은 SSH 키(권장) 또는 sshpass 비번, sudo 는 설정파일의 SUDO_PASSWORD 사용.
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 서버 한 대 처리 (서브셸에서 호출 → 설정 변수가 서버 간에 섞이지 않음)
run_one() {
  set -e
  local CONF="$1"
  if [ ! -f "$CONF" ]; then echo "[x] 설정 파일 없음: $CONF"; return 1; fi
  chmod 600 "$CONF" 2>/dev/null || true
  # shellcheck disable=SC1090
  source "$CONF"
  : "${HOST:?$CONF 에 HOST 설정 필요}"
  : "${USER:?$CONF 에 USER 설정 필요}"
  local SSH_PORT="${SSH_PORT:-22}"
  local REMOTE_DIR="${REMOTE_DIR:-/home/$USER/Documents/linux-security-rehearsal}"
  local LOCAL_DIR="${LOCAL_DIR:-$HOME/Downloads/${HOST}-results}"
  local REHEARSE_ARGS="${REHEARSE_ARGS:-all --fetch --no-mark -y}"
  local REPO_URL="${REPO_URL:-https://github.com/f56e751/linux-security-rehearsal.git}"
  local SUDO_PASSWORD="${SUDO_PASSWORD:-}"
  local SSH_LOGIN_PASSWORD="${SSH_LOGIN_PASSWORD:-}"
  mkdir -p "$LOCAL_DIR"

  local SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
  local SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
  local -a SSH SCP
  if [ -n "$SSH_LOGIN_PASSWORD" ]; then
    command -v sshpass >/dev/null 2>&1 || { echo "[x] sshpass 미설치 → 'brew install sshpass' 하거나 SSH 키 사용"; return 1; }
    export SSHPASS="$SSH_LOGIN_PASSWORD"
    SSH=(sshpass -e ssh "${SSH_OPTS[@]}"); SCP=(sshpass -e scp "${SCP_OPTS[@]}")
  else
    SSH=(ssh "${SSH_OPTS[@]}"); SCP=(scp "${SCP_OPTS[@]}")
  fi
  local TARGET="$USER@$HOST"

  # 접속 확인 (실패 사유는 위에 뜨는 SSH 오류로 확인: 타임아웃/거부/인증실패 등)
  echo "[*] ($TARGET:$SSH_PORT) 접속 확인..."
  if "${SSH[@]}" "$TARGET" true; then
    echo "[+] ($TARGET) 접속 OK"
  else
    echo "[x] ($TARGET) 접속 실패 — 건너뜀"
    return 1
  fi

  # sudo 실행 방식: 비번 있으면 stdin(-S), 없으면 NOPASSWD 가정
  local SUDO_CMD; if [ -n "$SUDO_PASSWORD" ]; then SUDO_CMD="sudo -S -p ''"; else SUDO_CMD="sudo"; fi
  ssh_sudo() {  # 원격 명령을 실행하되, 비번이 설정돼 있으면 stdin 으로 전달
    if [ -n "$SUDO_PASSWORD" ]; then "${SSH[@]}" "$TARGET" "$1" <<< "$SUDO_PASSWORD"
    else "${SSH[@]}" "$TARGET" "$1"; fi
  }

  echo "[*] ($TARGET:$SSH_PORT) 준비: git 확인/설치 → clone 또는 pull..."
  ssh_sudo "
    if ! command -v git >/dev/null 2>&1; then
      echo '  → git 미설치: 설치 시도';
      if   command -v apt-get >/dev/null 2>&1; then $SUDO_CMD sh -c 'apt-get update -qq && apt-get install -y -qq git';
      elif command -v dnf     >/dev/null 2>&1; then $SUDO_CMD dnf install -y -q git;
      elif command -v yum     >/dev/null 2>&1; then $SUDO_CMD yum install -y -q git;
      else echo '  [!] 패키지 관리자를 못 찾음 — git 을 수동 설치하세요'; fi;
    fi;
    if [ -d '$REMOTE_DIR/.git' ]; then cd '$REMOTE_DIR' && (git pull -q || true);
    else echo '  → 최초 설치: git clone'; git clone -q '$REPO_URL' '$REMOTE_DIR'; fi
  "

  echo "[*] ($TARGET) 실행: rehearse.sh $REHEARSE_ARGS"
  ssh_sudo "cd '$REMOTE_DIR' && $SUDO_CMD ./rehearse.sh $REHEARSE_ARGS"

  echo "[*] 최신 결과 파일 확인..."
  local LATEST
  LATEST="$("${SSH[@]}" "$TARGET" "ls -t '$REMOTE_DIR'/results/*.txt 2>/dev/null | head -1" || true)"
  if [ -z "$LATEST" ]; then echo "[x] 결과 txt 를 찾지 못함 ($REMOTE_DIR/results)"; return 1; fi
  echo "[*] 가져오기: $LATEST"
  "${SCP[@]}" "$TARGET:$LATEST" "$LOCAL_DIR/"
  echo "[+] 완료 → $LOCAL_DIR/$(basename "$LATEST")"
}

# ----- 설정 파일 목록 결정 -----
CONFS=("$@")
if [ ${#CONFS[@]} -eq 0 ]; then CONFS=("$HERE/remote.conf"); fi

rc=0
total=${#CONFS[@]}
i=0
ok_n=0; fail_n=0; OK_NAMES=""; FAIL_NAMES=""   # 문자열 누적(bash 3.2 호환)
for conf in "${CONFS[@]}"; do
  i=$((i+1))
  name="$(basename "$conf" .conf)"
  echo "════════════════════════════════════════  [$i/$total] $name"
  if ( run_one "$conf" ); then
    ok_n=$((ok_n+1)); OK_NAMES="$OK_NAMES $name"
  else
    echo "[x] 실패: $name (다음 서버 계속)"
    fail_n=$((fail_n+1)); FAIL_NAMES="$FAIL_NAMES $name"; rc=1
  fi
done

echo
echo "════════════════════════ 요약 (총 ${total}대) ════════════════════════"
echo "  ✔ 성공 ${ok_n}:${OK_NAMES:-  (없음)}"
echo "  ✘ 실패 ${fail_n}:${FAIL_NAMES:-  (없음)}"
if [ "$fail_n" -gt 0 ]; then
  echo "  · 실패 서버 원인은 위 로그에서 해당 이름으로 검색해 확인하세요."
  echo "  · 결과 파일은 노트북의 ~/Downloads/<HOST>-results/ 에 서버별로 저장됩니다."
fi
exit $rc
