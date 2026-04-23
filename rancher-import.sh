#!/bin/bash
#
# rancher-import.sh — 離線端 load image tar.gz + retag + push 到目標 registry
#
# 流程：podman/docker login → podman/docker load -i <image-tar.gz>
#       → 解析 loaded image → 若 src ≠ target 則 retag → podman/docker push
#
# Script 不解壓 rancher-airgap-<ver>.tar.gz，也不動使用者任何檔案；
# 只讀位置參數傳進的 image tar.gz、並對目標 registry 做 push。
# 使用者需自行 `tar -xzf rancher-airgap-<ver>.tar.gz -C <dir>` 後把 *-image.tar.gz
# 的路徑傳給本 script。

# 設定 Debug 模式
## 預設將執行中的指令及其參數重新導向到 /tmp/import_message.log 檔案中
[[ -z "${Command_log_file}" ]] && Command_log_file="/tmp/import_message.log"
[[ -f "${Command_log_file}" ]] && rm -f "${Command_log_file}"
exec {BASH_XTRACEFD}>>"${Command_log_file}"
export PS4='+ [$(date +%H:%M:%S)] ${BASH_SOURCE##*/}:${LINENO}: '
set -x

## 預設確保命令執行後的輸出重定向到 /tmp/import_output_message.log 檔案中
[[ -z "${Command_Output_log_file}" ]] && Command_Output_log_file="/tmp/import_output_message.log"
[[ -f "${Command_Output_log_file}" ]] && rm -f "${Command_Output_log_file}"

usage() {
  cat <<EOF
Usage:
  ENV_VAR=... $(basename "${BASH_SOURCE[0]}") <image-tar.gz> [<image-tar.gz> ...]

Required:
   - Positional args：一或多個 image tar.gz 檔路徑
       例：~/work/imported/rancher/v2.13.4/rancher-v2.13.4-image.tar.gz
           ~/work/imported/rancher/v2.13.4/cert-manager-image-v1.20.2.tar.gz

   - Target_Registry_Name
     目標私有 Image Registry 的 hostname（必填）
     例：harbor.customer.internal

Optional environment variables:
   - Container_Runtime          (default: podman；可 podman 或 docker)
   - Target_Registry_Namespace  (default: rancher；第二層 namespace／project)
   - Registry_Username          (optional；搭配 Registry_Password 走 --password-stdin)
   - Registry_Password          (optional)
   - Skip_Login                 (default: 0；設 1 跳過 login)
   - Command_log_file           (default: /tmp/import_message.log)
   - Command_Output_log_file    (default: /tmp/import_output_message.log)

備註：
  - Script 本身不解壓 rancher-airgap-<ver>.tar.gz
    請先 'tar -xzf rancher-airgap-<ver>.tar.gz -C <您選的目錄>' 再把 *-image.tar.gz
    的路徑傳給本 script
  - 解壓後的 helm chart (.tgz)、cert-manager.yaml、helper scripts 由您自行保留
    用於後續 'helm install rancher' / 'kubectl apply -f cert-manager.yaml'

Example:
  # Shell glob（最常見）
  \$ Target_Registry_Name=harbor.customer.internal \\
      $(basename "${BASH_SOURCE[0]}") ~/work/imported/rancher/v2.13.4/*-image.tar.gz

  # 顯式指定多個檔案
  \$ Target_Registry_Name=harbor.customer.internal \\
      Target_Registry_Namespace=rancher-prime \\
      $(basename "${BASH_SOURCE[0]}") \\
        ~/work/imported/rancher/v2.13.4/rancher-v2.13.4-image.tar.gz \\
        ~/work/imported/rancher/v2.13.4/cert-manager-image-v1.20.2.tar.gz

  # 非互動登入（CI pipeline）
  \$ Target_Registry_Name=harbor.customer.internal \\
      Registry_Username=admin Registry_Password='...' \\
      $(basename "${BASH_SOURCE[0]}") /path/to/*-image.tar.gz

  # 使用 docker
  \$ Container_Runtime=docker Target_Registry_Name=harbor.x.com \\
      $(basename "${BASH_SOURCE[0]}") /path/to/*-image.tar.gz

  # 已經登入過，跳過 login
  \$ Skip_Login=1 Target_Registry_Name=harbor.x.com \\
      $(basename "${BASH_SOURCE[0]}") /path/to/*-image.tar.gz
EOF
  exit 1
}

[[ "$#" -eq "0" ]] && usage

# 印進度列到終端（同一行覆寫），非 TTY 時靜默
print_progress() {
  printf "\r\033[K[%s %d/%d] %s" "$1" "$2" "$3" "$4" >/dev/tty 2>/dev/null || true
}

# 在合併 log 檔寫一個醒目的 section 分隔符
log_section() {
  local label="$1"
  local ts; ts=$(date '+%Y-%m-%d %H:%M:%S')
  {
    echo ""
    echo "############################################################"
    echo "# [$ts] $label"
    echo "############################################################"
    echo ""
  } >> "${Command_Output_log_file}"
}

# 執行外部命令並把 CMD／輸出／EXIT 一起結構化寫入合併 log 檔（不上螢幕）。
# 使用：logged_run "<label>" <cmd> <args...>
# 回傳值為原命令的 exit code。
logged_run() {
  local label="$1"; shift
  local log="${Command_Output_log_file}"
  local ts_start; ts_start=$(date '+%Y-%m-%d %H:%M:%S')
  {
    echo ""
    echo "=== [$ts_start] $label ==="
    echo "CMD: $*"
  } >> "$log"
  "$@" >> "$log" 2>&1
  local rc=$?
  local ts_end; ts_end=$(date '+%Y-%m-%d %H:%M:%S')
  echo "=== [$ts_end] EXIT: $rc ===" >> "$log"
  return $rc
}

setup_env() {
  # Container_Runtime 預設 podman
  if [[ -z "${Container_Runtime}" ]]; then
    Container_Runtime="podman"
  fi

  # 驗證 runtime binary 存在
  if ! which "${Container_Runtime}" &> /dev/null; then
    echo "${Container_Runtime} command not found!" >&2
    exit 1
  fi

  # Target_Registry_Name 必填
  if [[ -z "${Target_Registry_Name}" ]]; then
    echo "Target_Registry_Name is required" >&2
    usage
  fi

  # Target_Registry_Namespace 預設 rancher（對齊 prepare 端 Private_Registry_Namespace）
  if [[ -z "${Target_Registry_Namespace}" ]]; then
    Target_Registry_Namespace="rancher"
  fi

  # Skip_Login 預設 0
  if [[ -z "${Skip_Login}" ]]; then
    Skip_Login="0"
  fi

  # 先驗證所有位置參數指向的檔案存在且可讀，避免做了一半才報錯
  for tarball in "$@"; do
    if [[ ! -f "$tarball" ]]; then
      echo "Image tarball not found: $tarball" >&2
      exit 1
    fi
    if [[ ! -r "$tarball" ]]; then
      echo "Image tarball not readable: $tarball" >&2
      exit 1
    fi
  done
}

# 登入目標 registry
do_login() {
  if [[ "${Skip_Login}" == "1" ]]; then
    echo "Skip_Login=1, skip ${Container_Runtime} login"
    return 0
  fi

  if [[ -n "${Registry_Username}" && -n "${Registry_Password}" ]]; then
    # 非互動：password-stdin；暫關 xtrace 避免密碼寫進 Command_log_file
    echo "Login to ${Target_Registry_Name} as ${Registry_Username} (non-interactive)..."
    local login_rc
    local ts_start; ts_start=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo ""
      echo "=== [$ts_start] import: login ${Target_Registry_Name} (--password-stdin) ==="
      echo "CMD: ${Container_Runtime} login -u ${Registry_Username} --password-stdin ${Target_Registry_Name}"
    } >> "${Command_Output_log_file}"

    set +x
    echo "${Registry_Password}" | "${Container_Runtime}" login -u "${Registry_Username}" --password-stdin "${Target_Registry_Name}" >> "${Command_Output_log_file}" 2>&1
    login_rc=$?
    set -x

    local ts_end; ts_end=$(date '+%Y-%m-%d %H:%M:%S')
    echo "=== [$ts_end] EXIT: $login_rc ===" >> "${Command_Output_log_file}"

    if [[ $login_rc -ne 0 ]]; then
      echo "Login to ${Target_Registry_Name} failed" >&2
      exit 1
    fi
  else
    # 互動：直接跑，讓 runtime 自己 prompt（stdin/stderr 不導開）
    echo "Login to ${Target_Registry_Name} (interactive prompt)..."
    if ! "${Container_Runtime}" login "${Target_Registry_Name}"; then
      echo "Login to ${Target_Registry_Name} failed" >&2
      exit 1
    fi
  fi
}

# 依序 load 所有 image tarball，並把 `Loaded image: <ref>` 解析到 loaded_images 陣列
load_all_images() {
  loaded_images=()
  local tarball_count=$#
  local tarball_idx=0

  for tarball in "$@"; do
    tarball_idx=$((tarball_idx + 1))
    echo "[${tarball_idx}/${tarball_count}] Loading ${tarball} ..."

    # load 的 stdout 要 parse 取 image ref，所以不走 logged_run；改 inline 版同時寫 log + capture
    local ts_start; ts_start=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo ""
      echo "=== [$ts_start] import: load ${tarball} ==="
      echo "CMD: ${Container_Runtime} load -i ${tarball}"
    } >> "${Command_Output_log_file}"

    local tmp_out; tmp_out=$(mktemp)
    "${Container_Runtime}" load -i "${tarball}" > "${tmp_out}" 2>&1
    local load_rc=$?
    cat "${tmp_out}" >> "${Command_Output_log_file}"

    local ts_end; ts_end=$(date '+%Y-%m-%d %H:%M:%S')
    echo "=== [$ts_end] EXIT: $load_rc ===" >> "${Command_Output_log_file}"

    if [[ $load_rc -ne 0 ]]; then
      echo "Load ${tarball} failed (exit ${load_rc}). See ${Command_Output_log_file}" >&2
      rm -f "${tmp_out}"
      exit 1
    fi

    # 解析 `Loaded image: <ref>`（podman / docker 輸出格式一致）
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && loaded_images+=( "$line" )
    done < <(awk -F': ' '/^Loaded image:/ {print $2}' "${tmp_out}")

    rm -f "${tmp_out}"
  done

  if [[ ${#loaded_images[@]} -eq 0 ]]; then
    echo "No images loaded from input tarballs" >&2
    exit 1
  fi

  echo "Loaded ${#loaded_images[@]} images total from ${tarball_count} tarball(s)."
}

# 對 loaded_images 逐一做 retag（若需要）+ push
retag_and_push() {
  local total=${#loaded_images[@]}
  local idx=0
  local image src_registry after_reg src_namespace rest target_ref

  for image in "${loaded_images[@]}"; do
    idx=$((idx + 1))

    # 解析 source：<registry>/<namespace>/<rest...>
    src_registry="${image%%/*}"
    after_reg="${image#*/}"
    src_namespace="${after_reg%%/*}"
    rest="${after_reg#*/}"

    # 若 image 只有單段（沒有 /），after_reg == image；防呆處理
    if [[ "$src_registry" == "$image" ]]; then
      # 沒有 registry 前綴（理論上 Rancher airgap 不會出現）；直接拼 target
      target_ref="${Target_Registry_Name}/${Target_Registry_Namespace}/${image}"
      print_progress "retag" "$idx" "$total" "$image"
      if ! logged_run "import [$idx/$total] retag $image -> $target_ref" "${Container_Runtime}" tag "$image" "$target_ref"; then
        printf "\n" >/dev/tty 2>/dev/null || true
        echo "tag ${image} -> ${target_ref} failed" >&2
        exit 1
      fi
    elif [[ "$src_registry" == "$Target_Registry_Name" && "$src_namespace" == "$Target_Registry_Namespace" ]]; then
      # 已對齊，skip retag
      target_ref="$image"
    else
      target_ref="${Target_Registry_Name}/${Target_Registry_Namespace}/${rest}"
      print_progress "retag" "$idx" "$total" "$image"
      if ! logged_run "import [$idx/$total] retag $image -> $target_ref" "${Container_Runtime}" tag "$image" "$target_ref"; then
        printf "\n" >/dev/tty 2>/dev/null || true
        echo "tag ${image} -> ${target_ref} failed" >&2
        exit 1
      fi
    fi

    print_progress "push" "$idx" "$total" "$target_ref"
    if ! logged_run "import [$idx/$total] push $target_ref" "${Container_Runtime}" push "$target_ref"; then
      printf "\n" >/dev/tty 2>/dev/null || true
      echo "push ${target_ref} failed" >&2
      exit 1
    fi
  done

  printf "\n" >/dev/tty 2>/dev/null || true
}

# ----- main -----

setup_env "$@"
log_section "import START (Container_Runtime=${Container_Runtime} Target=${Target_Registry_Name}/${Target_Registry_Namespace})"

do_login
load_all_images "$@"
retag_and_push

total_images=${#loaded_images[@]}
echo "Import OK. Loaded ${total_images} images from $# tarball(s)."
echo "Pushed to: ${Target_Registry_Name}/${Target_Registry_Namespace}"
log_section "import END"
