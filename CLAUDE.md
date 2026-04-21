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

1. **所有變更走 Git。** 不在本機或 `~/work/` 下做「暫時的」手動修改；要改 `prepare.sh`／`podman-prepare.sh`／`README.md`／`CLAUDE.md` 或任何設定，都透過檔案編輯 → `git commit` → （必要時）`git push` 的流程。拒絕產生不進版控的「補丁輸出」。
2. **宣告式、可重現。** 給定相同的環境變數（版本、`Private_Registry_Name` 等）與相同的 commit，執行結果的產物（`~/work/compressed_files/*.tar.gz` 的內容）應該可以重現。因此：
   - **版本必須 pin 成具體值**，不得引入 `latest`、floating tag、或「最新 release」這類動態解析。
   - 新增外部資源時，URL 必須是可版本化的 release 連結，不得指向會變動的分支／HEAD。
3. **兩支腳本同步在同一 commit。** `prepare.sh` 與 `podman-prepare.sh` 是平行孿生腳本；任一行為修改都必須在**同一個 commit**內同時更新兩支，避免 drift。若只改其中一支，視為違反 GitOps 原則，需要明確理由並寫在 commit message 中。
4. **預設值四處同步。** 修改某個預設版本時，兩支腳本的 `setup_env` 內與 `usage` heredoc 內共四處必須一起改，並在同一個 commit 落地（見下方「架構」一節）。
5. **冪等。** 腳本執行可安全重跑；編輯腳本時請維持這個性質（目錄用 `mkdir -p`、下載允許覆寫既有檔案等）。不要引入「只能跑一次」或會污染使用者既有狀態的步驟。
6. **Commit 訊息描述 why，而不只是 what。** 版本升級要註明上游 release，行為改動要註明動機，方便日後從 `git log` 重建決策脈絡。
7. **不要提交產出物（artifact）與 log。** `~/work/`、`/tmp/prepare_*.log`、任何 `*.tar.gz` 都是執行產物，不屬於 Git 倉庫。
8. **不要修改 git 設定、不要 force push、不要 `--no-verify`。** 如有衝突，先跟使用者確認再處理。

以上原則對「文件更新」同樣適用——`README.md` 與 `CLAUDE.md` 的修改也必須透過 commit 落地，並在訊息中說明原因。

## 專案目的

本專案包含兩支幾乎完全相同的 Bash 腳本，用於打包 Harbor、RKE2、Rancher（Prime）、K3S 與 Neuvector 的全離線（air-gap）安裝包。每次執行會下載該產品的 release 檔案，並把所需的 container images 全部拉下來，最後用 tar + gzip 壓縮成 `~/work/compressed_files/<product>-airgap-<version>.tar.gz`。

## 執行方式

```bash
./prepare.sh        <target>...   # 使用 docker（需可免密碼 sudo）
./podman-prepare.sh <target>...   # 使用 rootless podman
```

可用的 target：`all` | `harbor` | `rke2` | `rancher` | `neuvector` | `k3s`。不帶參數時會印出 usage。

版本可透過 `README.md` 列出的環境變數覆寫（`Harbor_Version`、`RKE2_Version`、`Rancher_Version`、`K3S_Version`、`Neuvector_Version`、`Helm_Version`、`Cert_Manager_Version`、`Docker_Compose_Version`、`Private_Registry_Name`）。本專案沒有 build／lint／test 工具鏈，單純就是 shell 腳本，沒有對應的測試 harness。

Log：每一條執行的指令都會透過 `BASH_XTRACEFD` + `set -x` 寫進 `/tmp/prepare_message.log`；下載／pull 的 stdout/stderr 則寫進 `/tmp/prepare_output_message.log`。這兩個檔案會在每次執行開頭被刪除。

## 架構

**兩支腳本、一套邏輯。** `prepare.sh` 與 `podman-prepare.sh` 幾乎逐行對應——差異只在 container runtime（`sudo docker` vs rootless `podman`，以及 `podman save -m` 用於多 image save）。**任何行為上的修改，通常都必須在兩支腳本裡都改一次。** 除非某個改動本質上只跟單一 runtime 有關，否則請同步維護。

**每個 target 的處理流程。** 每個 `prepare_<product>()` 函式會：
1. 呼叫 `setup_env`（檢查網路、用 `nc`/`which` 檢查工具、為缺少的版本變數填入預設值）。
2. `cd ~/work/<product>/<version>`（目錄由 `create_working_directory` 建立）。
3. 用 `wget`／`curl` 從上游下載 release 資產（GitHub releases、`get.helm.sh`、`get.rke2.io`、`get.k3s.io`，以及 rancher／jetstack／neuvector 的 Helm repo）。
4. 對於以 Helm chart 形式發佈的產品（rancher、cert-manager、neuvector）：先 `helm template` 渲染 chart，用 grep 抓出 `image:` 行，逐一 pull，再 retag 為 `${Private_Registry_Name}/rancher/...`，最後以 `docker/podman save | gzip` 打包成單一的 `*.tar.gz`。
5. `tar -czf ~/work/compressed_files/<product>-airgap-<version>.tar.gz <product>/<version>`。

**Dispatch。** 檔案尾端的 `while`／`case` 迴圈把每個位置參數導向 `create_working_directory` + `prepare_<x>`，所有呼叫都透過 `run_step` helper：它把 stdout/stderr tee 到 `Command_Output_log_file`，並用 `PIPESTATUS[0]` 取 pipeline 第一段的 exit code，確保 function 內 `exit N` 能正確終止整支腳本（避免 pipeline subshell 吞掉 exit code）。`all` 會依序跑所有五個產品（harbor → rke2 → rancher → k3s → neuvector）後 `exit 0`，**不會**再回到 dispatch loop 處理同一行其餘參數。

**setup_env 的預設值。** 預設版本同時寫在 `setup_env` 內，也重複寫在 `usage` 的 heredoc 裡。想改某個預設版本，代表兩支腳本、各兩處，總共要改**四個地方**。

## 已知的粗糙之處（不要無腦「修」）

- `prepare_*` 函式內部仍有若干 `[[ "$?" != "0" ]] && echo ... && exit 1` 寫在一條 pipeline 的**下一行**——`$?` 只反映 pipeline 最後一個指令的狀態（例：`... | gzip > file.tar.gz` 成功但前段 `helm template` 或 `docker save` 失敗會被吞）。dispatch 層已透過 `run_step` + `PIPESTATUS[0]` 守住；內部這些檢查除非使用者明確要求強化，否則保留。
- 程式碼註解與使用者面向的訊息都是繁體中文，編修時請沿用這個慣例。
