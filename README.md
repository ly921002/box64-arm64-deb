# box64-arm64-deb

ARM64 平台上的 **Box64 x86_64 模拟器**预编译 Debian 包 + 一键安装脚本。

在飞腾 / 鲲鹏 / 树莓派 / RK3588 / Apple M 系列虚拟机等 ARM64 Linux 上，
直接用它跑 x86_64 的 Linux 程序（含游戏、Wine、Steam 等）。

---

## 📦 包基本信息

| 项 | 值 |
| --- | --- |
| 包名 | `box64` |
| 声明版本 | `0.3.5` |
| **二进制实际版本** | **v0.4.3**（commit `373e1306a`）⚠️ 见下方说明 |
| 架构 | `arm64` |
| 维护者 | `local`（本地构建，非官方源） |
| 依赖声明 | **无 `Depends` 字段** |
| 描述 | Box64 x86_64 emulator with ARM Dynarec and binfmt |
| deb 格式版本 | `2.0`，内部用 zstd 压缩 |

### 校验值

| 文件 | 大小 | SHA-256 |
| --- | --- | --- |
| `box64-deb.deb` | 15,715,356 B (15.0 MiB) | `e530f6014fb699e018e8525c073ea5b5cf0494be1b70de81d437e9a6944cef80` |
| `install.sh` | 808 B | `1ee996a2022f41956689beb6870a57d86b097b89cace1ae4c209af130c0e122d` |

包内文件：

| 路径 | 大小 | SHA-256 |
| --- | --- | --- |
| `/usr/local/bin/box64` | 84,402,432 B (80.5 MiB) | `f69d0e34004c2b9268b21d40c7c2949bbd7c4fa7b85bbc74c92969b71ec7c344` |
| `/etc/box64.box64rc` | 30,337 B | `11ec74e25dd96226d09274e8a80e5d2fd106aca6cfea1eb0428f7c5ac7358430` |
| `/etc/binfmt.d/box64.conf` | 212 B | `6b65bbccdb0c2d9e16917bb1eb321758cd8cfdc59da66efd5e2785ad4ef14eca` |

---

## 🔍 包内三个文件各自干什么

### 1. `/usr/local/bin/box64` —— 主程序

- AArch64 ELF 可执行文件（`e_machine=0xB7`，`e_type=2` 即静态链接的 EXEC）
- 内嵌版本串：`Box64 arm64 v0.4.3 373e1306a with Dynarec`
- 编入了 Dynarec（动态重编译），这是 Box64 性能的关键 —— 把 x86_64 指令块
  翻译成 ARM64 原生代码并缓存，比纯解释快一个数量级
- 还编入了 `gpu_stats` / `cpu_stats` / `fps` / `frame_timing` 等统计支持

### 2. `/etc/binfmt.d/box64.conf` —— 让内核自动调用 Box64

```
:box64:M::\x7fELF\x02\x01\x01\x00...\x02\x00\x3e\x00:<mask>:/usr/local/bin/box64:
```

这是 Linux `binfmt_misc` 的注册规则。作用是：
**当内核遇到一个它自己跑不了的 x86_64 ELF 时，自动交给 `/usr/local/bin/box64` 执行**，
于是你可以直接 `./some-x86_64-program` 而不用手写 `box64 ./some-x86_64-program`。

magic 逐字节拆解：

| 偏移 | 字节 | 含义 |
| --- | --- | --- |
| 0–3 | `7f 45 4c 46` | ELF magic |
| 4 | `02` | ELFCLASS64（64 位） |
| 5 | `01` | 小端 |
| 6 | `01` | EI_VERSION=1 |
| 7–15 | `00`×9 | OSABI + padding |
| 16–17 | `02 00` | **e_type = 2 = `ET_EXEC`** |
| 18–19 | `3e 00` | e_machine = 0x3e = 62 = `EM_X86_64` |

⚠️ **注意 e_type 那两字节**：mask 在这两字节上是 `ff fe`，
低字节（偏移 16）被**全量匹配**为 `0x02`。也就是说这条规则**只命中 `ET_EXEC`**，
而现代 Linux 发行版（Debian 12 / Ubuntu 22.04+）默认开启 PIE，
编译出来的程序是 `ET_DYN`（e_type = 3）—— **不会命中这条规则**。

用 `file` 就能确认：

```bash
file ./your-program
# 出现 "ELF 64-bit LSB executable"        → ET_EXEC，能自动拦截
# 出现 "ELF 64-bit LSB shared object"     → ET_DYN/PIE，不会自动拦截
```

碰到 PIE 程序有两个办法：

```bash
# 办法 A：显式调用（最稳妥，什么时候都行）
box64 ./your-program

# 办法 B：把 mask 放宽，让 ET_EXEC 和 ET_DYN 都命中
# 把偏移 16 的 mask 从 ff 改成 fc（忽略低 2 位，2 和 3 都能过）
sudo sed -i 's/\\xff\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff$/\\xfc\\xff\\xff\\xff\\xff\\xfe\\xff\\xff\\xff/' /etc/binfmt.d/box64.conf
sudo systemctl restart systemd-binfmt
```

> 上面 sed 的匹配串要按你文件里的实际 mask 调整，改之前先备份。

### 3. `/etc/box64.box64rc` —— 系统级默认配置

1445 行，**268 个配置段**，涉及 **47 种配置键**。结构是「进程名 → 环境变量」：

```ini
[*setup*]                      # 进程名（大小写不敏感）
BOX64_DYNACACHE=0
BOX64_DYNAREC_SAFEFLAGS=2

[/d3d11.dll]                   # 针对某个库的设置
BOX64_DYNAREC_STRONGMEM=0
BOX64_DYNAREC_BIGBLOCK=3

[Celeste.bin.x86_64]           # 针对某个游戏的设置
BOX64_DYNAREC_STRONGMEM=1
```

已针对大量程序调优，包括 `bash`、`chrome`、`7z`、`Celeste`、`AlienIsolation`、
`BeamNG.drive`、`Broforce`、各种 DirectX DLL（d3d8/9/10/11、dxgi）等。

常用的键：

| 键 | 作用 |
| --- | --- |
| `BOX64_DYNAREC_BIGBLOCK` | Dynarec 块大小，0=关，越大越快但越不稳 |
| `BOX64_DYNAREC_SAFEFLAGS` | 标志位处理严格度，2=最安全（安装器用），0=最快 |
| `BOX64_DYNAREC_STRONGMEM` | 内存模型强度，影响多线程程序正确性 |
| `BOX64_DYNAREC_CALLRET` | 调用/返回优化 |
| `BOX64_DYNACACHE` | Dynarec 缓存开关 |
| `BOX64_LOG` | 日志级别，调试时设 1~2 |
| `BOX64_EMULATED_LIBS` | 强制用 Box64 内建实现替代某些库 |
| `BOX64_AVX` / `BOX64_SSE42` / `BOX64_SHAEXT` | 模拟的指令集扩展 |
| `BOX64_MALLOC_HACK` | 应对某些程序的内存分配怪癖 |

> 优先级：**`~/.box64rc`（用户级）会覆盖 `/etc/box64.box64rc`（系统级）**。
> 想单独给某个程序调参，在家目录建 `.box64rc` 即可，别改系统文件。

---

## 📜 install.sh 逐段分析

```bash
dpkg -i ./box64-deb.deb || true      # ① 装 deb
dpkg --add-architecture amd64        # ② 让 apt 能装 amd64 包
apt update                           # ③ 刷新源
apt install -y libc6:amd64 \
   libstdc++6:amd64 libgcc-s1:amd64 \
   libcurl4:amd64 libssl3:amd64 \
   zlib1g:amd64                      # ④ 装 x86_64 运行库
apt -f install -y                    # ⑤ 补依赖
box64 -v || true                     # ⑥ 验证
```

**为什么要 ② 和 ④**：Box64 只翻译 CPU 指令，不翻译系统调用和库函数。
被模拟的 x86_64 程序最终还是要调用真实的 C 库、C++ 标准库、OpenSSL 等，
这些库必须是 **x86_64 版本**，所以在 ARM64 系统上要额外启用 amd64 架构来装。
这一步是必需的，不是可选的。

`libcurl4` 和 `libssl3` 主要是给 Steam、Wine、各类联网程序准备的。

**为什么 deb 里没写 `Depends`**：本地打包时没写。好处是 `dpkg -i` 一定成功；
坏处是缺库不会有任何提示，运行时才报 `libxxx.so.6: cannot open shared object file`。

---

## ⚠️ 发现的问题

按严重程度排序：

| # | 问题 | 影响 | 建议 |
| --- | --- | --- | --- |
| 1 | **binfmt 装了但没激活** | 装完脚本后自动拦截**不生效**，必须重启或手动激活 | 加一行 `systemctl restart systemd-binfmt` |
| 2 | **`\|\| true` 掩盖真实错误** | deb 损坏、架构不对时脚本照样"跑完"，最后 `box64 -v` 也失败得无声无息，你以为装好了 | 去掉 `\|\| true`，或失败后显式 `exit 1` |
| 3 | **版本号对不上**：control 写 `0.3.5`，二进制是 `v0.4.3` | `dpkg -l box64` 显示错误版本，将来无法靠版本号判断升级 | 重新打包时把 control 改成 `0.4.3` |
| 4 | **binfmt 规则只匹配 ET_EXEC** | 现代 PIE 程序不会被自动拦截（详见上文） | 放宽 mask，或显式 `box64 xxx` |
| 5 | **没检查 root 权限** | 非 root 运行时 `dpkg`/`apt` 会失败，报错信息不友好 | 开头加 `[ "$(id -u)" -eq 0 ] || exit 1` |
| 6 | **没检查主机架构** | 在 x86_64 机器上跑会把 arm64 包装上去 | 开头加 `dpkg --print-architecture` 判断 |
| 7 | **`libssl3` 兼容性** | Debian 11 / Ubuntu 20.04 是 `libssl1.1`，没有 `libssl3`，脚本会直接失败 | 按发行版分支处理，或改用 `libssl*` 通配 |
| 8 | **运行库不够全** | 只装了 6 个基础库；跑图形程序还缺 `libx11`、`libgl1`、`libxext` 等 | 按实际用途补 |

### 推荐的安装流程（在原脚本基础上补强）

```bash
# 0. 前置检查
[ "$(id -u)" -eq 0 ] || { echo "请用 root 运行"; exit 1; }
[ "$(dpkg --print-architecture)" = "arm64" ] || { echo "本包只适用于 arm64"; exit 1; }

# 1. 装包（不要吞掉错误）
dpkg -i ./box64-deb.deb || apt -f install -y

# 2. 启用 amd64 并装运行库
dpkg --add-architecture amd64
apt update
apt install -y libc6:amd64 libstdc++6:amd64 libgcc-s1:amd64 \
               libcurl4:amd64 libssl3:amd64 zlib1g:amd64

# 3. 【原脚本缺的关键一步】激活 binfmt
if command -v systemctl >/dev/null && systemctl is-system-running --quiet 2>/dev/null; then
    systemctl restart systemd-binfmt
else
    # 容器 / chroot / Termux 等无 systemd 环境
    update-binfmts --import /etc/binfmt.d/box64.conf 2>/dev/null || \
        echo "请自行挂载 binfmt_misc 后手动注册"
fi

# 4. 验证
box64 -v || { echo "安装失败"; exit 1; }
```

---

## 🚀 使用

```bash
# 装（需要 root）
chmod +x install.sh
sudo ./install.sh

# 手动激活 binfmt（装完必做，脚本没做这步）
sudo systemctl restart systemd-binfmt

# 验证
box64 -v
# 应输出：Box64 arm64 v0.4.3 373e1306a with Dynarec ...

# 直接跑 x86_64 程序（binfmt 生效后）
./some-x86_64-program

# 或显式调用（binfmt 没生效时用这个，永远有效）
box64 ./some-x86_64-program

# 临时调参
BOX64_LOG=1 BOX64_DYNAREC_BIGBLOCK=3 box64 ./program
```

### 确认 binfmt 是否真的生效

```bash
cat /proc/sys/fs/binfmt_misc/box64   # 有内容说明注册成功
ls /proc/sys/fs/binfmt_misc/         # 至少应有 box64 一项
```

---

## 🎯 适用平台

| 平台 | 说明 |
| --- | --- |
| Debian 12 (bookworm) arm64 | ✅ 推荐，`libssl3` 存在 |
| Ubuntu 22.04 / 24.04 arm64 | ✅ 推荐 |
| Debian 11 (bullseye) arm64 | ⚠️ 需把 `libssl3` 换成 `libssl1.1` |
| Ubuntu 20.04 arm64 | ⚠️ 同上 |
| 飞腾 D2000/S5000C、鲲鹏 920 | ✅ |
| 树莓派 4/5 (aarch64) | ✅ |
| RK3588 系列板子 | ✅ |
| Apple M 系列上的 ARM64 Linux 虚拟机 | ✅ |
| Termux / proot / 无 systemd 容器 | ⚠️ binfmt.d 不生效，需手动处理 |
| x86_64 主机 | ❌ 不需要，也没用 |

---

## ❓ 常见问题

**Q：运行报 `libxxx.so.6: cannot open shared object file`**
缺 x86_64 库。用 `apt-file search libxxx.so.6` 找到包名，然后 `apt install 包名:amd64`。

**Q：`box64 -v` 有输出，但程序还是跑不起来**
多半是缺库或 Dynarec 设置不合适。开日志看细节：
`BOX64_LOG=1 box64 ./program 2>&1 | tail -50`

**Q：程序能启动但很慢**
先确认 Dynarec 在工作（启动时日志会显示）。可以尝试
`BOX64_DYNAREC_BIGBLOCK=3 BOX64_DYNAREC_SAFEFLAGS=0`，但稳定性会下降。

**Q：想给某个游戏单独调参**
在家目录建 `~/.box64rc`，格式同 `/etc/box64.box64rc`，写 `[游戏进程名]` 段即可，会覆盖系统级配置。

**Q：卸载**
```bash
sudo dpkg -r box64
sudo rm -f /etc/binfmt.d/box64.conf
sudo systemctl restart systemd-binfmt
```

---

## 📝 说明

- 本包为**本地构建**（`Maintainer: local`），不是 Box64 官方发布物。
- Box64 上游：<https://github.com/ptitSeb/box64>
- 二进制内嵌版本为 **v0.4.3**（commit `373e1306a`），与 control 里声明的
  `0.3.5` 不一致 —— 已在上文「发现的问题」中标注。
- 本仓库只是把已有的 deb 与安装脚本归档，并附上分析结论；
  `install.sh` 保持原样未改动，修正建议见上文。
