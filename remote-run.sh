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

  echo "[*] ($TARGET:$SSH_PORT) 코드 준비(없으면 clone, 있으면 pull)..."
  "${SSH[@]}" "$TARGET" "if [ -d '$REMOTE_DIR/.git' ]; then cd '$REMOTE_DIR' && (git pull -q || true); else echo '  → 최초 설치: git clone'; git clone -q '$REPO_URL' '$REMOTE_DIR'; fi"

  echo "[*] ($TARGET) 실행: rehearse.sh $REHEARSE_ARGS"
  if [ -n "$SUDO_PASSWORD" ]; then
    "${SSH[@]}" "$TARGET" "cd '$REMOTE_DIR' && sudo -S -p '' ./rehearse.sh $REHEARSE_ARGS" <<< "$SUDO_PASSWORD"
  else
    "${SSH[@]}" "$TARGET" "cd '$REMOTE_DIR' && sudo ./rehearse.sh $REHEARSE_ARGS"
  fi

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
for conf in "${CONFS[@]}"; do
  i=$((i+1))
  echo "════════════════════════════════════════  [$i/$total] $conf"
  if ( run_one "$conf" ); then :; else echo "[x] 실패: $conf (다음 서버 계속)"; rc=1; fi
done
echo "════════════════════════════════════════  완료 (${total}대)"
exit $rc
