# FX3-SLog3-DaVinci-AutoGrade

[English](README.md)

这是一个在 DaVinci Resolve 内部运行的 Lua 工作流，用于把已经可靠确认为 Sony FX3、S-Gamut3.Cine / S-Log3 的素材，以自然、保守、可复核的方式转换为 Rec.709 Gamma 2.4。

项目不猜测输入色彩空间、不自动套 LUT。工作流包含三条素材兼容性测试、Neutral V2A/V2B 人工对比，以及每次最多十条的 V2B 批处理。原素材目录始终按只读处理，渲染只能进入 `ship_output`。

## 已验证环境

- Windows 11
- DaVinci Resolve 20.3.2 免费版
- Sony FX3 / ILME-FX3
- Sony S-Gamut3.Cine / S-Log3
- 测试素材：HEVC Main 10、3840×2160、59.94p
- 输出：Individual Clips、MP4/H.264、AAC 双声道 48 kHz

其他 Resolve 版本的设置名称或编码能力可能不同。本项目不保证适配其他相机、色域、Log 曲线、帧率或编码格式。

## 默认色彩流程

- DaVinci YRGB Color Managed；关闭自动色彩管理
- Input：Sony S-Gamut3.Cine / S-Log3
- Timeline：DaVinci Wide Gamut / DaVinci Intermediate
- Output：Rec.709 Gamma 2.4
- Timeline / Playback：59.94 fps
- Resolution：3840×2160
- 不使用 LUT、自动曝光、自动白平衡、色温/Tint 修正、暗角、颗粒、美肤、降噪或额外锐化

统一 V2B 调整位于色彩管理后的新增串行节点 02：

| 参数 | 数值 |
|---|---:|
| Contrast | 1.120 |
| Pivot | 0.440 |
| Color Boost | 12.00 |
| Saturation | 54.00 |
| Highlights | -8.00 |
| Temperature | 0.0 |
| Tint | 0.00 |

## 安装

1. 下载或克隆项目到本地目录。支持中文和空格路径，但命令行中的路径必须完整引用。
2. 创建本地 `ship`、`ship_output`、`ship_review`、`logs` 和 `temp` 目录；这些目录已被 Git 忽略。
3. 只把原始 MP4 和可选的相机元数据侧车放入 `ship`。禁止把输出放回 `ship`。
4. 将 `config/autograde.example.json` 复制为 `config/autograde.json` 并填写本机路径；真实配置不会进入 Git。
5. 将 `config/source_files.example.txt` 复制为 `config/source_files.txt`，每行填写一个已批准的 MP4 文件名。不要填写路径或 XML。
6. 启动 Resolve 前设置 `FX3_AUTOGRADE_ROOT`，或修改测试、对比脚本顶部公开的 `PROJECT_ROOT` 回退值。
7. 先把三个 Lua 模板分别复制为 `scripts/*.local.lua`（本地副本已被 Git 忽略）。在本地测试和对比脚本中，把三个 `FX3_TEST_00X.MP4` 占位名替换为三条已确认素材；在本地批处理脚本中，将 `REFERENCE_TIMELINE` 改为 `CMP_<首条素材stem>_NeutralV2B`。
8. 将三个定制后的本地 Lua 文件复制到 Resolve Utility 目录；安装时可去掉文件名中的 `.local`：

   `%APPDATA%\Blackmagic Design\DaVinci Resolve\Support\Fusion\Scripts\Utility\`

9. 重启 Resolve，使脚本出现在 `工作区（Workspace）> 脚本（Scripts）` 菜单。

## 运行步骤

1. 创建或打开名为 `FX3_SLog3_AutoGrade_Test` 的独立空项目，不要使用正式制作项目。
2. 导入媒体和创建时间线之前，设置 3840×2160、Timeline Frame Rate 59.94、Playback Frame Rate 59.94，并读回确认两个帧率。
3. 运行 `Workspace > Scripts > FX3 Standard AutoGrade Test`，仅处理配置的三条测试素材。若 HEVC Main 10 显示 Media Offline 或只有声音，立即停止。
4. 人工审看三条 Standard 测试成片。
5. 运行 `FX3 Neutral Comparison` 生成 V2A/V2B 对比，并确认选定的 V2B 参考时间线恰好包含两个串行节点。
6. 明确授权后运行 `FX3 Batch V2B`。每次最多处理清单中的十条。每批结束后确认任务全绿、保存项目并核对输出帧率与时长，再运行下一批。
7. 清单全部完成后停止，不得自动扩大处理范围。

## 免费版所需最少人工操作

已经验证的免费版流程不依赖外部 Resolve API。最少人工操作包括：

- 创建或选择隔离项目；
- 导入前设置并读回分辨率和两个帧率；
- 安装脚本后重启 Resolve；
- 从 `Workspace > Scripts` 运行内部脚本；
- 目视确认首条素材可正常解码；
- 启动或监督已授权的测试/批次渲染并确认任务全绿。

脚本通过内部 `app:GetResolve()` 获取 Resolve 对象，不需要 UIManager、鼠标宏、图像识别、第三方插件或下载 LUT。

## 安全限制

- `ship` 永远只读，不移动、删除、覆盖或重命名原始 MP4/XML。
- 输出只能写入 `ship_output`，输出目录不得作为输入。
- 不覆盖已有输出；同名完整文件应验证后跳过，不完整文件使用时间戳或序号重新渲染。
- 不猜测相机或 Log 格式。无法可靠确认 Sony FX3 S-Gamut3.Cine / S-Log3 时必须停止并人工确认。
- XML 仅用于元数据确认，不作为媒体导入。
- 不安装来源不明的包、可执行文件、LUT 或插件。
- 首测最多三条；每批最多十条。
- 单条失败不得删除其他成功输出。

## 报告与隐私

只有 `examples/` 中的脱敏示例可公开。真实清单、日志、本机配置、媒体、Resolve 数据库、代理、缓存和备份均由 `.gitignore` 排除。

## 许可证

MIT，详见 [LICENSE](LICENSE)。
