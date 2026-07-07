#!/usr/bin/env bash
# common.sh — 공통 헬퍼(로깅 / root 확인 / 배포판 감지 / 설정값 편집)
# rehearse.sh 에서 source 되어 사용됩니다. 단독 실행용 아님.

# ----- 색상/로깅 -----
if [ -t 1 ]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_BLU=$'\033[34m'; C_RST=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_BLU=; C_RST=
fi

log()  { printf '%s[*]%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[!]%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
err()  { printf '%s[x]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; }
die()  { err "$*"; exit 1; }

is_dry() { [ "${DRY_RUN:-0}" = "1" ]; }

# ----- 관리 대상 설정 파일 -----
# 백업 시 존재하는 것만 복사하고, 복원 시 원상복구 대상이 됩니다.
CONFIG_FILES=(
  /etc/login.defs
  /etc/security/pwquality.conf
  /etc/security/faillock.conf
  /etc/pam.d/system-auth
  /etc/pam.d/common-password
  /etc/pam.d/common-auth
)

# ----- root 확인 -----
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    die "root 권한이 필요합니다. 'sudo ./rehearse.sh ...' 로 실행하세요."
  fi
}

# ----- 배포판 감지 -----
# 결과: DISTRO_FAMILY(rhel|debian|unknown), RHEL_MAJOR(정수), OS_PRETTY
detect_distro() {
  DISTRO_FAMILY=unknown
  RHEL_MAJOR=0
  OS_PRETTY="unknown"
  if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    OS_PRETTY="${PRETTY_NAME:-${ID:-unknown}}"
    case " ${ID:-} ${ID_LIKE:-} " in
      *rhel*|*fedora*|*centos*|*rocky*|*almalinux*) DISTRO_FAMILY=rhel ;;
      *debian*|*ubuntu*)                            DISTRO_FAMILY=debian ;;
    esac
    local major="${VERSION_ID%%.*}"
    if [ -n "$major" ] && [ -z "${major//[0-9]/}" ]; then
      RHEL_MAJOR="$major"
    fi
  fi
  log "감지된 배포판: ${OS_PRETTY} (family=${DISTRO_FAMILY}, major=${RHEL_MAJOR})"
}

# ----- 설정값 편집(idempotent) -----
# set_kv FILE KEY VALUE SEP
#   SEP 예:  " "   → login.defs 형식  (PASS_MIN_LEN 8)
#            " = " → conf 형식        (lcredit = -1)
# 주석 처리됐거나 활성화된 KEY 라인이 있으면 그 한 줄만 교체, 없으면 파일 끝에 추가.
# 원본 파일의 권한/소유자는 유지(내용만 덮어씀).
set_kv() {
  local file="$1" key="$2" val="$3" sep="$4"
  local newline="${key}${sep}${val}"
  if is_dry; then
    log "[dry-run] ${file}: '${newline}'"
    return 0
  fi
  if [ ! -e "$file" ]; then
    warn "${file} 없음 — 새로 생성합니다."
    : > "$file"
  fi
  local tmp="${file}.rehearse.tmp"
  # 기존(또는 주석 처리된) KEY 라인을 grep 으로 제거한 뒤 새 값을 추가한다.
  # awk 에 의존하지 않으므로 mawk/gawk/BSD awk 어디서든 동일하게 동작한다.
  # (grep 매칭은 GNU/BSD 모두 신뢰 가능 — 탭/공백/'=' 구분자 모두 처리)
  local pat="^[[:space:]]*#?[[:space:]]*${key}[[:space:]=]"
  if grep -Eq "$pat" "$file"; then
    grep -Ev "$pat" "$file" > "$tmp" || true    # KEY 라인만 빼고 나머지 보존
    printf '%s\n' "$newline" >> "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
  else
    printf '%s\n' "$newline" >> "$file"
  fi
  ok "설정: ${file}  →  ${newline}"
}

# ----- 현재 값 읽기 -----
# get_val FILE KEY  → 활성(주석 아님) KEY 의 마지막 값을 출력. 없거나 주석뿐이면 빈 값.
# 공백/탭/'=' 구분자 모두 처리. awk 비의존(grep+sed).
get_val() {
  local file="$1" key="$2"
  [ -r "$file" ] || return 0
  grep -E "^[[:space:]]*${key}[[:space:]=]" "$file" 2>/dev/null | tail -1 \
    | sed -E "s/^[[:space:]]*${key}[[:space:]=]+//; s/[[:space:]].*$//" || true
}
