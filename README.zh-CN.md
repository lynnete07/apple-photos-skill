# Apple Photos Codex Skill

[English](README.md)

这是一个带安全门禁的 Apple Photos skill，适合希望整理大型照片库、但不想反复做大量细碎决定的人。

它按年度分析照片库，根据时间与拍摄频次划分复核批次，复用已有相册，创建经过覆盖校验的年度兜底相册，把“收藏”作为中性的临时标记，导出未修改原件，通过 SHA-256 比对归档，并且只执行用户明确确认的删除方案。

## 适合哪些用户

- Apple Photos 中积累了多年、大量照片与视频的人。
- 喜欢明确规则、固定步骤和可预测结果的人，包括神经多样性用户，以及容易产生决策疲劳的人。
- 使用外置盘或其他位置保存长期主归档，需要安全导出与比对的人。
- 希望通过 Codex 自动化 Photos，但不允许工具直接修改 Photos 私有数据库的人。

## 它解决什么问题

常见照片整理会不断重复这些微小决策：识别批次、建立相册、判断收藏的含义、导出、比对、删除、再次检查。本 skill 将这些动作拆开：

1. **分析**：根据时间和拍摄频次识别候选批次，不修改 Photos。
2. **隔离**：建立互不重叠的临时相册，并创建覆盖全年剩余内容的兜底相册。
3. **标记**：把收藏作为中性标记，用来临时选择任意子集。
4. **决策**：明确记录保留、导出、删除、合并或结束批次等动作。
5. **执行**：将已确认动作合并预检，重新核对数量，一次执行并复核结果。

## 核心能力

- 指令中的“照片”默认包括静态照片、视频和 Live Photo。
- 已有相册完整覆盖批次时直接复用，避免重复建相册。
- 通过年度兜底相册确保全年内容零遗漏。
- 导出未修改原始资源，保留照片和视频中的原始元数据。
- Live Photo 默认导出静态原片与动态资源；仅在用户明确选择时只导出静态图片。
- 收藏只是标记，不自动等于保留或删除。
- 删除前重新读取相册当前内容和精确数量。
- 公共版默认保留 Photos 来源、本地来源、RAW 文件，并关闭云端备份。
- 仅使用 Apple 公开 PhotoKit API，不读取或修改 Photos 私有数据库。

## 环境要求

- 安装 Apple Photos 的 macOS。
- Xcode Command Line Tools，能够使用 `xcrun` 和 Swift 编译器。
- Python 3。
- Codex 或其他支持 skill 的 Agent。
- macOS 弹出权限请求时，允许访问完整照片图库。

所有处理均在本机运行。本 skill 不会自行上传照片或元数据。

## 安装

```bash
git clone https://github.com/lynnete07/apple-photos-skill.git
mkdir -p ~/.codex/skills
cp -R apple-photos-skill/apple-photos ~/.codex/skills/
cd ~/.codex/skills/apple-photos
bash scripts/install.sh
scripts/apple-photos status
```

安装完成后重启 Codex，使其发现新 skill。

## 推荐用自然语言开始

大多数用户无需直接编写命令，可以这样对 Codex 说：

```text
使用 $apple-photos 分析我 2024 年的所有照片和视频。本轮只分析，不创建或删除任何内容。
```

```text
使用 $apple-photos 按已确认方案创建 2024 年复核批次，并创建一个兜底相册，承载所有未进入批次且未被已有相册覆盖的 2024 年内容。
```

```text
使用 $apple-photos 删除相册【2024-08-24_待复核】中未收藏的内容，保留相册，并确认收藏内容没有受到影响。
```

```text
使用 $apple-photos 将相册【2024-10-03_香港】的未修改原件导出到 /Volumes/Archive/Photos。Live Photo 导出完整原始资源，不删除任何内容。
```

## 命令行入口

Agent 会使用这些内置命令：

```bash
bash scripts/install.sh
scripts/apple-photos status
scripts/apple-photos inspect --album "相册名称"
scripts/apple-photos scan --start "2024-01-01" --end "2025-01-01" --gap-hours 36
scripts/apple-photos validate-manifest --manifest /绝对路径/plan.json
scripts/apple-photos batch --manifest /绝对路径/plan.json
scripts/apple-photos batch --manifest /绝对路径/plan.json --apply
```

`batch` 只做预检；`batch --apply` 会在修改 Photos 前再次执行全部安全检查。

## 公共版安全默认值

| 设置 | 默认值 |
|---|---|
| 导出后的 Photos 原资产 | 保留 |
| 电脑或外置盘来源 | 保留 |
| RAW 文件 | 归档并保留 |
| Live Photo | 导出原始静态图片与配对动态资源 |
| 云端备份 | 关闭 |
| 归档路径 | 不预设，必须由用户配置 |

这些设置可以修改，但配置文件只是工作流默认值，不能代替本次破坏性操作的明确授权。

## 重要安全规则

- 删除 Photos 资产会从图库全局删除，不只是移出当前相册。
- 删除内容会进入“最近删除”。恢复资产不会自动恢复已经删除的相册结构。
- 相册名称必须唯一匹配。
- 数量发生变化、权限被拒绝、iCloud 原件下载失败、相册重名或复核失败时，操作立即停止。
- 导出和删除可以放入同一个方案，只有选中原件全部导出并验证后才会进入删除阶段。

第一次执行删除前，请阅读[安全模型](docs/SAFETY.zh-CN.md)。

## 仓库结构

```text
apple-photos-skill/
├── apple-photos/          # 安装时完整复制这个 skill 文件夹
│   ├── SKILL.md
│   ├── agents/
│   ├── references/
│   └── scripts/
├── docs/                  # 面向用户的安全说明
└── tests/                 # 公开验证样例与测试
```

安装或转发时，请保持 `apple-photos` 文件夹的目录结构不变。

## 能力边界

- 本 skill 处理 PhotoKit 能访问的系统照片图库。
- 仅存在于 iCloud 的原件必须能够下载，导出才能完成。
- Finder 创建时间不是拍摄时间。本 skill 保留原文件内嵌元数据，并单独报告 Photos 显示的拍摄日期。
- 归档比对默认包含 RAW 在内的所有格式；只有用户明确要求时才忽略某种后缀。
- 本 skill 不根据画面擅自推断人物、事件或旅行名称，只根据时间、频次、位置和设备连续性提出批次建议。

## 贡献与安全问题

参见 [CONTRIBUTING.md](CONTRIBUTING.md) 和 [SECURITY.md](SECURITY.md)。请勿在 issue 或测试文件中提交真实照片库标识、个人绝对路径或私人元数据。

## 许可证

[MIT](LICENSE)
