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
[cert-manager 11/11] quay.io/jetstack/cert-manager-ctl:v1.20.2
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
```

## Example:
  ### 一次準備全部五個產品（Harbor、RKE2、Rancher、K3S、Neuvector），並指定 Harbor 特定版本
  ```
  Harbor_Version=v2.15.0 ./podman-prepare.sh all
  ```
  ### 只準備 Rancher 的全離線安裝包，並且指定安裝 Rancher v2.13.4 版本
  ```
  Rancher_Version=v2.13.4 ./podman-prepare.sh rancher
  ```
  ### 準備 Neuvector 的全離線安裝包，並且指定安裝 Neuvector 5.5.0 版本
  ```
  Neuvector_Version=5.5.0 ./podman-prepare.sh neuvector
  ```

  ### 同時準備 Rancher、Harbor 和 K3S 的全離線安裝包，分別指定安裝 v2.13.4、v2.15.0 和 v1.35.3 版本，並設定私有 Image Registry 的名稱
  ```
  Rancher_Version=v2.13.4 Harbor_Version=v2.15.0 K3S_Version=v1.35.3 \
  Private_Registry_Name="antony-harbor.example.com" \
  ./podman-prepare.sh rancher harbor k3s
  ```

  ### 覆寫 RKE2 來源 URL 與 revision（從 Prime Artifacts 換回 GitHub releases）
  ```
  RKE2_Source_URL=https://github.com/rancher/rke2/releases/download \
  RKE2_Version=v1.35.3 RKE2_Revision=rke2r3 \
  ./podman-prepare.sh rke2
  ```

  ### 準備 K3S，顯式指定版本與 revision 後綴（未來若上游出 k3s2 可直接覆寫）
  ```
  K3S_Version=v1.35.3 K3S_Revision=k3s1 \
  ./podman-prepare.sh k3s
  ```

  ### 覆寫 K3S 來源 URL（從 Prime Artifacts 換回 GitHub releases）
  ```
  K3S_Source_URL=https://github.com/k3s-io/k3s/releases/download \
  K3S_Version=v1.35.3 K3S_Revision=k3s1 \
  ./podman-prepare.sh k3s
  ```

  ### 準備 Rancher，並顯式指定 cert-manager 版本
  ```
  Rancher_Version=v2.13.4 Cert_Manager_Version=v1.20.2 \
  ./podman-prepare.sh rancher
  ```

  ### 準備 Rancher，並指定特定 Helm 客戶端版本（會觸發 setup_env 的 Helm↔k8s n-3 相容性 pre-flight 檢查）
  ```
  Helm_Version=v3.20.2 Rancher_Version=v2.13.4 \
  ./podman-prepare.sh rancher
  ```

  ### 把 image retag 到 Harbor 的 `rancher-prime` project（而非預設的 `rancher`）
  ```
  Private_Registry_Name=harbor.example.com \
  Private_Registry_Namespace=rancher-prime \
  ./podman-prepare.sh rancher
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

## 離線端匯入 Rancher

以上 `prepare.sh`／`podman-prepare.sh` 是**連線端**（可連外網）準備 airgap 包的流程。離線端拿到 `rancher-airgap-<ver>.tar.gz` 後的還原流程由 `rancher-import.sh` 負責，它只做 **load + retag + push**：

```
┌─────────────────┐              ┌──────────────────────────┐
│  連線端（有網） │   transfer   │  離線端（air-gap）       │
│  prepare.sh     │ ───────────▶ │  rancher-import.sh       │
│  打包 tarball   │   by USB／   │  load + retag + push     │
│                 │   SCP／etc.  │  到內部 registry         │
└─────────────────┘              └──────────────────────────┘
```

### 職責邊界

| 步驟 | 誰做 |
|---|---|
| `tar -xzf rancher-airgap-<ver>.tar.gz` | **使用者手動**（想解到哪就解到哪） |
| 管理解壓後的 helm chart (`.tgz`)／`cert-manager.yaml`／helper scripts | **使用者手動**（保留供 `helm install`／`kubectl apply` 用） |
| `podman load -i <image-tar.gz>` | **`rancher-import.sh`** |
| 解析 loaded image 做 retag | **`rancher-import.sh`** |
| `podman login` ／ `podman push` | **`rancher-import.sh`** |

Script 只讀入 image tar.gz 做 registry 匯入，不碰使用者的解壓目錄結構。

### Usage

```
Usage:
  ENV_VAR=... rancher-import.sh <image-tar.gz> [<image-tar.gz> ...]

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
```

### 典型三步驟工作流

```bash
# Step 1: 使用者自行解壓（想解到哪就解到哪；這裡示範 ~/work/imported/）
mkdir -p ~/work/imported/rancher/v2.13.4
tar -xzf ~/work/compressed_files/rancher-airgap-v2.13.4.tar.gz \
  -C ~/work/imported/rancher/v2.13.4 --strip-components=2

# Step 2: Script 處理 image（shell glob 最簡潔）
Target_Registry_Name=harbor.customer.internal \
  ./rancher-import.sh ~/work/imported/rancher/v2.13.4/*-image.tar.gz

# Step 3: 使用者用保留下來的 helm chart／yaml 裝 cert-manager 與 Rancher
cd ~/work/imported/rancher/v2.13.4
kubectl apply -f cert-manager-crd.yaml
helm install cert-manager ./cert-manager-v1.20.2.tgz -n cert-manager --create-namespace
helm install rancher ./rancher-2.13.4.tgz -n cattle-system --create-namespace \
  --set hostname=rancher.example.com \
  --set rancherImage=harbor.customer.internal/rancher/rancher
```

### Import Examples

```bash
# 顯式指定多個檔案，並指定 Target_Registry_Namespace=rancher-prime
Target_Registry_Name=harbor.customer.internal \
Target_Registry_Namespace=rancher-prime \
./rancher-import.sh \
  ~/work/imported/rancher/v2.13.4/rancher-v2.13.4-image.tar.gz \
  ~/work/imported/rancher/v2.13.4/cert-manager-image-v1.20.2.tar.gz

# 非互動登入（CI pipeline）
Target_Registry_Name=harbor.customer.internal \
Registry_Username=admin Registry_Password='...' \
./rancher-import.sh /path/to/*-image.tar.gz

# 使用 docker 而非 podman
Container_Runtime=docker Target_Registry_Name=harbor.x.com \
./rancher-import.sh /path/to/*-image.tar.gz

# 已經 login 過，跳過 login 步驟
Skip_Login=1 Target_Registry_Name=harbor.x.com \
./rancher-import.sh /path/to/*-image.tar.gz
```

### Retag 邏輯

Script 從 image tag 自動解析 source：`<src_registry>/<src_namespace>/<rest...>`，若 `src_registry`／`src_namespace` 皆等於 `Target_Registry_Name`／`Target_Registry_Namespace` 則 **skip retag**；否則 retag 為 `${Target_Registry_Name}/${Target_Registry_Namespace}/${rest}`。範例：

| Loaded image | Target_Registry_Name / Namespace | 行為 |
|---|---|---|
| `harbor.example.com/rancher/rancher:v2.13.4` | `harbor.example.com` / `rancher` | **skip retag**（已對齊） |
| `harbor.example.com/rancher/rancher:v2.13.4` | `harbor.customer.internal` / `rancher` | retag → `harbor.customer.internal/rancher/rancher:v2.13.4` |
| `harbor.example.com/rancher/rancher:v2.13.4` | `harbor.example.com` / `rancher-prime` | retag → `harbor.example.com/rancher-prime/rancher:v2.13.4` |

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


