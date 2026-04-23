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

# 印進度列到終端（同一行覆寫），非 TTY 時靜默。
# {...} 2>/dev/null 把 bash 對 `/dev/tty` 開啟失敗的錯誤訊息也吞掉，
# 避免非 TTY 執行環境（CI、被管線吃掉的 subshell）噴錯到 stderr。
print_progress() {
  { printf "\r\033[K[%s %d/%d] %s" "$1" "$2" "$3" "$4" >/dev/tty; } 2>/dev/null || true
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
  # 用 bash builtin `command -v`（POSIX）而非 `which`，後者在不同 distro／busybox
  # 行為不一致、且有些最小容器映像不含。
  if ! command -v "${Container_Runtime}" &> /dev/null; then
    echo "${Container_Runtime} command not found!" >&2
    exit 1
  fi

  # Target_Registry_Name 必填，且不得含 scheme／trailing slash（否則 podman tag 會失敗
  # 且錯誤訊息不直觀；在這裡先 fail-fast 給使用者清楚的修正提示）
  if [[ -z "${Target_Registry_Name}" ]]; then
    echo "Target_Registry_Name is required" >&2
    usage
  fi
  if [[ "${Target_Registry_Name}" =~ ^https?:// ]]; then
    echo "Target_Registry_Name 不可包含 scheme（https://／http://）；請改填純 hostname，例：harbor.customer.internal" >&2
    exit 1
  fi
  if [[ "${Target_Registry_Name}" == */ ]]; then
    echo "Target_Registry_Name 不可以 '/' 結尾；請改填純 hostname，例：harbor.customer.internal" >&2
    exit 1
  fi

  # Target_Registry_Namespace 預設 rancher（對齊 prepare 端 Private_Registry_Namespace）
  if [[ -z "${Target_Registry_Namespace}" ]]; then
    Target_Registry_Namespace="rancher"
  fi

  # Skip_Login 預設 0
  if [[ -z "${Skip_Login}" ]]; then
    Skip_Login="0"
  fi

  # Registry_Username／Registry_Password 半給的情境（只給其一）幾乎必然是使用者失誤；
  # 若放任 fall through 到互動模式會讓使用者誤以為 CI 非互動路徑生效、卻其實卡在
  # prompt 等 stdin。直接 fail-fast 讓錯誤訊息明確。
  # 測 Password 存在性會被 set -x 展開成密碼值寫進 xtrace；關 xtrace 測完再開。
  set +x
  if [[ -n "${Registry_Username}" && -z "${Registry_Password}" ]]; then
    set -x
    echo "Registry_Username is set but Registry_Password is empty. Provide both or neither." >&2
    exit 1
  fi
  if [[ -z "${Registry_Username}" && -n "${Registry_Password}" ]]; then
    set -x
    echo "Registry_Password is set but Registry_Username is empty. Provide both or neither." >&2
    exit 1
  fi
  set -x

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

  # 測密碼存在性的 [[ ]] 在 set -x 下會展開成 `[[ -n <密碼值> ]]` 寫進
  # Command_log_file；因此**在讀取 Registry_Password 變數前**先關 xtrace，
  # 只在後段走到互動分支時再打開。
  set +x
  local use_stdin=0
  if [[ -n "${Registry_Username}" && -n "${Registry_Password}" ]]; then
    use_stdin=1
  fi

  if [[ "$use_stdin" == "1" ]]; then
    # 非互動：password-stdin
    echo "Login to ${Target_Registry_Name} as ${Registry_Username} (non-interactive)..."
    local login_rc
    local ts_start; ts_start=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo ""
      echo "=== [$ts_start] import: login ${Target_Registry_Name} (--password-stdin) ==="
      echo "CMD: ${Container_Runtime} login -u ${Registry_Username} --password-stdin ${Target_Registry_Name}"
    } >> "${Command_Output_log_file}"

    echo "${Registry_Password}" | "${Container_Runtime}" login -u "${Registry_Username}" --password-stdin "${Target_Registry_Name}" >> "${Command_Output_log_file}" 2>&1
    login_rc=$?

    local ts_end; ts_end=$(date '+%Y-%m-%d %H:%M:%S')
    echo "=== [$ts_end] EXIT: $login_rc ===" >> "${Command_Output_log_file}"
    set -x

    if [[ $login_rc -ne 0 ]]; then
      echo "Login to ${Target_Registry_Name} failed" >&2
      exit 1
    fi
  else
    set -x
    # 互動：直接跑，讓 runtime 自己 prompt（stdin/stderr 不導開）
    echo "Login to ${Target_Registry_Name} (interactive prompt)..."

    # 互動模式無法像非互動分支那樣 redirect stdout/stderr 進 log（會讓 prompt 看不到）；
    # 仍然寫 start/exit 標記維持 log 結構一致性。
    local ts_start; ts_start=$(date '+%Y-%m-%d %H:%M:%S')
    {
      echo ""
      echo "=== [$ts_start] import: login ${Target_Registry_Name} (interactive) ==="
      echo "CMD: ${Container_Runtime} login ${Target_Registry_Name}"
      echo "(互動模式，stdout/stderr 不導入 log 以免吞掉 prompt)"
    } >> "${Command_Output_log_file}"

    "${Container_Runtime}" login "${Target_Registry_Name}"
    local login_rc=$?

    local ts_end; ts_end=$(date '+%Y-%m-%d %H:%M:%S')
    echo "=== [$ts_end] EXIT: $login_rc ===" >> "${Command_Output_log_file}"

    if [[ $login_rc -ne 0 ]]; then
      echo "Login to ${Target_Registry_Name} failed" >&2
      exit 1
    fi
  fi
}

# 依序 load 所有 image tarball，並把 `Loaded image: <ref>` 解析到 loaded_images 陣列
#
# 注意：loaded_images 是**刻意宣告為 global**（無 local），供 retag_and_push 讀取。
# 請勿加 `local` 否則會破壞跨函式的 state 傳遞。若要改為參數傳遞需同步修改兩個函式。
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
    local before_count=${#loaded_images[@]}
    local line
    while IFS= read -r line; do
      [[ -n "$line" ]] && loaded_images+=( "$line" )
    done < <(awk -F': ' '/^Loaded image:/ {print $2}' "${tmp_out}")
    local after_count=${#loaded_images[@]}

    rm -f "${tmp_out}"

    # 個別 tarball 沒有帶出任何 image 時警告（使用者很可能誤傳 helm chart tgz
    # 或配置檔等非 image tarball）。不阻擋流程，讓後續 tarball 繼續 load；
    # 若所有 tarball 加總仍為 0 則最後統一 exit 1。
    if [[ $after_count -eq $before_count ]]; then
      echo "Warning: ${tarball} 未帶出任何 'Loaded image:' 條目（可能不是 image tar.gz）" >&2
    fi
  done

  # 去重：同一個 image ref 若出現在多個 tarball（或同一 tarball 被傳了兩次），
  # retag/push 會做冗餘工作與錯誤計數；用 awk '!seen[$0]++' 保留首見順序做 dedup。
  # awk 失敗極罕見（理論上只有 OOM 才可能），但為了 defensive 檢查 PIPESTATUS。
  if [[ ${#loaded_images[@]} -gt 0 ]]; then
    local dedup_out
    dedup_out=$(printf '%s\n' "${loaded_images[@]}" | awk '!seen[$0]++')
    local pipe_rc=${PIPESTATUS[1]}
    if [[ $pipe_rc -ne 0 ]]; then
      echo "Dedup awk failed (exit ${pipe_rc}); 保留原始 loaded_images 繼續執行" >&2
    else
      local deduped=()
      local img
      while IFS= read -r img; do
        [[ -n "$img" ]] && deduped+=( "$img" )
      done <<< "$dedup_out"
      local before_dedup=${#loaded_images[@]}
      loaded_images=( "${deduped[@]}" )
      local after_dedup=${#loaded_images[@]}
      if [[ $after_dedup -lt $before_dedup ]]; then
        echo "Deduped $((before_dedup - after_dedup)) duplicate image ref(s)."
      fi
    fi
  fi

  if [[ ${#loaded_images[@]} -eq 0 ]]; then
    echo "No images loaded from input tarballs" >&2
    exit 1
  fi

  echo "Loaded ${#loaded_images[@]} images total from ${tarball_count} tarball(s)."
}

# 計算 loaded image 的目標 ref。
# - image 無 `/`（單段，非 Rancher airgap 常見）→ prepend Target_Registry_Name/Namespace
# - src_registry + src_namespace 已對齊 Target → 回傳原 image（skip retag）
# - 其他 → 替換前兩段為 Target_Registry_Name/Namespace
compute_target_ref() {
  local image="$1"
  local src_registry after_reg src_namespace rest
  src_registry="${image%%/*}"
  after_reg="${image#*/}"
  src_namespace="${after_reg%%/*}"
  rest="${after_reg#*/}"

  if [[ "$src_registry" == "$image" ]]; then
    # 沒有 registry 前綴（image 只有單段）
    echo "${Target_Registry_Name}/${Target_Registry_Namespace}/${image}"
  elif [[ "$src_registry" == "$Target_Registry_Name" && "$src_namespace" == "$Target_Registry_Namespace" ]]; then
    echo "$image"
  else
    echo "${Target_Registry_Name}/${Target_Registry_Namespace}/${rest}"
  fi
}

# 對 loaded_images 逐一做 retag（若需要）+ push
# 將 retag／skip 計數寫到 global retag_count／skip_count 供 summary 使用
retag_and_push() {
  local total=${#loaded_images[@]}
  local idx=0
  local image target_ref
  retag_count=0
  skip_count=0

  for image in "${loaded_images[@]}"; do
    idx=$((idx + 1))

    target_ref=$(compute_target_ref "$image")

    # 只有 target_ref 與 image 不同時才真的 tag；相同就 skip
    if [[ "$target_ref" != "$image" ]]; then
      retag_count=$((retag_count + 1))
      print_progress "retag" "$idx" "$total" "$image"
      if ! logged_run "import [$idx/$total] retag $image -> $target_ref" "${Container_Runtime}" tag "$image" "$target_ref"; then
        { printf "\n" >/dev/tty; } 2>/dev/null || true
        echo "tag ${image} -> ${target_ref} failed" >&2
        exit 1
      fi
    else
      skip_count=$((skip_count + 1))
    fi

    print_progress "push" "$idx" "$total" "$target_ref"
    if ! logged_run "import [$idx/$total] push $target_ref" "${Container_Runtime}" push "$target_ref"; then
      { printf "\n" >/dev/tty; } 2>/dev/null || true
      echo "push ${target_ref} failed" >&2
      exit 1
    fi
  done

  { printf "\n" >/dev/tty; } 2>/dev/null || true
}

# ----- main -----

setup_env "$@"

# 使用者若 tail -f log 想知道「跑完了沒／退出碼是什麼」，無論成功或中途
# exit 1 都要有 END 標記（帶 exit code）可收斂；用 trap 保證這件事。
# 放在 setup_env 之後：validation 階段的錯誤不需要污染 log 檔。
# INT/TERM 理論上 EXIT 會在其後自動 fire，但顯式列出意圖更明確。
trap 'log_section "import END (exit=$?)"' EXIT INT TERM

start_ts=$SECONDS

log_section "import START (Container_Runtime=${Container_Runtime} Target=${Target_Registry_Name}/${Target_Registry_Namespace})"

do_login
load_all_images "$@"
retag_and_push

total_images=${#loaded_images[@]}
elapsed=$((SECONDS - start_ts))

echo ""
echo "Import OK."
echo "  Runtime:   ${Container_Runtime}"
echo "  Target:    ${Target_Registry_Name}/${Target_Registry_Namespace}"
echo "  Tarballs:  $#"
echo "  Images:    ${total_images} loaded, ${total_images} pushed (${retag_count} retagged, ${skip_count} already aligned)"
echo "  Elapsed:   ${elapsed}s"
echo "  Logs:      ${Command_log_file}"
echo "             ${Command_Output_log_file}"
