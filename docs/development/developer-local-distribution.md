# Piki 开发者本地分发

这份文档描述 Piki 当前的开发者友好分发方式：不依赖 Apple 开发者账号，不做签名与公证，默认面向愿意本地部署的开发者。

## 1. 发布物

- GitHub Release 主产物：`Piki.app.zip`
- 校验文件：`SHA256SUMS`
- 默认平台：Apple Silicon macOS

## 2. 构建发布包

在维护者机器上运行：

```bash
./scripts/build_macos_dev_release.sh
```

脚本会完成：

- 重新生成 `PikiApp.xcodeproj`
- 构建 Release 版 `Piki.app`
- 打入内嵌 Python runtime 与 `agent_service`
- 产出 `dist/Piki-<version>-macos-arm64/`
- 生成 `Piki.app.zip`
- 生成 `SHA256SUMS`

## 3. 开发者安装

推荐直接运行安装脚本：

```bash
./scripts/install_piki_dev_release.sh --version <tag>
```

默认行为：

- 从 GitHub Release 下载 `Piki.app.zip`
- 优先安装到 `/Applications/Piki.app`
- 若当前用户无权限，则回退到 `~/Applications/Piki.app`
- 自动移除 quarantine 属性
- 安装完成后自动启动 App

如果你不想自动启动：

```bash
./scripts/install_piki_dev_release.sh --version <tag> --no-launch
```

如果你想指定安装位置：

```bash
./scripts/install_piki_dev_release.sh --version <tag> --dest ~/Applications
```

## 4. 手动安装

如果不走脚本，也可以手动：

1. 下载 `Piki.app.zip`
2. 解压得到 `Piki.app`
3. 拖到 `Applications` 或 `~/Applications`
4. 如首次打开被拦截，运行：

```bash
xattr -dr com.apple.quarantine /Applications/Piki.app
```

或者对 `~/Applications/Piki.app` 执行同样命令。

## 5. 首次使用

首次启动后，Piki 会自动：

- 创建默认知识库 `~/Documents/Piki Vault`
- 创建运行时私有目录 `~/.piki`
- 启动本地 `agent_service`

开发者仍需要在设置页完成：

- 模型
- Base URL
- API key

配置完成后运行一次 `Smoke Test` 即可验证模型链路。
