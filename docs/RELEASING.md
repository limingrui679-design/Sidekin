# CainiaoPet 发布流程

> 当前项目只作为 GitHub 源码项目和本地 Beta，不计划向普通用户公开分发已签名 App。Developer ID、公证和 Gatekeeper 放行不是当前完成条件；本页仅供未来改变分发目标时使用。

## 两种包必须区分

- `./Scripts/package-release.sh` 生成本机可测试的 ad-hoc 包。它有完整测试、资源哈希和干净 ZIP，但没有 Developer ID 与 Apple 公证。
- `./Scripts/release-public.sh` 才是可对外分发的正式流程。它会强制检查干净 Git 提交、Developer ID、Hardened Runtime、公证、票据装订和 Gatekeeper。

任何 ad-hoc 包都不得标记为“Apple 已验证”或“公开发布版”。

## 首次准备

1. 在 Apple Developer 账户中创建并安装 `Developer ID Application` 证书。
2. 注册本项目使用的反向域名 Bundle ID。
3. 把公证凭据保存到当前用户的钥匙串，不要写进仓库：

```bash
xcrun notarytool store-credentials "CainiaoPet-Notary"
```

4. 确认源码已提交，工作区没有未跟踪或未提交内容。

## 正式发布

以下值必须由发布者自己的 Apple Developer 账户提供：

```bash
export CAINIAOPET_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
export CAINIAOPET_NOTARY_PROFILE="CainiaoPet-Notary"
export CAINIAOPET_BUNDLE_ID="com.example.cainiaopet"
./Scripts/release-public.sh
```

脚本按以下顺序执行：

1. 运行源码、API 模拟、资源、Debug 和 Release 检查。
2. 分别签名桥接程序、主程序和 App 外壳，并启用 Hardened Runtime 与安全时间戳。
3. 生成无 `__MACOSX`、`.DS_Store` 和 AppleDouble 条目的上传 ZIP。
4. 使用 `notarytool` 等待 Apple 公证结果。
5. 将公证票据装订到 App，并验证票据。
6. 用已装订 App 重新生成最终 ZIP、发布清单和 SHA-256 文件。
7. 使用 `spctl` 做 Gatekeeper 验收，并再次验证 ZIP 内 App。

只有最后一行显示所有正式门禁通过后，才可以把 App 二进制作为面向普通用户直接下载运行的 GitHub Release 发布。当前源码项目与 CI 构建验证不需要执行这一流程。

## 发布文件

```text
artifacts/CainiaoPet-macOS-arm64.zip
artifacts/CainiaoPet-macOS-arm64.RELEASE.json
artifacts/CainiaoPet-macOS-arm64.zip.sha256
```

上传前应将版本标签与 `Support/Info.plist` 中的版本、Build 号保持一致，并把同一提交号写入 Release 说明。不要上传 `artifacts/CainiaoPet.app` 目录本身。
