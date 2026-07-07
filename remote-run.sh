#!/usr/bin/env bash
#
# remote-run.sh — 노트북에서 실행하는 원격 러너
#   서버에 SSH 접속 → git pull → sudo ./rehearse.sh <ARGS> → 최신 결과 txt 를 노트북으로 가져옴.
#
#   준비:  cp remote.conf.example remote.conf   (값 채우고 chmod 600)
#   실행:  ./remote-run.sh                       (또는 ./remote-run.sh 다른설정.conf)
#
# 로그인은 SSH 키(권장) 또는 sshpass 비번, sudo 는 설정파일의 SUDO_PASSWORD 사용.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${1:-$HERE/remote.conf}"

if [ ! -f "$CONF" ]; then
  echo "설정 파일이 없습니다: $CONF"
  echo "  cp '$HERE/remote.conf.example' '$HERE/remote.conf' 후 값을 채우세요."
  exit 1
fi
chmod 600 "$CONF" 2>/dev/null || true      # 비번 파일이므로 소유자만 접근

# shellcheck disable=SC1090
source "$CONF"
: "${HOST:?HOST 를 remote.conf 에 설정하세요}"
: "${USER:?USER 를 remote.conf 에 설정하세요}"
SSH_PORT="${SSH_PORT:-22}"
REMOTE_DIR="${REMOTE_DIR:-/home/$USER/Documents/linux-security-rehearsal}"
LOCAL_DIR="${LOCAL_DIR:-$HOME/Downloads/${HOST}-results}"
REHEARSE_ARGS="${REHEARSE_ARGS:-all --fetch --no-mark -y}"
SUDO_PASSWORD="${SUDO_PASSWORD:-}"
SSH_LOGIN_PASSWORD="${SSH_LOGIN_PASSWORD:-}"
mkdir -p "$LOCAL_DIR"

# ssh/scp 명령 구성
SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15)
if [ -n "$SSH_LOGIN_PASSWORD" ]; then
  command -v sshpass >/dev/null 2>&1 || { echo "sshpass 미설치 → 'brew install sshpass' 하거나 SSH 키를 쓰세요(SSH_LOGIN_PASSWORD 비우기)"; exit 1; }
  export SSHPASS="$SSH_LOGIN_PASSWORD"
  SSH=(sshpass -e ssh "${SSH_OPTS[@]}")
  SCP=(sshpass -e scp "${SCP_OPTS[@]}")
else
  SSH=(ssh "${SSH_OPTS[@]}")
  SCP=(scp "${SCP_OPTS[@]}")
fi
TARGET="$USER@$HOST"

echo "[*] ($TARGET:$SSH_PORT) 코드 업데이트(git pull)..."
"${SSH[@]}" "$TARGET" "cd '$REMOTE_DIR' && (git pull -q || true)"

echo "[*] ($TARGET) 실행: rehearse.sh $REHEARSE_ARGS"
if [ -n "$SUDO_PASSWORD" ]; then
  # sudo 비번을 stdin 으로 전달 (-S: stdin 에서 읽음, -p '': 프롬프트 숨김)
  "${SSH[@]}" "$TARGET" "cd '$REMOTE_DIR' && sudo -S -p '' ./rehearse.sh $REHEARSE_ARGS" <<< "$SUDO_PASSWORD"
else
  "${SSH[@]}" "$TARGET" "cd '$REMOTE_DIR' && sudo ./rehearse.sh $REHEARSE_ARGS"
fi

echo "[*] 최신 결과 파일 확인..."
LATEST="$("${SSH[@]}" "$TARGET" "ls -t '$REMOTE_DIR'/results/*.txt 2>/dev/null | head -1" || true)"
if [ -z "$LATEST" ]; then
  echo "[x] 결과 txt 를 찾지 못했습니다 ($REMOTE_DIR/results)."
  exit 1
fi

echo "[*] 가져오기: $LATEST"
"${SCP[@]}" "$TARGET:$LATEST" "$LOCAL_DIR/"
echo "[+] 완료 → $LOCAL_DIR/$(basename "$LATEST")"
