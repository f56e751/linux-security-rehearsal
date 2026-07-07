#!/usr/bin/env bash
#
# rehearse.sh — 리눅스 보안점검 전체 절차 "리허설" 도구 (테스트 서버 전용)
#
#   백업 → 점검 → 조치(하드닝) → 재점검 → 복원 → 복원검증
#
# 용도: 서울대 원격 서비스 포트 신청 절차의 점검/조치/복원 흐름을 '테스트 장비'에서
#       안전하게 연습·학습하기 위한 것입니다. 생성되는 결과 파일은 연습/자체점검용이며
#       보안팀 제출용이 아닙니다. 운영 서버에 실제 조치를 하려면 마지막 '복원' 단계 없이
#       apply 만 사용하세요( all 이 아니라 backup + apply ).
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
. "$HERE/lib/common.sh"
. "$HERE/lib/backup.sh"
. "$HERE/lib/remediate.sh"
. "$HERE/lib/check_local.sh"

# ----- 설정 -----
DRY_RUN=0
ASSUME_YES=0
MARK=1                                              # 1=결과에 '리허설/비공식' 표시, 0=표시 없음
FETCH=0                                              # 1=점검 전 공식 스크립트 자동 다운로드 시도
LAST_RESULT=""                                       # run_check 가 채우는 최근 결과 파일 경로
BACKUP_ROOT="$HERE/backups"
RESULT_DIR="$HERE/results"
OFFICIAL_SCRIPT="$HERE/Linux_Password_Check.sh"   # 있으면 이 공식 스크립트로 점검
OFFICIAL_URL="http://snucert.snu.ac.kr/Password_Check/Linux_Password_Check.sh"  # 학내망 전용

usage() {
  cat <<'EOF'
사용법: sudo ./rehearse.sh <명령> [옵션]

명령
  all         전체 리허설: 백업 → 점검 → 조치 → 재점검 → 복원 → 복원검증
  backup      현재 설정 백업만 수행
  check       점검만 수행(공식 스크립트 있으면 우선, 없으면 자체점검)
  fetch       [--force]  공식 점검 스크립트를 학내망에서 다운로드
  apply       보안 조치(하드닝)만 수행  ※ 복원하지 않음
  restore     [백업경로]  지정 백업으로 복원(생략 시 가장 최근 백업)
  verify      [백업경로]  현재 설정이 백업과 일치하는지(=원복 완료) 검증
  list        백업 목록 표시

옵션
  --dry-run   실제 변경 없이 수행할 작업만 출력
  --no-mark   자체점검 결과에서 '리허설/비공식' 표시 제거 (내 로컬 검증 도구 테스트용)
  --fetch     점검 전 공식 스크립트를 학내망에서 자동 다운로드(실패 시 자체점검)
  --yes, -y   확인 프롬프트 없이 진행
  -h, --help  도움말

예시
  sudo ./rehearse.sh all --dry-run     # 무엇이 바뀌는지 먼저 확인
  sudo ./rehearse.sh all --fetch -y    # 공식 스크립트 자동 다운로드 후 리허설
  sudo ./rehearse.sh fetch             # 공식 스크립트만 내려받기
  sudo ./rehearse.sh backup            # 백업만
  sudo ./rehearse.sh restore           # 최근 백업으로 되돌리기
EOF
}

confirm() {
  [ "$ASSUME_YES" = "1" ] && return 0
  printf '%s이 작업은 시스템 설정 파일을 수정합니다. 계속할까요? [y/N] %s' "$C_YEL" "$C_RST"
  local ans; read -r ans || ans=""
  case "$ans" in y|Y|yes|YES) return 0 ;; *) die "사용자가 취소했습니다." ;; esac
}

latest_backup() {
  ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null | sort | tail -1
}

banner() {
  warn "────────────────────────────────────────────────────────────"
  warn " 반드시 '테스트 서버'에서만 실행하세요."
  warn " 설정 오류로 로그인/SSH 접속이 막힐 수 있습니다(문서 경고 참고)."
  warn " 생성 결과 파일은 연습용이며 보안팀 제출용이 아닙니다."
  warn "────────────────────────────────────────────────────────────"
}

cmd_all() {
  require_root
  banner
  detect_distro
  confirm
  local stamp bdir
  stamp="$(date +%Y-%m-%d_%H-%M-%S)"
  bdir="$BACKUP_ROOT/$stamp"
  mkdir -p "$RESULT_DIR"

  if [ "$FETCH" = "1" ]; then
    log "STEP 0     공식 점검 스크립트 다운로드"
    fetch_official || true          # 실패해도(학내망 밖 등) 자체 점검으로 계속
  fi

  log "STEP 1/6  원본 설정 백업"
  backup_configs "$bdir"

  log "STEP 2/6  조치 전 점검"
  run_check "$RESULT_DIR"

  log "STEP 3/6  보안 조치(하드닝) 적용"
  apply_hardening

  log "STEP 4/6  조치 후 재점검(통과 결과 파일 생성)"
  run_check "$RESULT_DIR"
  local pass_file="${LAST_RESULT:-}"      # 조치 후(=통과) 결과 파일 경로

  log "STEP 5/6  원본 설정으로 복원"
  restore_configs "$bdir"

  log "STEP 6/6  복원 검증 (백업과 바이트 단위 대조)"
  verify_configs "$bdir" || warn "원복 검증에서 불일치 발견 — 위 로그를 확인하세요"

  ok "리허설 완료."
  log "  · 백업: $bdir"
  log "  · 결과 폴더: $RESULT_DIR"
  if [ -n "$pass_file" ]; then
    ok "  · 통과 결과 파일(자동화 입력용) →  $pass_file"
  fi
  warn "결과 파일은 연습/자체점검용입니다. 실제 제출은 운영 서버에서 조치를 '유지'한 상태로 진행하세요."
}

cmd_restore() {
  require_root
  local bdir="${1:-}"
  if [ -z "$bdir" ]; then
    bdir="$(latest_backup)"
    [ -n "$bdir" ] || die "복원할 백업이 없습니다. 먼저 backup 을 수행하세요."
    log "가장 최근 백업 사용: $bdir"
  fi
  confirm
  restore_configs "$bdir"
}

cmd_verify() {
  local bdir="${1:-}"
  if [ -z "$bdir" ]; then
    bdir="$(latest_backup)"
    [ -n "$bdir" ] || die "비교할 백업이 없습니다. 먼저 backup 을 수행하세요."
    log "가장 최근 백업과 비교: $bdir"
  fi
  verify_configs "$bdir"    # 불일치 시 0이 아닌 종료코드 반환
}

# ----- 인자 파싱 -----
CMD="${1:-}"; shift || true
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --no-mark) MARK=0 ;;
    --fetch)   FETCH=1 ;;
    -y|--yes)  ASSUME_YES=1 ;;
    -h|--help) usage; exit 0 ;;
    *)         POSITIONAL+=("$1") ;;
  esac
  shift
done

case "$CMD" in
  all)     cmd_all ;;
  backup)  require_root; banner; backup_configs "$BACKUP_ROOT/$(date +%Y-%m-%d_%H-%M-%S)" ;;
  check)   if [ "$FETCH" = "1" ]; then fetch_official || true; fi; run_check "$RESULT_DIR" ;;
  fetch)   fetch_official "${POSITIONAL[0]:-}" ;;
  apply)   require_root; banner; confirm; apply_hardening ;;
  restore) cmd_restore "${POSITIONAL[0]:-}" ;;
  verify)  cmd_verify "${POSITIONAL[0]:-}" ;;
  list)    ls -1d "$BACKUP_ROOT"/*/ 2>/dev/null || echo "(백업 없음)" ;;
  -h|--help|help) usage ;;
  "")      usage; exit 1 ;;
  *)       err "알 수 없는 명령: $CMD"; usage; exit 1 ;;
esac
