#!/usr/bin/env bash
# check_local.sh — 점검 실행기
#   - 공식 스크립트(Linux_Password_Check.sh)가 있으면 그것을 우선 실행
#   - 없으면 자체 점검(비공식)을 수행. 결과 파일명에 'rehearsal' 을 넣어
#     제출용 공식 결과와 반드시 구분되도록 합니다.
# common.sh 를 먼저 source 한 상태에서 사용합니다.

# run_check OUTDIR
#   생성된 결과 파일 경로를 전역 LAST_RESULT 에 담아 호출부에서 참조 가능.
run_check() {
  local outdir="${1:-.}"
  mkdir -p "$outdir"
  LAST_RESULT=""
  local script="${OFFICIAL_SCRIPT:-}"
  if [ -n "$script" ] && [ -f "$script" ]; then
    log "공식 점검 스크립트 실행: $script"
    chmod +x "$script" 2>/dev/null || true
    ( cd "$outdir" && bash "$script" ) || warn "공식 스크립트 실행 중 경고(계속 진행)"
    LAST_RESULT="$(ls -t "$outdir"/*.txt 2>/dev/null | head -1)" || true
    ok "공식 점검 결과 파일이 $outdir 에 생성되었습니다."
    return 0
  fi

  if [ "${MARK:-1}" = "1" ]; then
    warn "공식 스크립트 없음 → 자체 점검 실행 (이 결과는 '제출용'이 아닙니다)"
  else
    warn "공식 스크립트 없음 → 자체 점검 실행 (--no-mark: 마커 없는 형식)"
  fi
  local ts host out tag
  ts="$(date +%Y-%m-%d_%H-%M-%S)"
  host="$(hostname)"
  if [ "${MARK:-1}" = "1" ]; then tag="rehearsal"; else tag="result"; fi
  out="$outdir/${host}-linux-${tag}-${ts}.txt"
  local_check > "$out"
  LAST_RESULT="$out"
  ok "자체 점검 결과: $out"
  grep -E '\[(안전|취약)\]' "$out" || true
}

# 자체 점검(비공식). 문서 기준 항목을 확인해 안전/취약을 표시.
local_check() {
  local pass=0 fail=0
  if [ "${MARK:-1}" = "1" ]; then
    printf '# Linux 보안 리허설 자체점검 결과 (비공식, 제출용 아님)\n'
  fi
  printf '# host=%s  time=%s\n\n' "$(hostname)" "$(date '+%Y-%m-%d %H:%M:%S')"

  _emit() {  # LABEL  ok|no  DETAIL
    if [ "$2" = "ok" ]; then printf '[안전] %s — %s\n' "$1" "$3"; pass=$((pass+1))
    else                     printf '[취약] %s — %s\n' "$1" "$3"; fail=$((fail+1)); fi
  }
  _num() {  # 파일에서 KEY 의 마지막 값 추출(공백/'=' 구분 모두 대응). 파일 없으면 빈 값.
    [ -r "$2" ] || return 0
    awk -v k="$1" '
      $0 ~ ("^[[:space:]]*" k "[[:space:]=]") {
        line=$0; sub("^[[:space:]]*" k "[[:space:]=]+","",line); gsub(/[^-0-9].*$/,"",line); v=line
      }
      END { print v }' "$2" 2>/dev/null || true
  }

  local v
  # --- /etc/login.defs ---
  v="$(_num PASS_MIN_LEN /etc/login.defs)"
  if [ -n "$v" ] && [ "$v" -ge 8 ] 2>/dev/null; then _emit "패스워드 최소 길이"     ok "PASS_MIN_LEN=$v (>=8)"; else _emit "패스워드 최소 길이"     no "PASS_MIN_LEN=${v:-미설정}"; fi
  v="$(_num PASS_MAX_DAYS /etc/login.defs)"
  if [ -n "$v" ] && [ "$v" -le 90 ] 2>/dev/null; then _emit "패스워드 최대 사용기간" ok "PASS_MAX_DAYS=$v (<=90)"; else _emit "패스워드 최대 사용기간" no "PASS_MAX_DAYS=${v:-미설정}"; fi
  v="$(_num PASS_MIN_DAYS /etc/login.defs)"
  if [ -n "$v" ] && [ "$v" -ge 1 ] 2>/dev/null; then _emit "패스워드 최소 사용기간" ok "PASS_MIN_DAYS=$v (>=1)"; else _emit "패스워드 최소 사용기간" no "PASS_MIN_DAYS=${v:-미설정}"; fi

  # --- 복잡성 (pwquality.conf 우선) ---
  if [ -e /etc/security/pwquality.conf ]; then
    local key
    for key in lcredit ocredit dcredit; do
      v="$(_num "$key" /etc/security/pwquality.conf)"
      if [ -n "$v" ] && [ "$v" -le -1 ] 2>/dev/null; then _emit "복잡성($key)" ok "$key=$v (<=-1)"; else _emit "복잡성($key)" no "$key=${v:-미설정}"; fi
    done
  else
    _emit "패스워드 복잡성" no "pwquality.conf 없음 — PAM(cracklib/pwquality) 수동 확인 필요"
  fi

  # --- 계정 잠금 임계값 ---
  if [ -e /etc/security/faillock.conf ]; then
    v="$(_num deny /etc/security/faillock.conf)"
    if [ -n "$v" ] && [ "$v" -le 10 ] 2>/dev/null; then _emit "계정 잠금 임계값" ok "deny=$v (<=10)"; else _emit "계정 잠금 임계값" no "deny=${v:-미설정}"; fi
  else
    _emit "계정 잠금 임계값" no "faillock.conf 없음 — PAM(faillock/tally2) 수동 확인 필요"
  fi

  printf '\n=== 요약: 안전 %d / 취약 %d ===\n' "$pass" "$fail"
}
