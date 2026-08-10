# CainiaoPet 1.2.0 Beta 完成审计

本页把需求、实现与可复现证据分开记录。通过测试不等于已经公开发布；模拟 API 也不等于真实付费调用。

## 逐项结论

| 项目 | 当前结论 | 权威证据 |
|---|---|---|
| 逐阶段保存与断点续跑 | 已实现并测试 | `PetGenerationJobStore` 先保存 `raw-stage-XX.png`；API 模拟测试会在第二阶段中断，再从本地恢复且不重复第一阶段请求。 |
| 单阶段重试和替换 | 已实现并测试 | `regenerateStage` 在处理前保存隐藏恢复原图；模拟测试使处理故意失败两次并确认只发生一次 API 请求，成功替换后恢复文件被清理。 |
| 粉色/紫色安全抠图 | 已实现并测试 | `PetImageProcessor` 只从画布四周扩展背景连通区域，并自适应边缘主色；合成测试确认主体内部洋红和粉色不会被挖空。 |
| 原图和抠图预览 | 已实现、编译通过 | 恢复任务同时暴露原图与已处理阶段 URL，工坊恢复卡片分别显示两个预览。尚未在本轮启动 App 做人工点击验收。 |
| 三档质量与费用 | 已实现并测试 | `low / medium / high` 会进入生成与编辑请求；确认框按阶段数显示当前 1024 方图输出估算，并明确输入费用另计。 |
| 三套进化线重画 | 已完成资源检查与小尺寸人工复核 | 糖果、荒原和星核五阶段资源已替换；50 张 PNG 全部为独立 `1254×1254` 透明图。`ART_QA_DESKTOP_SCALE.jpg` 按接近 235px 显示区域排列全套形态。 |
| 模板管理 | 已实现并测试 | 支持重命名、删除、二进制模板包导入/导出、本地图替换和 AI 单阶段重绘；路径穿越、损坏 PNG、体积和阶段数均有门禁。 |
| 干净发布包 | 已实现并测试 | 打包验证会解压复验 App、资源和清单，并拒绝 `__MACOSX`、`.DS_Store`、AppleDouble、损坏 ZIP、arm64 漂移及哈希不一致。 |
| 独立源码仓库 | 已完成 | 仓库不再包含 ClaimTrace 文件；Git 提交、Beta 标签、CI 工作流、版本、发布清单和资源哈希均在 CainiaoPet 自己的目录中。 |
| Apple 公开发布 | 流程已实现，实际签名未完成 | `release-public.sh` 强制要求 Developer ID、注册 Bundle ID、Hardened Runtime、公证、装订和 Gatekeeper；当前机器没有 Developer ID，因此会在上传前退出。 |

## 一键复验

```bash
./Scripts/run-all-checks.sh
./Scripts/package-release.sh
```

第二条命令生成 ZIP 后，还会对 ZIP 内的 App 再执行一次签名、架构、资源与发布清单验证。

## 仍未声称完成的事项

- 没有使用任何真实 OpenAI API Key，也没有产生真实付费调用。
- 没有在本轮启动未公证 App、安装 Hooks 或执行工坊按钮点击。
- 没有 Developer ID 证书、Team ID 或 Apple 公证票据；当前包仍是本地 ad-hoc Beta。
- 已加入 GitHub Actions 配置，但仓库尚未在 GitHub 创建远端，因此没有远端 CI 运行记录或公开 Release。

因此，当前准确表述仍是“完成、测试并可追溯的本地 macOS Beta”，不是“已公开发布产品”或“真实 API 全链路已验证”。
