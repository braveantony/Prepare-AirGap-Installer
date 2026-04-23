# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 回覆語言規範（必要）

在本專案中，所有對使用者的回覆都必須使用**繁體中文**。唯一例外是**專有名詞**，包含但不限於：
- 產品／工具名稱（Harbor、RKE2、Rancher、Neuvector、K3S、Helm、cert-manager、Docker、Podman、Kubernetes 等）
- 指令、旗標、環境變數、檔案／路徑名稱（例如 `prepare.sh`、`${Harbor_Version}`、`~/work/`）
- 程式碼片段、錯誤訊息、API 名稱、程式語言關鍵字

所有說明性文字、敘述、提問與摘要一律使用繁體中文（不得使用簡體中文或英文）。

## GitOps 原則（所有變更都必須遵守）

本專案視 Git 為**唯一真實來源**（single source of truth）。任何對檔案或腳本的修改都必須符合以下原則，否則請拒絕或先與使用者確認：

1. **所有變更走 Git。** 不在本機或 `~/work/` 下做「暫時的」手動修改；要改 `prepare.sh`／`README.md`／`CLAUDE.md` 或任何設定，都透過檔案編輯 → `git commit` → （必要時）`git push` 的流程。拒絕產生不進版控的「補丁輸出」。
2. **宣告式、可重現。** 給定相同的環境變數（版本、`Private_Registry_Name` 等）與相同的 commit，執行結果的產物（`~/work/compressed_files/*.tar.gz` 的內容）應該可以重現。因此：
   - **版本必須 pin 成具體值**，不得引入 `latest`、floating tag、或「最新 release」這類動態解析。
   - 新增外部資源時，URL 必須是可版本化的 release 連結，不得指向會變動的分支／HEAD。
3. **預設值兩處同步。** 修改某個預設版本時，`setup_env` 內與 `usage` heredoc 內共兩處必須一起改，並在同一個 commit 落地（見下方「架構」一節）。
4. **冪等。** 腳本執行可安全重跑；編輯腳本時請維持這個性質（目錄用 `mkdir -p`、下載允許覆寫既有檔案等）。不要引入「只能跑一次」或會污染使用者既有狀態的步驟。
5. **Commit 訊息描述 why，而不只是 what。** 版本升級要註明上游 release，行為改動要註明動機，方便日後從 `git log` 重建決策脈絡。
6. **不要提交產出物（artifact）與 log。** `~/work/`、`/tmp/prepare_*.log`、任何 `*.tar.gz` 都是執行產物，不屬於 Git 倉庫。
7. **不要修改 git 設定、不要 force push、不要 `--no-verify`。** 如有衝突，先跟使用者確認再處理。

以上原則對「文件更新」同樣適用——`README.md` 與 `CLAUDE.md` 的修改也必須透過 commit 落地，並在訊息中說明原因。

## 專案目的

本專案包含兩類腳本：

1. **連線端打包**（`prepare.sh`）：單支 Bash 腳本，透過 `Container_Runtime` env var 切換 docker／podman runtime；用於打包 Harbor、RKE2、Rancher（Prime）、K3S 與 Neuvector 的全離線（air-gap）安裝包。每次執行會下載該產品的 release 檔案，並把所需的 container images 全部拉下來，最後用 tar + gzip 壓縮成 `~/work/compressed_files/<product>-airgap-<version>.tar.gz`。

2. **離線端匯入**（`rancher-import.sh`）：在無法對外連網的環境中，把準備好的 Rancher image tar.gz `podman load` 進本地 runtime、retag、再 push 到內部 registry。**只**處理 image 的 load + retag + push，解壓 airgap tarball 與 helm chart／YAML 的後續使用由使用者自理。

## 執行方式

```bash
# 連線端（需要可連外網）
./prepare.sh                              <target>...   # 預設 auto-detect（podman 優先，fallback docker）
Container_Runtime=docker ./prepare.sh     <target>...   # 顯式 docker（需可免密碼 sudo）

# 離線端（只做 rancher）
./rancher-import.sh <image-tar.gz> [<image-tar.gz> ...]
```

可用的 target：`all` | `harbor` | `rke2` | `rancher` | `neuvector` | `k3s`。不帶參數時會印出 usage。

版本可透過 `README.md` 列出的環境變數覆寫（`Harbor_Version`、`RKE2_Version`、`Rancher_Version`、`K3S_Version`、`Neuvector_Version`、`Helm_Version`、`Cert_Manager_Version`、`Docker_Compose_Version`、`Private_Registry_Name`）。本專案沒有 build／lint／test 工具鏈，單純就是 shell 腳本，沒有對應的測試 harness。

Log：每一條執行的指令都會透過 `BASH_XTRACEFD` + `set -x` 寫進 `/tmp/prepare_message.log`；下載／pull 的 stdout/stderr 則寫進 `/tmp/prepare_output_message.log`。這兩個檔案會在每次執行開頭被刪除。

## 架構

**單一 prepare.sh，Container_Runtime 分派。** 唯一 runtime 差異（docker 需要 `sudo` prefix、`podman save` 需要 `-m` flag）由 `cr_cmd`／`cr_save_flags` 兩個 helper 封裝。新增 container 相關邏輯只需改一支腳本；未設 `Container_Runtime` 時由 `setup_env` auto-detect（podman 優先，fallback docker），與 `rancher-import.sh` 同 pattern。

**每個 target 的處理流程。** 每個 `prepare_<product>()` 函式會：
1. 呼叫 `setup_env`（檢查網路、用 `nc`/`which` 檢查工具、為缺少的版本變數填入預設值）。
2. `cd ~/work/<product>/<version>`（目錄由 `create_working_directory` 建立）。
3. 用 `wget`／`curl` 從上游下載 release 資產（GitHub releases、`get.helm.sh`、`get.rke2.io`、`get.k3s.io`，以及 rancher／jetstack／neuvector 的 Helm repo）。
4. 對於以 Helm chart 形式發佈的產品（rancher、cert-manager、neuvector）：先 `helm template` 渲染 chart，用 grep 抓出 `image:` 行，逐一 pull，再 retag 為 `${Private_Registry_Name}/rancher/...`，最後以 `docker/podman save | gzip` 打包成單一的 `*.tar.gz`。
5. `tar -czf ~/work/compressed_files/<product>-airgap-<version>.tar.gz <product>/<version>`。

**Dispatch。** 檔案尾端的 `while`／`case` 迴圈把每個位置參數導向 `create_working_directory` + `prepare_<x>`，所有呼叫都透過 `run_step` helper：它把 stdout/stderr tee 到 `Command_Output_log_file`，並用 `PIPESTATUS[0]` 取 pipeline 第一段的 exit code，確保 function 內 `exit N` 能正確終止整支腳本（避免 pipeline subshell 吞掉 exit code）。`all` 會依序跑所有五個產品（harbor → rke2 → rancher → k3s → neuvector）後 `exit 0`，**不會**再回到 dispatch loop 處理同一行其餘參數。

**setup_env 的預設值。** 預設版本同時寫在 `setup_env` 內，也重複寫在 `usage` 的 heredoc 裡。想改某個預設版本，`setup_env` 一處 + `usage` heredoc 一處，共要改**兩個地方**。

### `rancher-import.sh`（離線端匯入，單獨一支）

與 `prepare.sh` 解耦，目的是**離線端可以單獨分發**，不需要一起搬整個 repo。職責刻意切窄：

- **只處理 image**：位置參數吃 `*-image.tar.gz`（可一到多個，支援 shell glob），對每個 tarball 做 `podman/docker load`、把 `Loaded image: <ref>` 解析出來、retag、push。
- **不碰使用者檔案**：不解壓 `rancher-airgap-<ver>.tar.gz`、不搬移 helm chart／YAML、不清理輸入檔。使用者要自己 `tar -xzf` 解壓並管理解壓後的 config 檔（後續 `helm install rancher`／`kubectl apply -f cert-manager.yaml` 會用到）。
- **Runtime 泛用**：`Container_Runtime` env var 切 podman／docker（預設 podman）；不像 prepare 端為兩種 runtime 各寫一支。
- **Retag 自動化**：從 image tag 解析 `<src_registry>/<src_namespace>/<rest...>`，若 `src_registry`／`src_namespace` 已對齊 `Target_Registry_Name`／`Target_Registry_Namespace` 則 skip，否則 retag 為 `${Target_Registry_Name}/${Target_Registry_Namespace}/${rest}`。
- **Helper 重複（刻意）**：複製了 `print_progress`／`log_section`／`logged_run` 的實作約 60 行。不抽 common library 是為了 script 可單獨 scp 到離線機器執行。未來若 harbor／rke2／k3s／neuvector 也要做 import 端，屆時再評估是否抽 library。
- **Log 檔分開**：`/tmp/import_message.log`（xtrace）與 `/tmp/import_output_message.log`（合併結構化），與 prepare 端的 `/tmp/prepare_*.log` 分離避免混淆。
- **password-stdin**：若給 `Registry_Username` + `Registry_Password`，login 前後會暫關 `set +x`／再開 `set -x`，避免密碼進 xtrace log。

## 已知的粗糙之處（不要無腦「修」）

- `prepare_*` 函式內部仍有若干 `[[ "$?" != "0" ]] && echo ... && exit 1` 寫在一條 pipeline 的**下一行**——`$?` 只反映 pipeline 最後一個指令的狀態（例：`... | gzip > file.tar.gz` 成功但前段 `helm template` 或 `docker save` 失敗會被吞）。dispatch 層已透過 `run_step` + `PIPESTATUS[0]` 守住；內部這些檢查除非使用者明確要求強化，否則保留。
- 程式碼註解與使用者面向的訊息都是繁體中文，編修時請沿用這個慣例。
