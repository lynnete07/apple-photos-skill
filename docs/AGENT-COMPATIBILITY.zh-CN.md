# Agent 兼容性

可安装单位是完整的 `apple-photos/` 文件夹。它遵循[开放的 Agent Skills 结构](https://agentskills.io/home)：必需的 `SKILL.md`，以及可选的脚本、参考资料和客户端适配文件。

## 共同运行条件

无论使用哪个 Agent，都必须满足：

- 在安装 Apple Photos 的 macOS 本机运行；
- 能执行 `bash`、Python 3、`xcrun` 和 Swift 编译器；
- 获得 macOS 的完整照片图库权限；
- 保持 skill 文件夹结构不变；
- 将 `SKILL.md` 视为唯一权威工作契约；
- 破坏性 manifest 必须先 dry-run，并在 apply 前取得本轮明确授权。

纯云端 Agent 不能直接操作用户本机的 Photos 图库。它必须连接到用户信任、且已经获得图库权限的 macOS 执行环境。

## Codex

```bash
mkdir -p ~/.codex/skills
cp -R apple-photos ~/.codex/skills/
cd ~/.codex/skills/apple-photos
bash scripts/install.sh
```

重启 Codex 后，可使用 `$apple-photos` 或与 skill 描述匹配的自然语言指令。

## Claude Code

个人安装：

```bash
mkdir -p ~/.claude/skills
cp -R apple-photos ~/.claude/skills/
cd ~/.claude/skills/apple-photos
bash scripts/install.sh
```

仅供单个项目使用时，安装到 `.claude/skills/apple-photos/`。使用 `/apple-photos` 或自然语言调用。Claude Code 可直接读取开放标准的 `SKILL.md`，不依赖 OpenAI 适配文件。参见官方 [Claude Code Skills 文档](https://code.claude.com/docs/en/skills)。

## WorkBuddy

下载 Release ZIP，在 **添加 Skill → 上传 Skill** 中选择本地 skill 包。WorkBuddy 会在安装前执行自己的安全检查。安装并启用后，可从 Skills 页面、输入 `/apple-photos`，或直接通过匹配的自然语言请求调用。参见官方 [WorkBuddy Skills 文档](https://www.workbuddy.ai/docs/workbuddy/From-Beginner-to-Expert-Guide/Function-Description/Skills)。

该安装包包含能够访问本机 Photos 图库的可执行脚本。安装前应审阅源码，并保持破坏性权限为保守状态；仅在 WorkBuddy 执行预期 PhotoKit 桥接程序时授予 Photos 权限。

## 其他兼容 Agent Skills 的客户端

将完整文件夹安装到该客户端文档规定的 skill 目录。如果客户端只能读取 prompt 文件，可以让它读取 `SKILL.md`；但要真正执行 Photos 操作，它仍必须具备本机终端执行能力和 macOS Photos 权限。

客户端专属元数据都是可选适配层，不得覆盖 `SKILL.md` 中的安全门禁。
