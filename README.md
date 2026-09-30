# Chromium Full Source Tarballs

为信创项目提供包含 **Chromium 完整源码、工具链、Linux Sysroot 及构建依赖**的一体化源码包，支持 Chromium 的**离线移植、交叉编译与长期归档**。

本项目不维护 Chromium 分支，而是根据指定 Chromium 版本，通过官方 `depot_tools` / `gclient` 工作流获取源码及构建依赖。

支持国产芯片：

* x86: 兆芯、海光
* arm64: 飞腾、华为麒麟、瑞芯微等
* loongarch64: 龙芯

龙芯版本已经包含龙芯官方sysroot、llvm、补丁包。

本项目源码包适合在 X86 架构系统上交叉编译 arm64/loong64（新世界） 的 Chromium。

构建系统可选 UOS V20、deepin v25、Ubuntu 24.04。理论上其他 Linux 发行版也可以，但未经验证。如果发现构建问题，欢迎提 issue。

## 项目背景

Chromium 的官方源码获取方式依赖 `depot_tools`、`fetch`、`gclient sync` 和 `gclient runhooks`。除了 Chromium 主仓库之外，构建过程中还会获取大量 `third_party` 依赖、Clang/LLVM、Rust、Sysroot 以及其他构建工具。

对于信创操作系统、国产 CPU 平台以及网络受限的构建环境而言，直接从 Chromium 官方仓库重新获取这些依赖存在以下问题：

* 源码及第三方依赖数量庞大；
* 构建依赖较多，首次准备环境耗时较长；
* 部分构建工具由 Chromium hooks 自动下载；
* 网络受限或完全离线的环境无法直接执行 `gclient sync` / `gclient runhooks`；

因此，本项目将指定 Chromium 版本所需的源码及 Chromium 构建依赖统一归档，形成可以直接分发和离线使用的源码包。

源码包中会保留 Chromium 的具体版本和 Git revision 信息，以便后续确认源码来源。

## 包含内容

根据 Chromium 版本及目标架构，生成的源码包主要包含：

```text
Chromium source
Chromium third_party dependencies
Clang / LLVM
Rust toolchain
Linux Sysroot
depot_tools Chromium 构建工具
```

其中工具链和其他构建依赖主要来自 Chromium `DEPS`、hooks 以及 Chromium 自身的构建配置。

### ARM64

对于 ARM64 版本，源码包会包含对应的 Linux ARM64 Sysroot，以支持交叉编译。

例如：

```text
chromium-full-src-140.0.7339.82-linux-arm64.tar.zst
```

该版本面向 Linux ARM64 Chromium 的移植和构建。

### loong64

loong64 不是 Chromium 官方支持的目标架构，Chromium 官方不提供对应的 Sysroot 和 Clang/LLVM 工具链。

因此 loong64 架构的源码包使用 Loongnix 提供的构建资源：Sysroot、Toolchain 和 Patch。

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
└── depot_tools/
```

## 构建

源码包的主要使用场景是网络受限或完全离线的 Chromium 构建环境。

在具有对应宿主机基础依赖的 Linux 环境中，解压源码包后，可以直接进入：

```bash
cd chromium-full-src-140.0.7339.82-linux-arm64/src
```

在 Ubuntu 系统上，可以运行如下命令安装构建依赖包：

```bash
./build/install-build-deps.sh
```

设置chromium构建工具 gn/ninja 的路径：

```bash
export PATH=$(pwd)/depot_tools:$PATH
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

## 项目与 Chromium 的关系

本项目：

* 不属于 Chromium 官方项目；
* 不维护 Chromium fork；
* 不重新发布 Chromium 的 Git 历史；
* 主要负责 Chromium 源码及构建依赖的归档和分发。

Chromium 源码及其中包含的第三方组件分别遵循其各自的许可证和版权声明。

使用、修改和再分发源码时，请遵循 Chromium 及相关第三方组件的 LICENSE、NOTICE 和其他许可证要求。

## License

本项目自身的脚本和配置文件按照仓库中的 LICENSE 发布。

Chromium 源码以及其中包含的第三方组件不属于本项目原创内容，其许可证以源码中的 LICENSE、NOTICE 以及各第三方组件自身的许可证文件为准。
