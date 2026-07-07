#!/usr/bin/env bash
# remediate.sh — 문서(서울대 원격 서비스 포트 신청 안내) 기준에 따른 보안 조치
# common.sh 를 먼저 source 한 상태에서 사용합니다.
#
# 점검 기준 요약
#   1) 패스워드 복잡성 : lcredit/ocredit/dcredit = -1 (소문자/특수문자/숫자 각 1자 이상)
#   2) 계정 잠금 임계값 : deny <= 10
#   3) 패스워드 정책   : PASS_MIN_LEN>=8, PASS_MAX_DAYS<=90, PASS_MIN_DAYS>=1

# pam_add_args FILE MODULE "opt1=v1 opt2=v2 ..."
#   지정 모듈 라인(주석 아님)에 옵션을 추가/갱신. 라인이 없으면 건너뜀(수동 확인 권장).
pam_add_args() {
  local file="$1" module="$2" args="$3"
  if [ ! -e "$file" ]; then warn "$file 없음 — 건너뜀"; return 0; fi
  if is_dry; then log "[dry-run] $file: $module 에 '$args' 반영"; return 0; fi
  if ! grep -Eq "^[^#].*${module}" "$file"; then
    warn "$file 에 활성 '$module' 라인이 없어 건너뜀 (배포판별로 수동 확인 필요)"
    return 0
  fi
  local tmp="${file}.rehearse.tmp" a
  cp -a "$file" "$tmp"
  for a in $args; do
    local optkey="${a%%=*}"
    awk -v mod="$module" -v opt="$optkey" -v full="$a" '
      $0 ~ ("^[^#].*" mod) {
        if ($0 ~ (opt "=")) { gsub(opt "=[^ \t]*", full) }
        else                { $0 = $0 " " full }
      }
      { print }
    ' "$tmp" > "${tmp}.2" && mv "${tmp}.2" "$tmp"
  done
  cat "$tmp" > "$file"; rm -f "$tmp"
  ok "PAM 설정: $file  ($module += $args)"
}

# RHEL 계열 계정 잠금: RHEL8+ 는 faillock.conf 가 authselect 로 auth 스택에 연결됨.
apply_lockout_rhel() {
  if [ -e /etc/security/faillock.conf ]; then
    set_kv /etc/security/faillock.conf deny        10  " = "
    set_kv /etc/security/faillock.conf unlock_time 120 " = "
  else
    warn "faillock.conf 없음(RHEL7?) → /etc/pam.d/system-auth 의 pam_tally2 수동 확인 권장"
  fi
}

# Debian/Ubuntu 계정 잠금: 공식 점검이 /etc/pam.d/common-auth 를 보므로 여기에 라인 추가.
#   ※ auth 스택 편집이라 가장 조심스러운 부분 → 모듈이 실제 존재할 때만 추가한다.
#   common-auth 는 백업 대상이라 all 이 자동 원복 / restore 로 복구 가능.
apply_lockout_debian() {
  local ca=/etc/pam.d/common-auth
  if is_dry; then log "[dry-run] $ca 에 계정 잠금(deny=10) 라인 추가"; return 0; fi
  [ -e "$ca" ] || { warn "$ca 없음 — 잠금 설정 건너뜀"; return 0; }
  if grep -Eq '^[^#].*deny=' "$ca"; then
    log "$ca 에 이미 deny= 설정 존재 — 건너뜀(중복/충돌 방지)"; return 0
  fi
  local line=""
  if _pam_mod_path pam_tally2.so >/dev/null; then
    line=$'auth\trequired\tpam_tally2.so onerr=fail deny=10 unlock_time=120'
  elif _pam_mod_path pam_faillock.so >/dev/null; then
    line=$'auth\trequired\tpam_faillock.so preauth silent deny=10 unlock_time=120'
    [ -e /etc/security/faillock.conf ] && { set_kv /etc/security/faillock.conf deny 10 " = "; set_kv /etc/security/faillock.conf unlock_time 120 " = "; }
  else
    warn "pam_tally2/pam_faillock 모듈을 찾을 수 없음 — 잠금 설정 수동 필요"; return 0
  fi
  # 첫 활성 auth 라인 앞에 삽입 (awk 비의존 → mawk 문제 없음)
  local tmp="${ca}.rehearse.tmp" inserted=0 ln
  : > "$tmp"
  while IFS= read -r ln || [ -n "$ln" ]; do
    if [ "$inserted" = 0 ] && printf '%s\n' "$ln" | grep -Eq '^[[:space:]]*auth[[:space:]]'; then
      printf '%s\n' "$line" >> "$tmp"; inserted=1
    fi
    printf '%s\n' "$ln" >> "$tmp"
  done < "$ca"
  [ "$inserted" = 0 ] && printf '%s\n' "$line" >> "$tmp"
  cat "$tmp" > "$ca"; rm -f "$tmp"
  ok "잠금 설정: $ca 맨 위에 추가 → ${line//$'\t'/ }"
}

apply_hardening() {
  detect_distro

  log "== 1) 패스워드 정책 (/etc/login.defs) =="
  set_kv /etc/login.defs PASS_MIN_LEN  8  " "    # 최소 길이 8자 이상
  set_kv /etc/login.defs PASS_MAX_DAYS 90 " "    # 최대 사용기간 90일 이하
  set_kv /etc/login.defs PASS_MIN_DAYS 1  " "    # 최소 사용기간 1일 이상

  log "== 2) 패스워드 복잡성 =="
  case "$DISTRO_FAMILY" in
    rhel)
      if [ "$RHEL_MAJOR" -ge 7 ] || [ -e /etc/security/pwquality.conf ]; then
        set_kv /etc/security/pwquality.conf lcredit -1 " = "
        set_kv /etc/security/pwquality.conf ocredit -1 " = "
        set_kv /etc/security/pwquality.conf dcredit -1 " = "
      else
        warn "RHEL7 이전 계열 → /etc/pam.d/system-auth 의 pam_cracklib 라인 조치 시도"
        pam_add_args /etc/pam.d/system-auth pam_cracklib.so "lcredit=-1 ocredit=-1 dcredit=-1"
      fi
      ;;
    debian)
      if [ -e /etc/security/pwquality.conf ]; then
        set_kv /etc/security/pwquality.conf lcredit -1 " = "
        set_kv /etc/security/pwquality.conf ocredit -1 " = "
        set_kv /etc/security/pwquality.conf dcredit -1 " = "
      else
        pam_add_args /etc/pam.d/common-password pam_pwquality.so "lcredit=-1 ocredit=-1 dcredit=-1"
      fi
      ;;
    *)
      warn "배포판 미확인 — 복잡성 설정은 수동 확인이 필요합니다."
      ;;
  esac

  log "== 3) 계정 잠금 임계값 (deny<=10) =="
  case "$DISTRO_FAMILY" in
    debian) apply_lockout_debian ;;
    rhel)   apply_lockout_rhel ;;
    *)      warn "배포판 미확인 — 계정 잠금 설정은 수동 확인이 필요합니다." ;;
  esac

  ok "보안 조치 적용 완료"
}
