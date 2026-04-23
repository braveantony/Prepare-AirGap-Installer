#!/bin/bash

# 設定 Debug 模式
## 預設將執行中的指令及其參數重新導向到 /tmp/prepare_message.log 檔案中
[[ -z "${Command_log_file}" ]] && Command_log_file="/tmp/prepare_message.log"
[[ -f "${Command_log_file}" ]] && sudo rm "${Command_log_file}"
exec {BASH_XTRACEFD}>>"${Command_log_file}"
export PS4='+ [$(date +%H:%M:%S)] ${BASH_SOURCE##*/}:${LINENO}: '
set -x

## 預設確保命令執行後的輸出重定向到 /tmp/prepare_output_message.log 檔案中
[[ -z "${Command_Output_log_file}" ]] && Command_Output_log_file="/tmp/prepare_output_message.log"
[[ -f "${Command_Output_log_file}" ]] && sudo rm "${Command_Output_log_file}"

usage() {
  cat <<EOF
Usage:
  ENV_VAR=... $(basename "${BASH_SOURCE[0]}") [options]

Available options:

all        一次準備 Harbor、RKE2、Rancher、K3S、Neuvector 的全離線安裝包
harbor     只準備 Harbor 的全離線安裝包
rke2       只準備 RKE2 的全離線安裝包
rancher    只準備 Rancher 的全離線安裝包
neuvector  只準備 Neuvector 的全離線安裝包
k3s        只準備 K3S 的全離線安裝包

Environment variables:

   - Harbor_Version
     定義 Harbor 的版本
     預設是 'v2.15.0'。

   - Docker_Compose_Version
     定義 docker-compose 的版本
     預設是 'v2.40.3'。

   - RKE2_Version
     定義 RKE2 的版本
     預設是 'v1.35.3'。

   - RKE2_Revision
     定義 RKE2 的 revision 後綴
     預設是 'rke2r3'。

   - RKE2_Source_URL
     定義下載 RKE2 airgap artifact 的來源 URL
     預設是 'https://prime.ribs.rancher.io'（Rancher Prime Artifacts）。

   - Rancher_Version
     定義 Rancher 的版本
     預設是 'v2.13.4'。

   - Rancher_Source_URL
     定義下載 Rancher airgap artifact 的來源 URL
     預設是 'https://prime.ribs.rancher.io'（Rancher Prime Artifacts）。

   - Helm_Version
     定義 Helm 的版本
     預設是 'v3.20.2'。

   - Cert_Manager_Version
     定義 Cert-manager 的版本
     預設是 'v1.20.2'。

   - K3S_Version
     定義 K3S 的版本
     預設是 'v1.35.3'。

   - K3S_Revision
     定義 K3S 的 revision 後綴
     預設是 'k3s1'。

   - K3S_Source_URL
     定義下載 K3S airgap artifact 的來源 URL
     預設是 'https://prime.ribs.rancher.io'（Rancher Prime Artifacts）。

   - Neuvector_Version
     定義 Neuvector 的版本
     預設是 '5.5.0'。

   - Private_Registry_Name
     定義企業內部私有 Image Registry 的名稱
     預設是 'harbor.example.com'。

   - Private_Registry_Namespace
     定義企業內部私有 Image Registry 下的第二層 namespace／project 名稱
     （retag 成 <Private_Registry_Name>/<Private_Registry_Namespace>/<image>）
     預設是 'rancher'（例：harbor.example.com/rancher/...）。
     Rancher Prime 離線環境常設為 'rancher-prime'。

   - Command_log_file
     將執行的命令重新導向到 /tmp/prepare_message.log
     預設是 '/tmp/prepare_message.log'。

   - Command_Output_log_file
     將命令執行後的輸出重新導向到 /tmp/prepare_output_message.log
     預設是 '/tmp/prepare_output_message.log'。

   - Container_Runtime
     選擇 container runtime，可設為 'docker' 或 'podman'
     預設 auto-detect（優先 'podman'；若 podman 不可用則 'docker'）
     設為 'docker' 時會使用 'sudo docker'（需可免密碼 sudo）

Example:
  ## 一次準備 Harbor、RKE2、Rancher、K3S、Neuvector 的全離線安裝包，並且指定安裝 Harbor 特定版本
  \$ Harbor_Version=v2.7.0 ./prepare.sh all

  ## 只準備 Rancher 的全離線安裝包，並且指定安裝 Rancher v2.7.9 版本
  \$ Rancher_Version=v2.7.9 ./prepare.sh rancher

  ## 準備 Neuvector 的全離線安裝包，並且指定安裝 Neuvector 5.2.0 版本
  \$ Neuvector_Version=5.2.0 ./prepare.sh neuvector

  ## 同時準備 Rancher、Harbor 和 K3S 的全離線安裝包，分別指定安裝 v2.7.9、v2.7.0 和 v1.25.9 版本，並設定私有 Image Registry 的名稱
  \$ Rancher_Version=v2.7.9 Harbor_Version=v2.7.0 K3S_Version=v1.25.9 \\
  Private_Registry_Name="antony-harbor.example.com" \\
  ./prepare.sh rancher harbor k3s

  ## 顯式使用 docker 而非 auto-detect（需可免密碼 sudo）
  \$ Container_Runtime=docker Rancher_Version=v2.13.4 ./prepare.sh rancher
EOF
  exit
}

[[ "$#" -eq "0" ]] && usage

# Confirm the environment required for program execution and define predefined variables
setup_env() {
  # check internet connection
  if ! nc -vz google.com 443 &> /dev/null; then
    echo "internet connection is offline" && exit 1
  fi

  # Container_Runtime 分派：未設定時 auto-detect（優先 podman；fallback docker）
  if [[ -z "${Container_Runtime}" ]]; then
    if command -v podman &>/dev/null; then
      Container_Runtime="podman"
    elif command -v docker &>/dev/null; then
      Container_Runtime="docker"
    else
      echo "neither podman nor docker found; set Container_Runtime explicitly" >&2
      exit 1
    fi
  fi
  case "${Container_Runtime}" in
    docker|podman) ;;
    *) echo "Container_Runtime must be 'docker' or 'podman', got: '${Container_Runtime}'" >&2; exit 1 ;;
  esac
  if ! command -v "${Container_Runtime}" &>/dev/null; then
    echo "${Container_Runtime} command not found!" >&2
    exit 1
  fi

  # check Command is installed
  for command in wget curl helm
  do
    if ! which $command &> /dev/null; then
      echo "${command} command not found!" && exit 1
    fi
  done

  # make sure the version of the Harbor is defined
  if [[ -z "${Harbor_Version}" ]]; then
    Harbor_Version="v2.15.0"
  fi

  # make sure the version of the Docker-compose is defined
  if [[ -z "${Docker_Compose_Version}" ]]; then
    Docker_Compose_Version="v2.40.3"
  fi

  # make sure the version of the RKE2 is defined
  if [[ -z "${RKE2_Version}" ]]; then
    RKE2_Version="v1.35.3"
  fi

  # make sure the revision of the RKE2 is defined
  if [[ -z "${RKE2_Revision}" ]]; then
    RKE2_Revision="rke2r3"
  fi

  # make sure the URL of the RKE2 source is defined
  if [[ -z "${RKE2_Source_URL}" ]]; then
    RKE2_Source_URL="https://prime.ribs.rancher.io"
  fi

  # make sure the version of the Rancher is defined
  if [[ -z "${Rancher_Version}" ]]; then
    Rancher_Version="v2.13.4"
  fi

  # make sure the URL of the Rancher source is defined
  if [[ -z "${Rancher_Source_URL}" ]]; then
    Rancher_Source_URL="https://prime.ribs.rancher.io"
  fi

  # make sure the version of the Helm is defined
  if [[ -z "${Helm_Version}" ]]; then
    Helm_Version="v3.20.2"
  fi

  # make sure the version of the Cert-Manager is defined
  if [[ -z "${Cert_Manager_Version}" ]]; then
    Cert_Manager_Version="v1.20.2"
  fi

  # make sure the version of the K3S is defined
  if [[ -z "${K3S_Version}" ]]; then
    K3S_Version="v1.35.3"
  fi

  # make sure the revision of the K3S is defined
  if [[ -z "${K3S_Revision}" ]]; then
    K3S_Revision="k3s1"
  fi

  # make sure the URL of the K3S source is defined
  if [[ -z "${K3S_Source_URL}" ]]; then
    K3S_Source_URL="https://prime.ribs.rancher.io"
  fi

  # make sure the version of the Neuvector is defined
  if [[ -z "${Neuvector_Version}" ]]; then
    Neuvector_Version="5.5.0"
  fi

  # make sure the name of the Private Images Registry is defined
  if [[ -z "${Private_Registry_Name}" ]]; then
    Private_Registry_Name="harbor.example.com"
  fi

  # make sure the namespace/project under the Private Images Registry is defined
  if [[ -z "${Private_Registry_Namespace}" ]]; then
    Private_Registry_Namespace="rancher"
  fi

  # Helm 與 k8s n-3 相容性 pre-flight check；fail 時 exit 以避免打包出無法用的 airgap 包
  if ! helm_version_skew_check; then
    echo "[helm version skew] 版本不相容，停止執行。詳見 https://helm.sh/docs/topics/version_skew/" >&2
    exit 1
  fi
}

# 印進度列到終端（同一行覆寫），非 TTY 時靜默
print_progress() {
  printf "\r\033[K[%s %d/%d] %s" "$1" "$2" "$3" "$4" >/dev/tty 2>/dev/null || true
}

# Runtime CLI prefix wrapper：docker 需要 sudo（rootful），podman 走 rootless
# 使用：$(cr_cmd) pull foo、$(cr_cmd) tag a b
cr_cmd() {
  if [[ "${Container_Runtime}" == "docker" ]]; then
    echo "sudo docker"
  else
    echo "podman"
  fi
}

# save 的 multi-image flag：podman 需要 -m（manifest list），docker 原生多 arg 不需要
cr_save_flags() {
  [[ "${Container_Runtime}" == "podman" ]] && echo "-m"
}

# 呼叫 function/command 並把 stdout/stderr 導入 log 檔；若呼叫者非零結束，
# 整支腳本立即以相同 exit code 結束（用 PIPESTATUS[0] 取 pipeline 第一段狀態，
# 避免 `prepare_* | tee` 把 function 包進 subshell 後 `exit 1` 只結束 subshell 的問題）
run_step() {
  "$@" 2>&1 | tee -a "${Command_Output_log_file}"
  local rc=${PIPESTATUS[0]}
  [[ $rc -ne 0 ]] && exit $rc
  return 0
}

# 在合併 log 檔寫一個醒目的 section 分隔符，用來標記 prepare_* 函式的進入與結束
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
# 回傳值為原命令的 exit code，呼叫端既有 `[[ "$?" != "0" ]] && echo ... && exit 1` 仍適用。
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

# 檢查 ${Helm_Version} compiled-against 的 k8s minor 與 ${RKE2_Version}／${K3S_Version}
# 是否落在 Helm n-3 support window 內（https://helm.sh/docs/topics/version_skew/）。
# 規律（v3.x 系列）：Helm 3.N 對應 k8s.io/client-go v0.(N+15) → k8s 1.(N+15)。
# 例：v3.20 → k8s 1.35，支援 1.32 – 1.35；v3.14 → k8s 1.29，支援 1.26 – 1.29。
# 非 v3.x（例：v4.x）目前不自動判斷，僅 echo 提示請使用者自行對照文件。
helm_version_skew_check() {
  local helm_ver="${Helm_Version#v}"
  local helm_major="${helm_ver%%.*}"
  local helm_minor_rest="${helm_ver#*.}"
  local helm_minor="${helm_minor_rest%%.*}"

  if [[ "$helm_major" != "3" ]]; then
    echo "[helm version skew] Helm_Version=${Helm_Version} 非 v3.x，跳過自動相容性檢查；請自行對照 https://helm.sh/docs/topics/version_skew/" >&2
    return 0
  fi

  local helm_k8s_target=$((helm_minor + 15))       # e.g. Helm 3.20 → k8s 1.35
  local helm_k8s_min=$((helm_k8s_target - 3))      # n-3 下界，e.g. 1.32

  local target_names=("RKE2" "K3S")
  local target_vars=("${RKE2_Version}" "${K3S_Version}")
  local rc=0
  local i
  for i in "${!target_vars[@]}"; do
    local tv="${target_vars[$i]#v}"
    local tn="${target_names[$i]}"
    local t_major="${tv%%.*}"
    local t_minor_rest="${tv#*.}"
    local t_minor="${t_minor_rest%%.*}"

    if [[ "$t_major" != "1" ]]; then
      echo "[helm version skew] ${tn}_Version=${target_vars[$i]} 非 v1.x，跳過" >&2
      continue
    fi

    if (( t_minor > helm_k8s_target )); then
      echo "[helm version skew] ${tn}_Version=${target_vars[$i]}（k8s 1.${t_minor}）比 Helm_Version=${Helm_Version} compiled-against 的 k8s 1.${helm_k8s_target} 還新；超出 Helm 支援範圍 → 升 Helm_Version" >&2
      rc=1
    elif (( t_minor < helm_k8s_min )); then
      echo "[helm version skew] ${tn}_Version=${target_vars[$i]}（k8s 1.${t_minor}）早於 Helm_Version=${Helm_Version} 的 n-3 下界 1.${helm_k8s_min} → 降 Helm_Version 或升 ${tn}_Version" >&2
      rc=1
    fi
  done
  return $rc
}

# 建立工作目錄
create_working_directory() {
  setup_env
  mkdir -p ~/work/{harbor/"${Harbor_Version}",rke2/"${RKE2_Version}",rancher/"${Rancher_Version}",k3s/"${K3S_Version}",neuvector/"${Neuvector_Version}",compressed_files}
}

# 準備 Harbor 全離線安裝包
prepare_harbor() {
  setup_env
  log_section "prepare_harbor START (Harbor_Version=${Harbor_Version})"

  # 清除本產品前次產出的離線安裝包，避免與本次新版並存
  rm -f ~/work/compressed_files/harbor-offline-*.tar.gz

  # 切換工作目錄
  cd ~/work/harbor/"${Harbor_Version}"

  # 下載 Harbor 壓縮檔（-nv：non-verbose；-O：顯式覆寫同名檔，避免重跑時產生 *.1）
  logged_run "harbor: download offline-installer tgz" wget -nv -O harbor-offline-installer-"${Harbor_Version}".tgz https://github.com/goharbor/harbor/releases/download/"${Harbor_Version}"/harbor-offline-installer-"${Harbor_Version}".tgz
  [[ "$?" != "0" ]] && echo "Download harbor-offline-installer-"${Harbor_Version}".tgz failed" && exit 1

  # 下載 Docker Compose 套件（-O 同上原因）
  logged_run "harbor: download docker-compose" wget -nv -O docker-compose-linux-x86_64 https://github.com/docker/compose/releases/download/"${Docker_Compose_Version}"/docker-compose-linux-x86_64
  [[ "$?" != "0" ]] && echo "Download docker-compose-linux-x86_64 "${Docker_Compose_Version}" failed" && exit 1

  # 將以上離線安裝 Harbor 所需之套件壓縮成一個檔案
  cd ../..
  logged_run "harbor: tar airgap bundle" tar -czvf compressed_files/harbor-offline-"${Harbor_Version}".tar.gz harbor/"${Harbor_Version}"
  if [[ "$?" != "0" ]]; then
    echo "Preparing harbor full Air Gap installer failed" && exit 1
  else
    echo "Prepare Harbor "${Harbor_Version}" OK."
  fi
  log_section "prepare_harbor END"
}

# 準備 RKE2 全離線安裝包
prepare_rke2() {
  setup_env
  log_section "prepare_rke2 START (RKE2_Version=${RKE2_Version}, RKE2_Revision=${RKE2_Revision})"

  # 清除本產品前次產出的離線安裝包，避免與本次新版並存
  rm -f ~/work/compressed_files/rke2-airgap-*.tar.gz

  # 切換工作目錄
  cd ~/work/rke2/"${RKE2_Version}"

  # 下載離線安裝 RKE2 所需 Image 之壓縮檔
  logged_run "rke2: download rke2-images.linux-amd64.tar.zst" curl -s -OL "${RKE2_Source_URL}"/rke2/"${RKE2_Version}"%2B"${RKE2_Revision}"/rke2-images.linux-amd64.tar.zst
  [[ "$?" != "0" ]] && echo "Download rke2-images.linux-amd64.tar.zst "${RKE2_Version}" failed" && exit 1

  logged_run "rke2: download rke2.linux-amd64.tar.gz" curl -s -OL "${RKE2_Source_URL}"/rke2/"${RKE2_Version}"%2B"${RKE2_Revision}"/rke2.linux-amd64.tar.gz
  [[ "$?" != "0" ]] && echo "Download rke2.linux-amd64.tar.gz "${RKE2_Version}" failed" && exit 1

  logged_run "rke2: download sha256sum-amd64.txt" curl -s -OL "${RKE2_Source_URL}"/rke2/"${RKE2_Version}"%2B"${RKE2_Revision}"/sha256sum-amd64.txt
  [[ "$?" != "0" ]] && echo "Download sha256sum-amd64.txt "${RKE2_Version}" failed" && exit 1

  # 下載官網提供的離線安裝 RKE2 所需之安裝腳本，並賦予它執行權限
  logged_run "rke2: download install.sh" curl -sfL https://get.rke2.io --output install.sh
  [[ "$?" != "0" ]] && echo "Download rke2 install.sh failed" && exit 1
  logged_run "rke2: chmod install.sh" chmod +x install.sh

  # 將以上離線安裝 RKE2 所需之檔案，壓縮成一個檔案
  cd ../..
  logged_run "rke2: tar airgap bundle" tar -czvf compressed_files/rke2-airgap-"${RKE2_Version}".tar.gz rke2/"${RKE2_Version}"
  if [[ "$?" != "0" ]]; then
    echo "Preparing RKE2 Air Gap installer failed" && exit 1
  else
    echo "Prepare RKE2 "${RKE2_Version}" OK."
  fi
  log_section "prepare_rke2 END"
}

# 準備 Rancher Prime 全離線安裝包
prepare_rancher() {

  setup_env
  log_section "prepare_rancher START (Rancher_Version=${Rancher_Version})"

  # 清除本產品前次產出的離線安裝包，避免與本次新版並存
  rm -f ~/work/compressed_files/rancher-airgap-*.tar.gz

  # 切換工作目錄
  cd ~/work/rancher/"${Rancher_Version}"

  # helm 由 setup_env 的 required-command 檢查確保存在；不再 curl|bash 從 helm/main
  # 分支安裝（floating branch 會破壞「相同 commit → 相同產物」的可重現性）

  # 新增並刷新 Rancher Prime 的 Helm Chart Repository
  logged_run "rancher: helm repo add rancher-prime" helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
  [[ "$?" != "0" ]] && echo "helm repo add rancher-prime failed" && exit 1
  logged_run "rancher: helm repo update (rancher-prime)" helm repo update
  [[ "$?" != "0" ]] && echo "helm repo update (rancher-prime) failed" && exit 1

  # 下載 Rancher chart
  logged_run "rancher: helm pull rancher chart" helm pull rancher-prime/rancher --version="${Rancher_Version}"
  [[ "$?" != "0" ]] && echo "helm pull rancher failed" && exit 1

  # 新增和刷新 cert-manager repo
  logged_run "rancher: helm repo add jetstack" helm repo add jetstack https://charts.jetstack.io
  [[ "$?" != "0" ]] && echo "helm repo add jetstack failed" && exit 1
  logged_run "rancher: helm repo update (jetstack)" helm repo update
  [[ "$?" != "0" ]] && echo "helm repo update (jetstack) failed" && exit 1

  # 下載 cert-manager chart
  logged_run "rancher: helm pull cert-manager chart" helm pull jetstack/cert-manager --version "${Cert_Manager_Version}"
  [[ "$?" != "0" ]] && echo "helm pull Cert_Manager failed" && exit 1

  # 下載 cert-manager 要求的 CRD（-sSL：silent + show-error + follow-redirect）
  logged_run "rancher: download cert-manager CRD" curl -sSL -o cert-manager-crd.yaml https://github.com/cert-manager/cert-manager/releases/download/"${Cert_Manager_Version}"/cert-manager.crds.yaml
  [[ "$?" != "0" ]] && echo "Download Cert_Manager CRD failed" && exit 1

  # 下載 cert-manager 官方 combined install manifest（kubectl apply 路徑用；版本跟著 ${Cert_Manager_Version}）
  logged_run "rancher: download cert-manager manifest" curl -sSL -o cert-manager.yaml https://github.com/cert-manager/cert-manager/releases/download/"${Cert_Manager_Version}"/cert-manager.yaml
  [[ "$?" != "0" ]] && echo "Download Cert_Manager manifest failed" && exit 1

  # 處理 cert-manager 的 Container Images
  # 先計算 cert-manager 所需 image 總量，作為進度列的分母
  cert_manager_images=$(helm template cert-manager-*.tgz | awk '$1 ~ /image:/ {print $2}' | sed -e 's/\"//g')
  cert_manager_total=$(echo "$cert_manager_images" | wc -l)
  idx=0
  for image in $cert_manager_images
  do
    idx=$((idx + 1))
    print_progress "cert-manager" "$idx" "$cert_manager_total" "$image"

    # 下載 cert-manager 的 Container Images
    logged_run "cert-manager [$idx/$cert_manager_total] pull $image" $(cr_cmd) pull "$image"
    [[ "$?" != "0" ]] && { printf "\n" >/dev/tty 2>/dev/null; echo "Pull $image failed"; exit 1; }

    # 修改 cert-manager 的所有 Container Images Tag
    logged_run "cert-manager [$idx/$cert_manager_total] tag $image" $(cr_cmd) tag "${image}" "${Private_Registry_Name}"/"${Private_Registry_Namespace}"/"${image##*/}"
    [[ "$?" != "0" ]] && { printf "\n" >/dev/tty 2>/dev/null; echo "tag ${Private_Registry_Name}/${Private_Registry_Namespace}/${image##*/} Container images failed"; exit 1; }
  done
  printf "\n" >/dev/tty 2>/dev/null || true

  # 將 cert-manager 的所有 Container Images 打包成 .tar.gz 壓縮檔
  # 復用前面計算好的 $cert_manager_images，避免重新跑一次 helm template
  # pipe 用 bash -c 包，set -o pipefail 讓 save 或 gzip 任一段失敗都能正確回傳
  cert_manager_renamed_images=$(echo "$cert_manager_images" | sed "s|quay.io/jetstack|${Private_Registry_Name}/${Private_Registry_Namespace}|g" | tr '\n' ' ')
  logged_run "cert-manager: save images tar.gz" bash -c "set -o pipefail; $(cr_cmd) save $(cr_save_flags) ${cert_manager_renamed_images} | gzip --stdout > cert-manager-image-${Cert_Manager_Version}.tar.gz"
  [[ "$?" != "0" ]] && echo "${Container_Runtime} save Cert-manager ${Cert_Manager_Version} images failed" && exit 1

  # 下載 Helm 壓縮檔
  logged_run "rancher: download helm ${Helm_Version} tarball" wget -q https://get.helm.sh/helm-"${Helm_Version}"-linux-amd64.tar.gz -O helm-"${Helm_Version}"-linux-amd64.tar.gz
  [[ "$?" != "0" ]] && echo "Download helm ${Helm_Version} failed" && exit 1

  # 下載 Rancher Images List 文字檔及蒐集 Image 所需的 Shell Script
  # -O "${x}"：顯式覆寫同名檔，避免重跑時產生 *.1；舊檔殘留會讓下游 sort -u
  # 作用在錯的檔（變成前次的 image list），打包出錯到的 tarball
  for x in rancher-images.txt rancher-load-images.sh rancher-save-images.sh
  do
    logged_run "rancher: download $x" wget -q -O "${x}" "${Rancher_Source_URL}"/rancher/"${Rancher_Version}"/"${x}"
    [[ "$?" != "0" ]] && echo "Download ${x} failed" && exit 1
  done

  # 對 Image List 進行排序和唯一化，以消除來源之間的任何重疊
  logged_run "rancher: sort-uniq rancher-images.txt" sort -u rancher-images.txt -o rancher-images.txt

  # Rancher v2.12+ 的 rancher-images.txt 會包含以 `rancher/charts/` 開頭的 Helm chart
  # OCI artifact（mediaType application/vnd.cncf.helm.config.v1+json），這些不是
  # container image，用 podman/docker pull 會報 `unsupported image-specific operation
  # on artifact` 並失敗；filter 掉讓主 pull loop 只處理 container image。
  # 若未來需要一併打包這類 chart artifact，需改用 helm pull oci:// 或 oras pull。
  logged_run "rancher: filter out Helm chart OCI artifacts" sed -i '/^rancher\/charts\//d' rancher-images.txt
  [[ "$?" != "0" ]] && echo "Filter Helm chart OCI artifacts from rancher-images.txt failed" && exit 1

  echo "Start pulling and saving rancher ${Rancher_Version} images..."
  # 下載離線安裝 Rancher 所需的所有 Container Images 並打包成 rancher-images.tar.gz
  rancher_total=$(wc -l < rancher-images.txt)
  idx=0
  # `|| [[ -n "$image" ]]`：若檔案最後一行無 trailing newline，read 會回非零但
  # 仍把該行讀進 $image，補這個判斷才不會漏最後一行
  while IFS= read -r image || [[ -n "$image" ]]
  do
    idx=$((idx + 1))
    print_progress "rancher" "$idx" "$rancher_total" "$image"
    if ! logged_run "rancher [$idx/$rancher_total] pull $image" $(cr_cmd) pull registry.rancher.com/"${image}"; then
      printf "\n" >/dev/tty 2>/dev/null || true
      echo pull "$image" failed && exit 1
    fi
  done < rancher-images.txt
  printf "\n" >/dev/tty 2>/dev/null || true

  # 主 pull loop 已保證所有 image 都 pull 成功（任一失敗即 exit），此處只負責 retag；
  # 用 ${image#rancher/} 對齊下方 save 時的 sed 改寫規則（保留多層路徑），避免 single-level
  # ${n##*/} 與 multi-level sed 對不上導致 container runtime save 找不到 tag 的 latent bug。
  while IFS= read -r image || [[ -n "$image" ]]
  do
    src="registry.rancher.com/${image}"
    dst="${Private_Registry_Name}/${Private_Registry_Namespace}/${image#rancher/}"
    logged_run "rancher tag $image" $(cr_cmd) tag "$src" "$dst"
    [[ "$?" != "0" ]] && echo "tag $dst failed" && exit 1
  done < rancher-images.txt

  # save 為 pipe，用 bash -c + pipefail 包進 logged_run
  # 把 rancher-images.txt 中以 'rancher/' 開頭的項目改寫成 <registry>/<namespace>/；
  # 預設 Private_Registry_Namespace=rancher 時等價於原「prepend ${registry}/」行為
  rename_rancher_all_image=$(cat rancher-images.txt | sed "s|^rancher/|${Private_Registry_Name}/${Private_Registry_Namespace}/|" | tr '\n' ' ')
  logged_run "rancher: save images tar.gz" bash -c "set -o pipefail; $(cr_cmd) save $(cr_save_flags) ${rename_rancher_all_image} | gzip --stdout > rancher-${Rancher_Version}-image.tar.gz"
  [[ (( $(stat -c%s rancher-"${Rancher_Version}"-image.tar.gz) -lt 50000000 )) ]] && echo "${Container_Runtime} save rancher ${Rancher_Version} images failed" && exit 1

  cd ../..
  logged_run "rancher: tar airgap bundle" tar -czf compressed_files/rancher-airgap-"${Rancher_Version}".tar.gz rancher/"${Rancher_Version}"
  if [[ "$?" != "0" ]]; then
    echo "Preparing Rancher "${Rancher_Version}" Air Gap installer failed" && exit 1
  else
    echo "Prepare Rancher "${Rancher_Version}" OK."
  fi
  log_section "prepare_rancher END"
}

prepare_k3s() {
  setup_env
  log_section "prepare_k3s START (K3S_Version=${K3S_Version})"

  # 清除本產品前次產出的離線安裝包，避免與本次新版並存
  rm -f ~/work/compressed_files/k3s-airgap-*.tar.gz

  # 切換工作目錄
  cd ~/work/k3s/"${K3S_Version}"

  # -sSL：silent + show-error + follow-redirect，去掉 -# 的 hash progress bar
  logged_run "k3s: download k3s-airgap-images-amd64.tar" curl -sSL -O "${K3S_Source_URL}"/k3s/"${K3S_Version}"%2B"${K3S_Revision}"/k3s-airgap-images-amd64.tar
  [[ "$?" != "0" ]] && echo "Download k3s-airgap-images-amd64.tar ${K3S_Version} failed" && exit 1

  logged_run "k3s: download k3s binary" curl -sSL -O "${K3S_Source_URL}"/k3s/"${K3S_Version}"%2B"${K3S_Revision}"/k3s
  [[ "$?" != "0" ]] && echo "Download k3s Binary File ${K3S_Version} failed" && exit 1

  logged_run "k3s: download install.sh" curl -sfL https://get.k3s.io/ --output install.sh
  [[ "$?" != "0" ]] && echo "Download k3s Official Installation Script failed" && exit 1
  logged_run "k3s: chmod install.sh" chmod +x install.sh

  cd ../..
  logged_run "k3s: tar airgap bundle" tar -czf compressed_files/k3s-airgap-"${K3S_Version}".tar.gz k3s/"${K3S_Version}"
  if [[ "$?" != "0" ]]; then
    echo "Preparing K3S ${K3S_Version} Air Gap installer failed" && exit 1
  else
    echo "Prepare K3S "${K3S_Version}" OK."
  fi
  log_section "prepare_k3s END"
}

prepare_neuvector() {
  setup_env
  log_section "prepare_neuvector START (Neuvector_Version=${Neuvector_Version})"

  # 清除本產品前次產出的離線安裝包，避免與本次新版並存
  rm -f ~/work/compressed_files/neuvector-airgap-*.tar.gz

  # 切換工作目錄
  cd ~/work/neuvector/"${Neuvector_Version}"

  # helm 由 setup_env 的 required-command 檢查確保存在；不再 curl|bash 從 helm/main
  # 分支安裝（floating branch 會破壞「相同 commit → 相同產物」的可重現性）

  # add repo
  logged_run "neuvector: helm repo add" helm repo add neuvector https://neuvector.github.io/neuvector-helm/
  [[ "$?" != "0" ]] && echo "Add Neuvector Helm Repo failed" && exit 1

  # update local chart
  logged_run "neuvector: helm repo update" helm repo update
  [[ "$?" != "0" ]] && echo "Update Neuvector Helm Repo failed" && exit 1

  # get specify chart version（複雜 pipe，輸出結果賦值回變數；不包 logged_run）
  Chart_Version=$(helm search repo neuvector/core --versions | grep "${Neuvector_Version}" | head -n 1 | fmt -u | cut -d " " -f 2)

  # pull
  logged_run "neuvector: helm pull core ${Chart_Version}" helm pull neuvector/core --version "${Chart_Version}"
  [[ "$?" != "0" ]] && echo "Pull Neuvector ${Neuvector_Version} Helm packages failed" && exit 1

  # create image list
  helm template core-*.tgz | awk '$1 ~ /image:/ {print $2}' | sed -e 's/\"//g' > images-list.txt 2>> "${Command_Output_log_file}"

  # get images
  neuvector_total=$(wc -l < images-list.txt)
  idx=0
  while IFS= read -r image || [[ -n "$image" ]]
  do
    idx=$((idx + 1))
    print_progress "neuvector" "$idx" "$neuvector_total" "$image"
    logged_run "neuvector [$idx/$neuvector_total] pull $image" $(cr_cmd) pull "$image"
    [[ "$?" != "0" ]] && { printf "\n" >/dev/tty 2>/dev/null; echo "Pull $image failed"; exit 1; }
  done < images-list.txt
  printf "\n" >/dev/tty 2>/dev/null || true

  # save images to tar.gz（pipe 用 bash -c + pipefail 包）
  neuvector_all_images=$(tr '\n' ' ' < images-list.txt)
  logged_run "neuvector: save images tar.gz" bash -c "set -o pipefail; $(cr_cmd) save $(cr_save_flags) ${neuvector_all_images} | gzip --stdout > neuvector-images-${Neuvector_Version}.tar.gz"
  [[ "$?" != "0" ]] && echo "${Container_Runtime} save Neuvector images ${Neuvector_Version} failed" && exit 1

  cd ../..
  logged_run "neuvector: tar airgap bundle" tar -czf compressed_files/neuvector-airgap-"${Neuvector_Version}".tar.gz neuvector/"${Neuvector_Version}"
  if [[ "$?" != "0" ]]; then
    echo "Preparing Neuvector Air Gap installer failed" && exit 1
  else
    echo "Prepare Neuvector ${Neuvector_Version} OK."
  fi
  log_section "prepare_neuvector END"
}

while [[ "$#" -gt "0" ]]
do
  option="$1"
  case $option in
    all)
      run_step create_working_directory
      run_step prepare_harbor
      run_step prepare_rke2
      run_step prepare_rancher
      run_step prepare_k3s
      run_step prepare_neuvector
      exit 0
    ;;
    harbor)
      run_step create_working_directory
      run_step prepare_harbor
      shift
    ;;
    rke2)
      run_step create_working_directory
      run_step prepare_rke2
      shift
    ;;
    rancher)
      run_step create_working_directory
      run_step prepare_rancher
      shift
    ;;
    k3s)
      run_step create_working_directory
      run_step prepare_k3s
      shift
    ;;
    neuvector)
      run_step create_working_directory
      run_step prepare_neuvector
      shift
    ;;
    *)
      usage
      exit 1
    ;;
  esac
done
