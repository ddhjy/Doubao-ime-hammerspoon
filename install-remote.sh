#!/usr/bin/env bash

set -euo pipefail

REPO_OWNER="${REPO_OWNER:-ddhjy}"
REPO_NAME="${REPO_NAME:-Doubao-ime-hammerspoon}"
REPO_BRANCH="${REPO_BRANCH:-main}"
ARCHIVE_URL="${ARCHIVE_URL:-https://github.com/${REPO_OWNER}/${REPO_NAME}/archive/refs/heads/${REPO_BRANCH}.zip}"
TMP_DIR=""

info() {
  printf '[信息] %s\n' "$1"
}

error() {
  printf '[错误] %s\n' "$1" >&2
}

cleanup() {
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf "$TMP_DIR"
  fi
}

find_project_dir() {
  local search_root="$1"
  local found_dir

  found_dir="$(find "$search_root" -mindepth 1 -maxdepth 1 -type d | head -n 1)"

  if [[ -z "$found_dir" ]]; then
    error '未找到解压后的项目目录。'
    exit 1
  fi

  printf '%s\n' "$found_dir"
}

main() {
  local archive_path
  local unpack_dir
  local project_dir

  if [[ "$(uname -s)" != "Darwin" ]]; then
    error '该安装入口仅支持在 macOS 上运行。'
    exit 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    error '未检测到 curl，请先安装 curl 后重试。'
    exit 1
  fi

  if ! command -v ditto >/dev/null 2>&1; then
    error '未检测到 ditto，无法解压安装包。'
    exit 1
  fi

  TMP_DIR="$(mktemp -d)"
  trap cleanup EXIT

  archive_path="$TMP_DIR/${REPO_NAME}-${REPO_BRANCH}.zip"
  unpack_dir="$TMP_DIR/unpacked"

  mkdir -p "$unpack_dir"

  info "开始下载项目归档：$ARCHIVE_URL"
  curl -fsSL "$ARCHIVE_URL" -o "$archive_path"

  info '下载完成，开始解压安装包...'
  ditto -x -k "$archive_path" "$unpack_dir"

  project_dir="$(find_project_dir "$unpack_dir")"

  if [[ ! -f "$project_dir/install.sh" ]]; then
    error "解压后的目录中未找到 install.sh：$project_dir"
    exit 1
  fi

  info '开始执行安装脚本...'
  bash "$project_dir/install.sh" "$@"
}

main "$@"
