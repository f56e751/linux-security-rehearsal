#!/usr/bin/env bash
#
# check-configs.sh — remote-run 설정 파일 사전 점검 (실제 접속 전에 오류를 미리 발견)
#   servers/*.conf 가 멀쩡한지 확인한다. 비밀번호 '값'은 절대 출력하지 않는다.
#
#   ./check-configs.sh servers/*.conf
#   ./check-configs.sh                 # 인자 없으면 servers/*.conf
#
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FILES=("$@")
if [ ${#FILES[@]} -eq 0 ]; then
  shopt -s nullglob 2>/dev/null || true
  FILES=("$HERE"/servers/*.conf)
fi
if [ ${#FILES[@]} -eq 0 ]; then echo "점검할 .conf 가 없습니다."; exit 1; fi

problems=0
for f in "${FILES[@]}"; do
  b="$(basename "$f" .conf)"
  if [ ! -f "$f" ]; then printf '  %-10s ⚠️ 파일 없음\n' "$b"; problems=$((problems+1)); continue; fi

  host="$(grep -m1 '^HOST=' "$f" | cut -d= -f2-)"
  val="$(grep -m1 '^SUDO_PASSWORD=' "$f" 2>/dev/null | sed 's/^SUDO_PASSWORD=//')"
  slp="$(grep -m1 '^SSH_LOGIN_PASSWORD=' "$f" | cut -d= -f2-)"

  warns=""
  [ -z "$host" ] && warns="$warns [HOST없음]"

  if [ -z "$val" ] && [ -z "$slp" ]; then
    warns="$warns [비번없음]"           # SUDO/SSH 둘 다 비어있음 (NOPASSWD 아니면 실패)
  elif [ -n "$val" ]; then
    if printf '%s' "$val" | grep -q "^'.*'$"; then
      :                                  # 작은따옴표로 감쌈 → 안전
    elif printf '%s' "$val" | grep -qE '[^A-Za-z0-9]'; then
      warns="$warns [SUDO_PASSWORD-따옴표필요]"   # 특수문자인데 따옴표 없음
    fi
  fi

  if [ -z "$warns" ]; then st="✔ OK"; else st="⚠️$warns"; problems=$((problems+1)); fi
  printf '  %-10s HOST=%-16s %s\n' "$b" "${host:-<없음>}" "$st"
done

echo
if [ "$problems" -eq 0 ]; then
  echo "✅ 문제 없음 — ./remote-run.sh servers/*.conf 로 실행하세요."
else
  echo "⚠️ ${problems}건 확인 필요. 참고:"
  echo "   · [비번없음]           → SUDO_PASSWORD 를 채우세요"
  echo "   · [SUDO_PASSWORD-따옴표필요] → 특수문자 비번은 'single quote' 로 감싸기"
  echo "   · [HOST없음]           → 실제 IP/호스트명 입력"
fi
exit 0
