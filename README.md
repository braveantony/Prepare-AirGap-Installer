# 自動化準備全離線安裝包

## 描述

可自動化準備指定的產品及對應的版本，包含 Harbor、Rancher Kubernetes Engine 2 ( RKE2 )、Rancher、Neuvector 和 K3S 全離線安裝所需的檔案和 Container Images。
全離線安裝所需的檔案和 Container Images 會被壓縮成一個壓縮檔，並儲存在 `~/work/compressed_files` 目錄底下。

## PreRequirements

### prepare.sh
- Packages:
  - curl
  - wget
  - docker
  - sudo (without password)

### podman-prepare.sh
- Packages:
  - curl
  - wget
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

```
./podman-prepare.sh harbor rke2 k3s neuvector
```

螢幕輸出 : 

```
Prepare Harbor v2.15.0 OK.
Prepare RKE2 v1.35.3 OK.
Prepare K3S v1.35.3 OK.
Prepare Neuvector 5.5.0 OK.
```

檢查全離線安裝包

```
$ ls -lh ~/work/compressed_files/
total 1.9G
-rw-r--r-- 1 bigred bigred 630M Mar 15 15:15 harbor-offline-v2.15.0.tar.gz
-rw-r--r-- 1 bigred bigred 192M Mar 15 15:17 k3s-airgap-v1.35.3.tar.gz
-rw-r--r-- 1 bigred bigred  91M Mar 15 15:18 neuvector-airgap-5.5.0.tar.gz
-rw-r--r-- 1 bigred bigred 956M Mar 15 15:17 rke2-airgap-v1.35.3.tar.gz
```


## Usage

```
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
```

## Example:
  ### 一次準備 Harbor、RKE2、Rancher 的全離線安裝包，並且指定安裝 Harbor 特定版本
  ```
  Harbor_Version=v2.7.0 ./podman-prepare.sh all
  ```
  ### 只準備 Rancher 的全離線安裝包，並且指定安裝 Rancher v2.7.9 版本
  ```
  Rancher_Version=v2.7.9 ./podman-prepare.sh rancher
  ```
  ### 準備 Neuvector 的全離線安裝包，並且指定安裝 Neuvector 5.2.0 版本
  ```
  Neuvector_Version=5.2.0 ../podman-prepare.sh neuvector
  ```

  ### 同時準備 Rancher、Harbor 和 K3S 的全離線安裝包，分別指定安裝 v2.7.9、v2.7.0 和 v1.25.9 版本，並設定私有 Image Registry 的名稱
  ```
  Rancher_Version=v2.7.9 Harbor_Version=v2.7.0 K3S_Version=v1.25.9 \
  Private_Registry_Name="antony-harbor.example.com" \
  ./podman-prepare.sh rancher harbor k3s
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
### 檢視程式執行了哪些命令

```
$ tail -f /tmp/prepare_message.log
```

### 檢視程式執行命令的執行結果

```
$ tail -f /tmp/prepare_output_message.log
```


