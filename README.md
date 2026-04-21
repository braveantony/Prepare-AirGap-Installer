# 自動化準備全離線安裝包

## 描述

可自動化準備指定的產品及對應的版本，包含 Harbor、Rancher Kubernetes Engine 2 ( RKE2 )、Rancher、Neuvector 和 K3S 全離線安裝所需的檔案和 Container Images。
全離線安裝所需的檔案和 Container Images 會被壓縮成一個壓縮檔，並儲存在 `~/work/compressed_files` 目錄底下。

Rancher 生態系的 artifact（RKE2／Rancher／K3S）預設從 **Rancher Prime Artifacts**（`https://prime.ribs.rancher.io`）取得，可透過對應的 `*_Source_URL` 環境變數覆寫來源。

## PreRequirements

### prepare.sh
- Packages:
  - curl
  - wget
  - nc (netcat，連線檢查用)
  - docker
  - sudo (without password)

### podman-prepare.sh
- Packages:
  - curl
  - wget
  - nc (netcat，連線檢查用)
  - podman (rootless)
  - sudo (without password)

## Quick Start

### Download Git Repo

```
git clone https://github.com/braveantony/Prepare-AirGap-Installer.git && \
cd Prepare-AirGap-Installer/ && \
chmod +x *.sh
```

### 開始執行

`all` 會依序準備五個產品（harbor → rke2 → rancher → k3s → neuvector）：

```
./podman-prepare.sh all
```

螢幕輸出範例（image pull 過程會在**同一行**即時更新進度列，最終留下各產品完成訊息）：

```
[cert-manager 11/11] quay.io/jetstack/cert-manager-ctl:v1.11.0
[rancher 127/127] rancher/mirrored-coredns-coredns:1.12.0
[neuvector 8/8] neuvector/scanner:latest
Prepare Harbor v2.15.0 OK.
Prepare RKE2 v1.35.3 OK.
Prepare Rancher v2.13.4 OK.
Prepare K3S v1.35.3 OK.
Prepare Neuvector 5.5.0 OK.
```

檢查全離線安裝包

```
$ ls -lh ~/work/compressed_files/
total 2.5G
-rw-r--r-- 1 bigred bigred 661M Apr 21 13:35 harbor-offline-v2.15.0.tar.gz
-rw-r--r-- 1 bigred bigred 192M Apr 21 13:40 k3s-airgap-v1.35.3.tar.gz
-rw-r--r-- 1 bigred bigred  91M Apr 21 13:45 neuvector-airgap-5.5.0.tar.gz
-rw-r--r-- 1 bigred bigred 705M Apr 21 13:50 rancher-airgap-v2.13.4.tar.gz
-rw-r--r-- 1 bigred bigred 956M Apr 21 13:55 rke2-airgap-v1.35.3.tar.gz
```

> 每次執行 `prepare_<product>` 會先 `rm -f ~/work/compressed_files/<product>-*.tar.gz`，同產品舊版本 tarball 會被覆蓋；不同產品互不影響。


## Usage

```
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
     預設是 'v1.11.0'。

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

   - Command_log_file
     將執行的命令重新導向到 /tmp/prepare_message.log
     預設是 '/tmp/prepare_message.log'。

   - Command_Output_log_file
     將命令執行後的輸出重新導向到 /tmp/prepare_output_message.log
     預設是 '/tmp/prepare_output_message.log'。
```

## Example:
  ### 一次準備全部五個產品（Harbor、RKE2、Rancher、K3S、Neuvector），並指定 Harbor 特定版本
  ```
  Harbor_Version=v2.7.0 ./podman-prepare.sh all
  ```
  ### 只準備 Rancher 的全離線安裝包，並且指定安裝 Rancher v2.7.9 版本
  ```
  Rancher_Version=v2.7.9 ./podman-prepare.sh rancher
  ```
  ### 準備 Neuvector 的全離線安裝包，並且指定安裝 Neuvector 5.2.0 版本
  ```
  Neuvector_Version=5.2.0 ./podman-prepare.sh neuvector
  ```

  ### 同時準備 Rancher、Harbor 和 K3S 的全離線安裝包，分別指定安裝 v2.7.9、v2.7.0 和 v1.25.9 版本，並設定私有 Image Registry 的名稱
  ```
  Rancher_Version=v2.7.9 Harbor_Version=v2.7.0 K3S_Version=v1.25.9 \
  Private_Registry_Name="antony-harbor.example.com" \
  ./podman-prepare.sh rancher harbor k3s
  ```

  ### 覆寫 RKE2 來源 URL 與 revision（從 Prime Artifacts 換回 GitHub releases）
  ```
  RKE2_Source_URL=https://github.com/rancher/rke2/releases/download \
  RKE2_Version=v1.27.11 RKE2_Revision=rke2r1 \
  ./podman-prepare.sh rke2
  ```

## 範例目錄結構
```
~/work/
├── compressed_files
│   ├── harbor-offline-v2.15.0.tar.gz   --> Harbor v2.15.0 版本的全離線安裝包
│   ├── k3s-airgap-v1.35.3.tar.gz      --> K3S v1.35.3 版本的全離線安裝包
│   ├── neuvector-airgap-5.5.0.tar.gz   --> Neuvector 5.5.0 版本的全離線安裝包
│   └── rancher-airgap-v2.13.4.tar.gz    --> Rancher v2.13.4 版本的全離線安裝包
│   └── rke2-airgap-v1.35.3.tar.gz     --> RKE2 v1.35.3 版本的全離線安裝包
├── harbor
│   ├── v2.15.0
├── k3s
│   └── v1.35.3
├── neuvector
│   └── 5.5.0
├── rancher
│   └── v2.13.4
└── rke2
    └── v1.35.3
```

## Log

執行期間兩個 log 檔分工：

### `/tmp/prepare_message.log`（xtrace，細節 debug 用）

由 `set -x` + `BASH_XTRACEFD` 產出，每行帶時間戳與來源行號格式：
```
+ [13:07:27] podman-prepare.sh:248: logged_run 'harbor: download offline-installer tgz' wget -nv -O harbor-offline-installer-v2.15.0.tgz https://...
```

### `/tmp/prepare_output_message.log`（合併結構化 log，日常看這個）

每個外部命令（`wget`／`curl`／`helm`／`podman/docker pull|tag|save`／`tar`…）都由 `logged_run` 包裝，寫成 `=== [TS] <label> ===` → `CMD: ...` → raw output → `=== [TS] EXIT: <rc> ===` 的區塊；每個 `prepare_<product>` 函式的首尾另有 `############` 醒目分隔符標記 START／END：

```
############################################################
# [2026-04-21 13:07:27] prepare_harbor START (Harbor_Version=v2.15.0)
############################################################

=== [2026-04-21 13:07:27] harbor: download offline-installer tgz ===
CMD: wget -nv -O harbor-offline-installer-v2.15.0.tgz https://github.com/goharbor/harbor/releases/download/v2.15.0/...
2026-04-21 13:08:10 URL:https://release-assets.githubusercontent.com/... [671556546/671556546] -> "harbor-offline-installer-v2.15.0.tgz" [1]
=== [2026-04-21 13:08:10] EXIT: 0 ===

...

############################################################
# [2026-04-21 13:08:29] prepare_harbor END
############################################################
```

進度列（例：`[rancher 42/127] <image>`）只印在終端（`/dev/tty`），**不**污染 log 檔。

兩個檔案在每次執行開頭都會被刪除重建。

```
# 追蹤執行期間的結構化 log
$ tail -f /tmp/prepare_output_message.log

# 除錯用 xtrace
$ tail -f /tmp/prepare_message.log
```

## Helm 與 Kubernetes 版本相容性

`setup_env` 會在執行任何 `prepare_*` 前做 pre-flight 檢查：若 `${Helm_Version}` compiled-against 的 Kubernetes 版本與 `${RKE2_Version}`／`${K3S_Version}` 不在 Helm 官方的 **n-3 support window** 內，會 exit 並印明確提示（該升哪個、該降哪個）。參見 <https://helm.sh/docs/topics/version_skew/>。

規律（v3.x 系列）：Helm `3.N` 對應 Kubernetes `1.(N+15)`。
- 預設 `Helm_Version=v3.20.2` → k8s 1.35 → 支援 1.32–1.35，預設 `v1.35.3` RKE2／K3S 相容。


