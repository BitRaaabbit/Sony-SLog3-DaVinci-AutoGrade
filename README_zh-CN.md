# Sony S-Log3 DaVinci AutoGrade

一套面向**已可靠确认 Sony S-Gamut3.Cine / S-Log3**素材的保守、安全、可诊断 DaVinci Resolve 工作流。相机型号只进入报告，不作为准入条件。

当前分支属于开发重构版。在 `docs/REGRESSION_TESTS.md` 的真实素材验证全部通过前，不应视为稳定生产版本。

## 已验证环境

- Windows、DaVinci Resolve 20.3.2 免费版
- 从 `Workspace > Scripts > Utility` 运行内部 Lua
- 使用实机验证成功的 `app:GetResolve()` 获取内部 Resolve 对象
- DaVinci YRGB Color Managed，关闭自动色彩管理
- Timeline：DaVinci Wide Gamut / DaVinci Intermediate
- Output：Rec.709 Gamma 2.4
- 不使用 LUT

工作流不依赖外部 Resolve API，也不安装编解码器、插件、LUT、Python 包或可执行文件。

## 架构

`Sony SLog3 Template Capture.lua` 先验证当前 Resolve 项目完全为空，并读回 Playback FPS、Timeline FPS、宽度和高度；全部匹配后才将该项目导出为私有且不覆盖的 DRP。它不会修改任何项目设置。

`Sony SLog3 Diagnostic.lua` 从纯 ASCII 路径读取本地 runtime profile，并验证同批素材。推荐的 `drp_template` 引导方式会把私有空白 DRP 以唯一项目名导入，再次验证格式和空项目状态，任一不匹配立即停止。只有 `Project:GetPresetList()` 能精确暴露已验证 Preset 时，才可选择保留的 `preset` 引导方式。Project Format 与色彩管线严格分离。兼容媒体由外部 filesystem/hash/ffprobe attestation 负责原片身份和精确 Original → Working 映射；Resolve 只导入 working 路径，并以真实 Video Track TimelineItem 证明视频解码成功。Resolve MediaStorage 枚举不再作为原始相机素材的存在性权威。

`Sony SLog3 AutoGrade.lua` 只有同时满足以下条件才允许运行：

- 诊断项目已经通过；
- 已明确选出代表测试素材；
- 存在人工批准的参考时间线；
- test 或 batch 已明确授权；
- 已明确授权启动渲染；
- Render Queue 为空；
- 首测最多3条，每批最多10条。

自动化只复现经过人工确认的参考调色，不在代码中固化永久 Neutral Safe Primary 数值。正式架构是：**人工批准 Reference TimelineItem → 官方 Still/DRX 导出 → SHA-256 锁定 DRX → `ApplyGradeFromDRX()`**。官方 `CopyGrades()`保留用于同项目直接复制和交叉验证。

Compatibility working media 默认 fail-closed。工作媒体必须先通过哈希绑定的外部预检与 signal equivalence，再在全新 Resolve 项目中通过真实视频解码诊断，AutoGrade 才能导入。Full→Limited 归一化属于 codec/range representation compatibility，不是创意调色或色彩空间转换；合法 limited-range DNxHR 不得在 Resolve 中强制设为 Full。

## 安装

1. 将 `scripts/` 下三个 Lua 文件复制到：

   `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility\`

2. 将 `config/runtime.example.lua` 复制为已忽略的 `config/runtime.local.lua`，填写可靠确认的本地元数据和路径，设置 `bootstrap_method = "drp_template"`，并指定私有、纯 ASCII 的 `template_path`。
3. 将本地 profile 复制到：

   `%TEMP%\SonySLog3AutoGrade\runtime.lua`

4. 新建空 Resolve 项目，在导入素材前人工设置并确认本批分辨率、Timeline FPS 和 Playback FPS，然后只运行一次 `Workspace > Scripts > Utility > Sony SLog3 Template Capture`。先读取 `template_capture.log`，并将导出的 DRP 保持为本地私有文件。
5. 只运行一次 `Workspace > Scripts > Utility > Sony SLog3 Diagnostic`。在任何调色或渲染前，先读取 `%TEMP%\SonySLog3AutoGrade\diagnostic.log` 和 `diagnostic_report.md`。

Runtime profile 和日志使用纯 ASCII 路径，是因为 Resolve 内部 Lua 的 `io.open` 在 Windows Unicode 路径上可能失败。素材路径仍直接交给 Resolve API，不能因此假定中文素材路径无法导入。

## Neutral Safe

Neutral Safe 面向活动、展会和纪录素材，目标是正常、自然、干净、通透，不制造明显滤镜感。当前候选范围仅用于测试：Contrast 约1.08、Pivot 约0.44、Color Boost 0–4、Saturation 约50、Highlights 约-4、Temperature 0、Tint 0。

这些不是永久默认参数，必须通过真人审片确认参考时间线。策略上禁止统一加暖、强 Color Boost、强饱和、Sharpen、Midtone Detail、Clarity、颗粒、全片降噪及风格化 LUT。

API 不保证暴露全部 Color Page Primary setter/readback。Reference Prep 因此只创建纯 RCM master Timeline 和纯 RCM reference seed Timeline，只渲染 RCM 基准，并把 seed 打开到 Color Page。人工批准以后，工作流抓取 Still、导出官方 DRX、计算并锁定 SHA-256，再应用该不可变 artifact；脚本不会重建不可读的 Primary 数值。

## 安全规则

- 原素材只读：不得移动、重命名、删除、覆盖，也不得渲染回源目录。
- Gamma、Primaries、帧率或分辨率未知/混杂时立即停止。
- 不静默覆盖已有输出。
- 机身型号不能替代 Gamma/Primaries 证据。
- Original source 与 Resolve working media 身份不得混淆；Input Color Policy 始终来自 original 的可靠元数据。
- `ImportMedia()` 返回对象不等于视频可解码；必须验证真实 Video Track TimelineItem。
- 调色问题与交付编码问题分开诊断。
- 全量批处理前必须完成小规模人工审片。

详见[工作流](docs/WORKFLOW.md)、[故障排查](docs/TROUBLESHOOTING.md)和[回归测试](docs/REGRESSION_TESTS.md)。

## 适用边界

本项目只面向已确认 Sony S-Gamut3.Cine / S-Log3 的素材，不保证适配其他相机、色域、Log 曲线、RAW 格式、操作系统或 Resolve 版本。

## 许可证

MIT，见 `LICENSE`。
