# 提示词优化助手｜先优化，你确认，再执行

先把需求变成清晰可执行的提示词，由用户审核后再执行。适合希望减少歧义、无关搜索、冗长输出和重复确认的人。

**流程：新需求 → 优化提示词 → 用户审核 → 确认执行。**

技能运行只需文本指令，无须 API Key，无个人信息或固定电脑路径；另附一键安装脚本。可用于支持 SKILL.md 的代理；具体加载方式由宿主决定。

## 一键安装到 Codex

适用于 **macOS、Linux 和 Windows WSL**，需要 Bash 和 curl。先安装 Codex，再在系统终端复制执行：

```bash
curl -fsSL https://raw.githubusercontent.com/tghappy155-sudo/prompt-review-gate/main/install.sh | bash
```

安装后在 Codex 输入 `$prompt-review-gate` 调用。脚本只安装技能，默认不修改全局规则。

**希望每个新需求先优化、确认后再执行**，使用下面这一条：

```bash
curl -fsSL https://raw.githubusercontent.com/tghappy155-sudo/prompt-review-gate/main/install.sh | bash -s -- --enable-default
```

第二条会备份已有全局规则，并追加一个带标记的前置规则；重复安装只更新同一个规则块。支持 `CODEX_HOME`，已有非空 `AGENTS.override.md` 时使用该文件。技能默认安装到 `~/.agents/skills/prompt-review-gate/`；已有符号链接时更新其实际目录并保留链接。

- 已有同名技能会先备份到 Codex 配置目录下的 `backups/prompt-review-gate/`，避免被当成另一份技能加载。
- 不需要管理员权限，不改动模型、密钥或 `config.toml`。
- 下载或来源校验失败时，不覆盖已有技能。
- 若技能未显示或全局规则未加载，请重启 Codex。项目规则可能影响全局偏好，这不是绝对优先级开关。

### 本地安装与自定义位置

也可先查看 [安装脚本](install.sh)，下载仓库后执行：

```bash
bash install.sh --source-dir . --enable-default
```

`--source-dir` 指向包含 `SKILL.md` 和 `agents/` 的目录。通过 `bash install.sh --help` 查看自定义技能目录与 Codex 配置目录参数。Windows 原生 PowerShell 暂无对应安装脚本，请使用 WSL 或手动安装。

### 手动安装

下载 ZIP 并解压，将 `SKILL.md` 和 `agents/` 放入 `~/.agents/skills/prompt-review-gate/`。希望默认触发时，可按 [全局规则示例](docs/GLOBAL-INSTRUCTIONS.md) 追加设置。安装本身不保证每条消息都自动调用。

## 使用

```text
使用 $prompt-review-gate 优化下面的需求，先给我审核：
从指定网页提取课程数据，填入我提供的表格。
```

技能会输出一个提示词，缺失的来源、表格或字段标记“待提供”，不先抓取数据。

| 回复 | 行为 |
| --- | --- |
| 执行／确认执行／按这版做 | 执行最近展示的版本 |
| 改成…… | 修订后重新展示待审核 |
| 仅复制／只要提示词 | 只交付提示词 |
| 本次跳过优化 | 直接处理本次原需求 |
| 关闭此流程 | 按用户指示停用；持久停用还需移除全局前置规则 |

已批准任务的补充信息、进度查询和继续执行不会重新进入审核。

## 手机端

- **最直接的方式：** 打开 [手机可复制规则](docs/MOBILE-PROMPT.md)，复制到手机聊天或项目指令中。当前聊天规则只作用于该聊天；项目指令只作用于对应项目。
- **手机远程连接电脑：** 任务仍由所连接的电脑执行，使用的是该环境中的配置。需按产品支持完成连接，并验证规则确实加载。
- **原生安装：** 本仓库是独立技能，未打包或发布为 ChatGPT 插件。上传到 GitHub不等于自动安装到手机，不保证手机存在“粘贴 GitHub 链接即可安装”的入口。

## 设计边界

优化提高可执行性，不只是压缩原话；保留必要细节与验证。无固定耗时或加速比例承诺，不改变模型推理档位。审核发生在消息进入模型之后，不是输入框发送前拦截。不会自动向其他聊天或模型发送内容。

## 文件

- `SKILL.md`：核心流程。
- `install.sh`：一键安装、旧版备份与可选默认前置规则。
- `tests/test_install.py`：隔离目录中的安装验证，不改动真实用户配置。
- `agents/openai.yaml`：Codex 显示信息与自动选择设置。
- `docs/GLOBAL-INSTRUCTIONS.md`：可选的全局前置规则。
- `docs/MOBILE-PROMPT.md`：手机端可复制版本。

## 安装验证

开发者可运行 `python3 tests/test_install.py`，验证首次安装、旧版备份、规则保留、重复安装、覆盖规则、符号链接与失败保护。测试使用临时目录。

## 官方参考

- [技能格式、加载及平台支持](https://learn.chatgpt.com/docs/build-skills)
- [AGENTS.md 全局与项目规则](https://learn.chatgpt.com/docs/agent-configuration/agents-md)
- [手机端 Codex](https://learn.chatgpt.com/docs/mobile)

产品能力会变化，以官方文档和你的实际界面为准。
