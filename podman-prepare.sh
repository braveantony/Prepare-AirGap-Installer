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

all        一次準備 Harbor、RKE2、Rancher 的全離線安裝包
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
     預設是 'v1.11.0'。

   - K3S_Version
     定義 K3S 的版本
     預設是 'v1.35.3'。

   - Neuvector_Version
     定義 Neuvector 的版本
     預設是 '5.5.0'。

   - Private_Registry_Name
     定義企業內部私有 Image Registry 的名稱
     預設是 'harbor.example.com'。

   - Command_log_file
     將執行的命令重新導向到 /tmp/prepare_message.log
     預設是 '/tmp/prepare_message.log'。

   - Command_Output_log_file
     將命令執行後的輸出重新導向到 /tmp/prepare_output_message.log
     預設是 '/tmp/prepare_output_message.log'。

Example:
  ## 一次準備 Harbor、RKE2、Rancher 的全離線安裝包，並且指定安裝 Harbor 特定版本
  \$ Harbor_Version=v2.7.0 ./podman-prepare.sh all

  ## 只準備 Rancher 的全離線安裝包，並且指定安裝 Rancher v2.7.9 版本
  \$ Rancher_Version=v2.7.9 ./podman-prepare.sh rancher

  ## 準備 Neuvector 的全離線安裝包，並且指定安裝 Neuvector 5.2.0 版本
  \$ Neuvector_Version=5.2.0 ./podman-prepare.sh neuvector

  ## 同時準備 Rancher、Harbor 和 K3S 的全離線安裝包，分別指定安裝 v2.7.9、v2.7.0 和 v1.25.9 版本，並設定私有 Image Registry 的名稱
  \$ Rancher_Version=v2.7.9 Harbor_Version=v2.7.0 K3S_Version=v1.25.9 \\
  Private_Registry_Name="antony-harbor.example.com" \\
  ./podman-prepare.sh rancher harbor k3s
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

  # check Command is installed
  for command in wget curl podman
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
    Cert_Manager_Version="v1.11.0"
  fi

  # make sure the version of the K3S is defined
  if [[ -z "${K3S_Version}" ]]; then
    K3S_Version="v1.35.3"
  fi

  # make sure the version of the Neuvector is defined
  if [[ -z "${Neuvector_Version}" ]]; then
    Neuvector_Version="5.5.0"
  fi

  # make sure the name of the Private Images Registry is defined
  if [[ -z "${Private_Registry_Name}" ]]; then
    Private_Registry_Name="harbor.example.com"
  fi
}

# 印進度列到終端（同一行覆寫），非 TTY 時靜默
print_progress() {
  printf "\r\033[K[%s %d/%d] %s" "$1" "$2" "$3" "$4" >/dev/tty 2>/dev/null || true
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

  # 下載 Harbor 壓縮檔
  logged_run "harbor: download offline-installer tgz" wget https://github.com/goharbor/harbor/releases/download/"${Harbor_Version}"/harbor-offline-installer-"${Harbor_Version}".tgz
  [[ "$?" != "0" ]] && echo "Download harbor-offline-installer-"${Harbor_Version}".tgz failed" && exit 1

  # 下載 Docker Compose 套件
  logged_run "harbor: download docker-compose" wget https://github.com/docker/compose/releases/download/"${Docker_Compose_Version}"/docker-compose-linux-x86_64
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

  # 安裝 helm
  logged_run "rancher: install helm" bash -c 'curl -s https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
  [[ "$?" != "0" ]] && echo "Install helm failed" && exit 1

  # 新增並刷新 Rancher Prime 的 Helm Chart Repository
  logged_run "rancher: helm repo add rancher-prime" helm repo add rancher-prime https://charts.rancher.com/server-charts/prime
  [[ "$?" != "0" ]] && echo "helm repo add rancher-prime failed" && exit 1
  logged_run "rancher: helm repo update (rancher-prime)" helm repo update
  [[ "$?" != "0" ]] && echo "helm repo update (rancher-prime) failed" && exit 1

  # 下載 Rancher chart
  logged_run "rancher: helm fetch rancher chart" helm fetch rancher-prime/rancher --version="${Rancher_Version}"
  [[ "$?" != "0" ]] && echo "helm fetch rancher failed" && exit 1

  # 新增和刷新 cert-manager repo
  logged_run "rancher: helm repo add jetstack" helm repo add jetstack https://charts.jetstack.io
  [[ "$?" != "0" ]] && echo "helm repo add jetstack failed" && exit 1
  logged_run "rancher: helm repo update (jetstack)" helm repo update
  [[ "$?" != "0" ]] && echo "helm repo update (jetstack) failed" && exit 1

  # 下載 cert-manager chart
  logged_run "rancher: helm fetch cert-manager chart" helm fetch jetstack/cert-manager --version "${Cert_Manager_Version}"
  [[ "$?" != "0" ]] && echo "helm fetch Cert_Manager failed" && exit 1

  # 下載 cert-manager 要求的 CRD
  logged_run "rancher: download cert-manager CRD" curl -L -o cert-manager-crd.yaml https://github.com/cert-manager/cert-manager/releases/download/"${Cert_Manager_Version}"/cert-manager.crds.yaml
  [[ "$?" != "0" ]] && echo "Download Cert_Manager CRD failed" && exit 1

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
    logged_run "cert-manager [$idx/$cert_manager_total] pull $image" podman pull "$image"
    [[ "$?" != "0" ]] && { printf "\n" >/dev/tty 2>/dev/null; echo "Pull quay.io/jetstack/$image Container images failed"; exit 1; }

    # 修改 cert-manager 的所有 Container Images Tag
    logged_run "cert-manager [$idx/$cert_manager_total] tag $image" podman tag "${image}" "${Private_Registry_Name}"/rancher/"${image##*/}"
    [[ "$?" != "0" ]] && { printf "\n" >/dev/tty 2>/dev/null; echo "tag ${Private_Registry_Name}/rancher/${image##*/} Container images failed"; exit 1; }
  done
  printf "\n" >/dev/tty 2>/dev/null || true

  # 將 cert-manager 的所有 Container Images 打包成 .tar.gz 壓縮檔
  # 復用前面計算好的 $cert_manager_images，避免重新跑一次 helm template
  # pipe 用 bash -c 包，set -o pipefail 讓 save 或 gzip 任一段失敗都能正確回傳
  cert_manager_renamed_images=$(echo "$cert_manager_images" | sed "s|quay.io/jetstack|${Private_Registry_Name}/rancher|g" | tr '\n' ' ')
  logged_run "cert-manager: save images tar.gz" bash -c "set -o pipefail; podman save -m ${cert_manager_renamed_images} | gzip --stdout > cert-manager-image-${Cert_Manager_Version}.tar.gz"
  [[ "$?" != "0" ]] && echo "Podman save Cert-manager ${Cert_Manager_Version} images failed" && exit 1

  # 下載 Helm 壓縮檔
  logged_run "rancher: download helm ${Helm_Version} tarball" wget -q https://get.helm.sh/helm-"${Helm_Version}"-linux-amd64.tar.gz -O helm-"${Helm_Version}"-linux-amd64.tar.gz
  [[ "$?" != "0" ]] && echo "Download helm ${Helm_Version} failed"

  # 下載 Rancher Images List 文字檔及蒐集 Image 所需的 Shell Script
  for x in rancher-images.txt rancher-load-images.sh rancher-save-images.sh
  do
    logged_run "rancher: download $x" wget -q "${Rancher_Source_URL}"/rancher/"${Rancher_Version}"/"${x}"
    [[ "$?" != "0" ]] && echo "Download ${x} failed" && exit 1
  done

  # 對 Image List 進行排序和唯一化，以消除來源之間的任何重疊
  logged_run "rancher: sort-uniq rancher-images.txt" sort -u rancher-images.txt -o rancher-images.txt

  [[ "$?" == "0" ]] && echo "Start pulling and saving rancher ${Rancher_Version} images in the background..."
  # 下載離線安裝 Rancher 所需的所有 Container Images 並打包成 rancher-images.tar.gz
  rancher_total=$(wc -l < rancher-images.txt)
  idx=0
  while read image
  do
    idx=$((idx + 1))
    print_progress "rancher" "$idx" "$rancher_total" "$image"
    if ! logged_run "rancher [$idx/$rancher_total] pull $image" podman pull registry.rancher.com/"${image}"; then
      printf "\n" >/dev/tty 2>/dev/null || true
      echo pull "$image" failed && exit 1
    fi
  done <<< $(cat rancher-images.txt)
  printf "\n" >/dev/tty 2>/dev/null || true

  rancher_all_image=$(cat rancher-images.txt | sed 's|^|registry.rancher.com/|' | tr '\n' ' ')
  for n in $rancher_all_image
  do
    if ! podman images "$n" | grep -q "${n%:*}"; then
      if ! logged_run "rancher retry pull $n" podman pull registry.rancher.com/"$n"; then
        echo pull "$n" failed twice && exit 1
      fi
    else
      logged_run "rancher retry tag $n" podman tag "${n}" "${Private_Registry_Name}"/rancher/"${n##*/}"
      [[ "$?" != "0" ]] && echo "tag ${Private_Registry_Name}/rancher/${n##*/} Container images failed" && exit 1
    fi
  done

  # save 為 pipe，用 bash -c + pipefail 包進 logged_run
  rename_rancher_all_image=$(cat rancher-images.txt | sed "s|^|${Private_Registry_Name}/|" | tr '\n' ' ')
  logged_run "rancher: save images tar.gz" bash -c "set -o pipefail; podman save -m ${rename_rancher_all_image} | gzip --stdout > rancher-${Rancher_Version}-image.tar.gz"
  [[ (( $(stat -c%s rancher-"${Rancher_Version}"-image.tar.gz) -lt 50000000 )) ]] && echo "Podman Save rancher ${Rancher_Version} images failed" && exit 1

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

  logged_run "k3s: download k3s-airgap-images-amd64.tar" curl -# -OL https://github.com/k3s-io/k3s/releases/download/"${K3S_Version}"%2Bk3s1/k3s-airgap-images-amd64.tar
  [[ "$?" != "0" ]] && echo "Download k3s-airgap-images-amd64.tar ${K3S_Version} failed" && exit 1

  logged_run "k3s: download k3s binary" curl -# -OL https://github.com/k3s-io/k3s/releases/download/"${K3S_Version}"%2Bk3s1/k3s
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

  # install helm
  logged_run "neuvector: install helm" bash -c 'curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash'
  [[ "$?" != "0" ]] && echo "Install helm failed" && exit 1

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
  for image in $(cat images-list.txt)
  do
    idx=$((idx + 1))
    print_progress "neuvector" "$idx" "$neuvector_total" "$image"
    logged_run "neuvector [$idx/$neuvector_total] pull $image" podman pull "$image"
    [[ "$?" != "0" ]] && { printf "\n" >/dev/tty 2>/dev/null; echo "Pull $image failed"; exit 1; }
  done
  printf "\n" >/dev/tty 2>/dev/null || true

  # save images to tar.gz（pipe 用 bash -c + pipefail 包）
  neuvector_all_images=$(tr '\n' ' ' < images-list.txt)
  logged_run "neuvector: save images tar.gz" bash -c "set -o pipefail; podman save -m ${neuvector_all_images} | gzip --stdout > neuvector-images-${Neuvector_Version}.tar.gz"
  [[ "$?" != "0" ]] && echo "Podman save Neuvector images ${Neuvector_Version} failed" && exit 1

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
