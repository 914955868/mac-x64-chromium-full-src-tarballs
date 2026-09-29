# Chromium Full Source Tarballs

为信创项目提供包含 **Chromium 完整源码、工具链、Linux Sysroot 及构建依赖**的一体化源码包，支持 Chromium 的**离线移植、交叉编译与长期归档**。

本项目不维护 Chromium 分支，也不修改 Chromium 源码，而是根据指定 Chromium 版本，通过官方 `depot_tools` / `gclient` 工作流获取源码及构建依赖，生成经过整理和校验的离线源码包。

## 项目背景

Chromium 的官方源码获取方式依赖 `depot_tools`、`fetch`、`gclient sync` 和 `gclient runhooks`。除了 Chromium 主仓库之外，构建过程中还会获取大量 `third_party` 依赖、Clang/LLVM、Rust、Sysroot 以及其他构建工具。

对于信创操作系统、国产 CPU 平台以及网络受限的构建环境而言，直接从 Chromium 官方仓库重新获取这些依赖存在以下问题：

* 源码及第三方依赖数量庞大；
* 构建依赖较多，首次准备环境耗时较长；
* 部分构建工具由 Chromium hooks 自动下载；
* 网络受限或完全离线的环境无法直接执行 `gclient sync` / `gclient runhooks`；
* 不同 Chromium 版本对应的依赖版本不同；
* 重新准备构建环境不利于版本归档和问题复现。

因此，本项目将指定 Chromium 版本所需的源码及 Chromium 构建依赖统一归档，形成可以直接分发和离线使用的源码包。

## 项目目标

本项目主要解决以下问题：

1. **完整归档 Chromium 源码**
2. **归档 Chromium third_party 依赖**
3. **归档 Chromium 官方构建工具链**
4. **归档 Linux Sysroot**
5. **支持 ARM64 / LoongArch64 交叉编译**
6. **减少离线环境准备 Chromium 构建环境的工作量**
7. **固定 Chromium 版本及对应依赖，便于长期维护和问题复现**
8. **通过 SHA-256 校验保证源码包完整性**
9. **通过 CI 自动生成和验证源码包**

## 包含内容

根据 Chromium 版本及目标架构，生成的源码包主要包含：

```text
Chromium source
Chromium third_party dependencies
Chromium build tools
Clang / LLVM
Rust toolchain
Linux Sysroot
Chromium hook dependencies
GN / Ninja 等 Chromium 构建相关工具
```

其中工具链和其他构建依赖主要来自 Chromium 官方 `DEPS`、hooks 以及 Chromium 自身的构建配置。

### ARM64

对于 ARM64 版本，源码包会包含对应的 Linux ARM64 Sysroot，以支持：

```text
x86_64 host
    ↓
Chromium ARM64 cross compilation
    ↓
ARM64 target
```

例如：

```text
chromium-full-src-140.0.7339.82-linux-arm64.tar.zst
```

该版本面向 Linux ARM64 Chromium 的移植和构建。

### LoongArch64 (loong64)

LoongArch64 不是 Chromium 官方支持的目标架构，Chromium 官方不提供对应的 Sysroot 和 Clang/LLVM 工具链。

因此 loong64 架构的源码包使用 Loongnix 提供的构建资源：

```text
Sysroot:   http://ftp.loongnix.cn/browser/build/sysroot/debian_bullseye_loongarch64-sysroot.tar.bz2
Toolchain: http://ftp.loongnix.cn/browser/build/toolchain/Release+Asserts-126.tar.bz2
Patch:     https://github.com/loongson/chromium/blob/loongarch-patches/chromium126/0001-la64-cross-CH126-Add-loongarch-build-support-for-old-new-w.patch
```

其中：

* Sysroot 解压到 `src/build/linux/`（目录名 `debian_bullseye_loongarch64-sysroot`）；
* 工具链解压到 `src/third_party/llvm-build/`，即替换 `src/third_party/llvm-build/Release+Asserts`：

```bash
rm -rf src/third_party/llvm-build/Release+Asserts
tar -xjvf Release+Asserts-126.tar.bz2 -C src/third_party/llvm-build/
```

* 源码同步完成后，在 `src/` 下打入 Loongson 的 LoongArch64 适配 patch：

```bash
cd src
patch -Np1 -i 0001-la64-cross-CH126-Add-loongarch-build-support-for-old-new-w.patch
```

该 patch 覆盖 `BUILD.gn`、`build/`、`base/`、`sandbox/`、`media/`、`third_party/` 等 131 个文件，为 `use_nw` old world / new world 构建提供 LoongArch 支持，因此必须在 `gclient runhooks` 之前应用。

由于 Loongnix 只提供 Chromium 126 对应的构建资源，**loong64 架构的 Chromium 版本被限制为 126**（例如 `126.0.6478.126`），其他版本会直接报错退出。

例如：

```text
chromium-full-src-126.0.6478.126-linux-loong64.tar.zst
```

## 不包含内容

本项目的源码包并不等同于一个完整的 Linux 操作系统或完整宿主机编译环境。

源码包**不包含**：

```text
Ubuntu root filesystem
Linux kernel
GPU driver
系统服务
宿主机 apt 软件包
宿主机系统库
用户自己的构建输出
```

特别需要说明：

```text
./build/install-build-deps.sh
```

用于安装 Chromium 在宿主 Ubuntu 系统上的构建依赖。这些宿主机软件包并不会因此自动进入源码压缩包。

因此，本项目更准确的定位是：

> **Chromium 源码及 Chromium 构建依赖的离线归档包**

而不是：

> 完全自包含的 Linux 编译环境。

## 排除内容

为了避免源码包体积进一步增长，默认不会包含 Chromium 的 Git 历史和构建输出。

主要排除：

```text
.git/
src/out/
src/out_*/
```

其中：

```text
src/out/
```

是 Chromium 的本地构建输出目录，不属于源码及构建依赖，因此不会进入发布包。

源码包中会保留 Chromium 的具体版本和 Git revision 信息，以便后续确认源码来源。

## 目录结构

生成的源码包采用以下结构：

```text
chromium-full-src-<version>-linux-<arch>/
├── chromium-build-manifest.txt
└── src/
    ├── base/
    ├── build/
    ├── chrome/
    ├── content/
    ├── net/
    ├── third_party/
    ├── tools/
    └── ...
```

例如：

```text
chromium-full-src-140.0.7339.82-linux-arm64/
├── chromium-build-manifest.txt
└── src/
    ├── base/
    ├── build/
    ├── chrome/
    ├── content/
    ├── third_party/
    └── ...
```

## Manifest

每个源码包都会包含：

```text
chromium-build-manifest.txt
```

用于记录本次源码包的基本信息，例如：

```text
Project: chromium-full-src-tarballs

Chromium version: 140.0.7339.82
Chromium revision: <git revision>

Target architecture: arm64
Host architecture: x86_64

Generated: <timestamp>

Included:
- Chromium source
- Chromium third_party dependencies
- Chromium build tools
- Chromium Clang/LLVM toolchain
- Chromium Rust toolchain
- Linux sysroot
- Chromium hook dependencies

Excluded:
- src/out
- Git metadata
```

这样即使源码包经过长期保存，也可以确认其对应的 Chromium 版本和具体 revision。

## 发布格式

源码包采用 `tar.zst` 格式：

```text
chromium-full-src-<version>-linux-<arch>.tar.zst
```

例如：

```text
chromium-full-src-140.0.7339.82-linux-arm64.tar.zst
```

同时提供 SHA-256 校验文件：

```text
SHA256SUMS
```

对于超过 GitHub Release 单文件限制的大型源码包，会进一步拆分：

```text
chromium-full-src-140.0.7339.82-linux-arm64.tar.zst.part-000
chromium-full-src-140.0.7339.82-linux-arm64.tar.zst.part-001
chromium-full-src-140.0.7339.82-linux-arm64.tar.zst.part-002
...
```

并提供：

```text
SHA256SUMS.parts
```

用于验证每一个分片。

## 恢复完整源码包

下载所有分片后，可以使用 `cat` 合并：

```bash
cat chromium-full-src-140.0.7339.82-linux-arm64.tar.zst.part-* \
    > chromium-full-src-140.0.7339.82-linux-arm64.tar.zst
```

然后验证完整文件：

```bash
sha256sum -c SHA256SUMS
```

验证通过后解压：

```bash
tar \
    --use-compress-program=zstd \
    -xf chromium-full-src-140.0.7339.82-linux-arm64.tar.zst
```

解压后：

```text
chromium-full-src-140.0.7339.82-linux-arm64/
└── src/
```

## 离线构建

源码包的主要使用场景是网络受限或完全离线的 Chromium 构建环境。

在具有对应宿主机基础依赖的 Linux 环境中，解压源码包后，可以直接进入：

```bash
cd chromium-full-src-140.0.7339.82-linux-arm64/src
```

然后根据实际构建目标生成 GN 配置。

例如 ARM64：

```bash
gn gen out/Release --args='
  is_debug=false
  target_os="linux"
  target_cpu="arm64"
  is_component_build=false
'
```

执行构建：

```bash
autoninja -C out/Release chrome
```

具体 GN 参数应根据目标操作系统、CPU、图形栈以及信创平台实际情况进行调整。

> 注意：源码包提供 Chromium 侧的源码、工具链、Sysroot 和相关构建依赖，但不保证可以在任意 Linux 发行版上直接构建。Chromium 官方当前 Linux 构建基础设施主要使用 Ubuntu 22.04，其他发行版可能需要额外适配。

## 交叉编译

本项目重点支持：

```text
x86_64 Linux Host
        │
        │ Chromium Clang / LLVM
        │ ARM64 Sysroot / LoongArch64 Sysroot
        ↓
Linux ARM64 Chromium / Linux LoongArch64 Chromium
```

因此特别适合以下场景：

* 国产 ARM64 / LoongArch64 CPU；
* 信创桌面操作系统；
* ARM64 Linux 桌面环境；
* Chromium ARM64 移植；
* 浏览器及 WebView 平台移植；
* 无公网环境下的 Chromium 构建。

## 构建流程

源码包由 CI 自动生成，基本流程如下：

```text
指定 Chromium Version
        │
        ↓
fetch Chromium
        │
        ↓
checkout 指定 Revision
        │
        ↓
gclient sync
        │
        ↓
应用目标架构 patch（仅 loong64）
        │
        ↓
install-build-deps
        │
        ↓
gclient runhooks
        │
        ↓
安装目标 Linux Sysroot
        │
        ↓
验证工具链及依赖
        │
        ↓
删除 Git metadata
        │
        ↓
删除 src/out
        │
        ↓
生成 chromium-build-manifest.txt
        │
        ↓
tar.zst
        │
        ↓
SHA-256
        │
        ↓
必要时拆分大文件
        │
        ↓
GitHub Release
```

## CI

项目使用 GitHub Actions 自动生成源码包。

由于 Chromium 源码、工具链和构建依赖占用较大的磁盘空间，CI 推荐使用自托管 Linux Runner，而不是普通的 GitHub Hosted Runner。

推荐配置：

```text
OS:       Ubuntu 22.04 x86_64
CPU:      16 cores or more
RAM:      32 GB or more
Disk:     300 GB or more
Storage:  SSD
Network:  High bandwidth
```

实际磁盘需求会随着 Chromium 版本、源码 checkout、hooks 下载内容以及压缩过程产生的临时文件而变化，因此生产环境建议预留更多空间。

## 版本管理

项目按照 Chromium 版本进行归档。

版本列表保存在：

```text
versions/stable.txt
```

例如：

```text
140.0.7339.82
```

每个版本对应一个明确的 Chromium Git revision。

Release 命名：

```text
chromium-<version>-<arch>
```

例如：

```text
chromium-140.0.7339.82-arm64
chromium-140.0.7339.82-amd64
chromium-126.0.6478.126-loong64
```

这种方式可以同时维护同一 Chromium 版本针对不同目标架构的源码包。

需要注意的是，loong64 架构只支持 Chromium 126。

## 可复现性

本项目不会尝试维护自己的 Chromium fork。

源码包以 Chromium 官方 revision 为基础进行归档：

```text
Chromium Version
        +
Chromium Git Revision
        +
DEPS dependencies
        +
Chromium hooks
        +
Target Sysroot
        ↓
Offline Source Package
```

因此后续可以根据 `chromium-build-manifest.txt` 确认源码包对应的 Chromium revision。

需要注意的是，**源码包归档并不自动等同于字节级可复现构建**。最终构建结果仍可能受到宿主机系统、编译参数、环境变量以及其他外部因素影响。

## 项目与 Chromium 的关系

本项目：

* 不属于 Chromium 官方项目；
* 不维护 Chromium fork；
* 不修改 Chromium 源码；
* 不重新发布 Chromium 的 Git 历史；
* 主要负责 Chromium 源码及构建依赖的归档和分发。

Chromium 源码及其中包含的第三方组件分别遵循其各自的许可证和版权声明。

使用、修改和再分发源码时，请遵循 Chromium 及相关第三方组件的 LICENSE、NOTICE 和其他许可证要求。

## 适用场景

本项目主要面向：

### 信创操作系统

为国产桌面操作系统准备固定版本的 Chromium 源码及构建依赖，降低构建环境准备成本。

### 国产 CPU / ARM64 / LoongArch64 平台

提供 ARM64、LoongArch64 Sysroot 和 Chromium 构建依赖，方便在 x86_64 Linux 主机上进行 ARM64、LoongArch64 Chromium 交叉编译。

### 离线环境

在无法访问公网的环境中，提前准备完整 Chromium 源码及构建依赖，避免构建过程中访问 Chromium 官方服务器。

### 长期维护

按照 Chromium 版本归档源码包，使历史版本能够独立保存，方便后续维护、问题定位和补丁开发。

## 注意事项

### 1. 源码包不是完整操作系统

源码包不能替代 Ubuntu 等 Linux 宿主系统，也不能替代宿主机的系统库、驱动和 apt 软件包。

### 2. 构建前仍需准备宿主机环境

Chromium 官方构建脚本会检查和使用宿主机的基础开发环境。

建议使用与 Chromium 构建基础设施相匹配的 Ubuntu 版本。

### 3. 不建议对源码包再次执行 gclient sync

源码包的目标是离线构建。

解压后已经包含对应版本所需的 Chromium 源码和构建依赖。在完全离线环境中再次执行：

```bash
gclient sync
```

可能会尝试访问网络，因此不应将其作为离线构建流程的一部分。

### 4. 不包含 out 目录

每个用户都应该根据自己的目标平台和构建参数重新生成：

```text
src/out/
```

例如：

```bash
gn gen out/Release ...
```

然后：

```bash
autoninja -C out/Release chrome
```

## Roadmap

后续计划包括：

* [x] Chromium 指定版本源码归档
* [x] Chromium third_party 依赖归档
* [x] Chromium Clang/LLVM 工具链归档
* [x] Rust 工具链归档
* [x] Linux Sysroot 归档
* [x] 排除 `src/out`
* [x] SHA-256 完整性校验
* [x] GitHub Release 自动发布
* [x] 大型源码包自动拆分
* [x] LoongArch64 (loong64) 源码包归档（限制 Chromium 126）
* [ ] ARM64 离线构建自动验证
* [ ] AMD64 离线构建自动验证
* [ ] LoongArch64 离线构建自动验证
* [ ] 多个 Chromium 稳定版本长期归档
* [ ] 构建元数据进一步标准化
* [ ] 提供更加完善的离线构建文档

## License

本项目自身的脚本和配置文件按照仓库中的 LICENSE 发布。

Chromium 源码以及其中包含的第三方组件不属于本项目原创内容，其许可证以源码中的 LICENSE、NOTICE 以及各第三方组件自身的许可证文件为准。
