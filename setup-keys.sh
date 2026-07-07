#!/usr/bin/env bash
#
# setup-keys.sh — 노트북 SSH 공개키를 여러 서버에 한 번에 등록 (이후 무비번 로그인)
#   실행 후엔 remote-run.sh 가 비번/ sshpass 없이 동작한다.
#
#   ./setup-keys.sh servers/*.conf
#   ./setup-keys.sh                  # 인자 없으면 servers/*.conf
#
# 각 서버:
#   - sshpass 가 있고 conf 에 비번이 있으면 → 자동 등록(비번 입력 불필요)
#   - 없으면 → ssh-copy-id 가 서버당 비번을 1회 물어봄(등록 후엔 다시 안 물어봄)
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1) 노트북에 SSH 키가 없으면 생성
PUBKEY="$(ls "$HOME"/.ssh/id_ed25519.pub "$HOME"/.ssh/id_rsa.pub 2>/dev/null | head -1)"
if [ -z "$PUBKEY" ]; then
  echo "[*] SSH 키가 없어 새로 생성합니다 (~/.ssh/id_ed25519)..."
  ssh-keygen -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
  PUBKEY="$HOME/.ssh/id_ed25519.pub"
fi
echo "[*] 사용할 공개키: $PUBKEY"

FILES=("$@")
if [ ${#FILES[@]} -eq 0 ]; then
  shopt -s nullglob 2>/dev/null || true
  FILES=("$HERE"/servers/*.conf)
fi
if [ ${#FILES[@]} -eq 0 ]; then echo "등록할 대상 .conf 가 없습니다."; exit 1; fi

ok_n=0; fail_n=0; FAILS=""
for f in "${FILES[@]}"; do
  name="$(basename "$f" .conf)"
  [ -f "$f" ] || { echo "[$name] 파일 없음"; fail_n=$((fail_n+1)); FAILS="$FAILS $name"; continue; }
  echo "════════ [$name] 키 등록"
  if (
        set -e
        # shellcheck disable=SC1090
        source "$f"
        : "${HOST:?HOST 없음}"
        port="${SSH_PORT:-22}"
        loginpw="${SSH_LOGIN_PASSWORD:-${SUDO_PASSWORD:-}}"
        opts=(-p "$port" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -i "$PUBKEY")
        if command -v sshpass >/dev/null 2>&1 && [ -n "$loginpw" ]; then
          echo "  → sshpass 로 자동 등록 시도 ($USER@$HOST)"
          SSHPASS="$loginpw" sshpass -e ssh-copy-id "${opts[@]}" "$USER@$HOST"
        else
          echo "  → 비번을 1회 입력하세요 ($USER@$HOST)"
          ssh-copy-id "${opts[@]}" "$USER@$HOST"
        fi
     ); then
    echo "  ✔ 등록 완료"
    ok_n=$((ok_n+1))
  else
    echo "  ✘ 등록 실패"
    fail_n=$((fail_n+1)); FAILS="$FAILS $name"
  fi
done

echo
echo "════════════ 요약 ════════════"
echo "  ✔ 등록 성공 $ok_n"
echo "  ✘ 실패 $fail_n:${FAILS:-  (없음)}"
if [ "$fail_n" -eq 0 ]; then
  echo "이제 ./remote-run.sh servers/*.conf 가 비번 없이 동작합니다."
fi