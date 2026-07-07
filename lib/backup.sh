#!/usr/bin/env bash
# backup.sh — 설정 파일 백업/복원
# common.sh 를 먼저 source 한 상태에서 사용합니다.

# backup_configs BACKUP_DIR
#   CONFIG_FILES 중 존재하는 파일을 디렉터리 구조 그대로 복사하고,
#   manifest.txt 에 각 파일의 존재 여부(EXIST/ABSENT)를 기록합니다.
backup_configs() {
  local dir="$1"
  mkdir -p "$dir"
  local manifest="$dir/manifest.txt"
  : > "$manifest"
  local f
  for f in "${CONFIG_FILES[@]}"; do
    if [ -e "$f" ]; then
      mkdir -p "$dir$(dirname "$f")"
      cp -a "$f" "$dir$f"          # 권한/타임스탬프/소유자 보존
      printf 'EXIST %s\n' "$f" >> "$manifest"
      log "백업: $f"
    else
      printf 'ABSENT %s\n' "$f" >> "$manifest"
    fi
  done
  ok "백업 완료 → $dir"
}

# restore_configs BACKUP_DIR
#   manifest 기준으로 원상복구.
#   - EXIST  : 백업본을 원위치로 되돌림
#   - ABSENT : 백업 시점엔 없던 파일 → 조치 중 생성됐다면 삭제
restore_configs() {
  local dir="$1"
  local manifest="$dir/manifest.txt"
  [ -r "$manifest" ] || die "매니페스트를 찾을 수 없습니다: $manifest"
  local state f
  while read -r state f; do
    [ -n "$f" ] || continue
    case "$state" in
      EXIST)
        if [ -e "$dir$f" ]; then
          if is_dry; then log "[dry-run] 복원: $f"; else cp -a "$dir$f" "$f"; ok "복원: $f"; fi
        else
          warn "백업본 없음, 건너뜀: $f"
        fi
        ;;
      ABSENT)
        if [ -e "$f" ]; then
          if is_dry; then log "[dry-run] 삭제(원래 없던 파일): $f"; else rm -f "$f"; ok "삭제(원래 없던 파일): $f"; fi
        fi
        ;;
    esac
  done < "$manifest"
  ok "복원 완료 (백업: $dir)"
}

# verify_configs BACKUP_DIR
#   현재 시스템 설정이 지정 백업과 동일한지(=원복 완료 상태인지) 확인.
#   모두 일치하면 0, 하나라도 다르면 1 을 반환하여 스크립트에서 판정 가능.
verify_configs() {
  local dir="$1"
  local manifest="$dir/manifest.txt"
  [ -r "$manifest" ] || die "매니페스트를 찾을 수 없습니다: $manifest"
  local state f diffcnt=0 total=0
  while read -r state f; do
    [ -n "$f" ] || continue
    total=$((total+1))
    case "$state" in
      EXIST)
        if [ ! -e "$f" ]; then
          err "누락  $f (백업엔 있으나 현재 없음)"; diffcnt=$((diffcnt+1))
        elif diff -q "$dir$f" "$f" >/dev/null 2>&1; then
          ok "동일  $f"
        else
          err "차이  $f"; diffcnt=$((diffcnt+1))
        fi
        ;;
      ABSENT)
        if [ -e "$f" ]; then
          err "잔존  $f (원래 없던 파일이 남아있음)"; diffcnt=$((diffcnt+1))
        else
          ok "정상  $f (원래대로 없음)"
        fi
        ;;
    esac
  done < "$manifest"
  if [ "$diffcnt" -eq 0 ]; then
    ok "검증 통과: 관리 대상 ${total}개가 백업과 완전히 일치합니다 — 원복 완료 상태"
    return 0
  fi
  err "검증 실패: ${total}개 중 ${diffcnt}개 불일치 — 원복이 완전하지 않음"
  return 1
}
