# CodexUsager v1.0.0

> 发布正文草稿。正式 DMG 尚未完成签名、公证和安装验证；通过 [发布门槛](RELEASE.md) 后再用于 GitHub Release。

CodexUsager 是一个原生 macOS AI Coding 用量伴侣，在本机汇总 Codex 和 Claude Code 的额度与使用情况。

## 功能

- Codex 和 Claude Code 数据来源；显示可用的实时额度和重置倒计时。
- Token、Session、Project 与 Model 统计，以及额度历史和使用趋势。
- macOS 菜单栏与 Small / Medium Widget。
- 本地用量修正、手动记录和 CSV / JSON 导出。

额度取决于来源实际提供的数据；来源未提供时，应用不会按套餐猜测额度。

## 隐私

CodexUsager 采用 local-first 方式处理用量数据，不保存 Prompt、AI 回复或登录凭据。详细说明见仓库中的 [PRIVACY.md](https://github.com/koajsj/codexusager/blob/main/docs/PRIVACY.md)。

## 系统要求

- macOS Sonoma 14.6 或更新版本。
- Apple Silicon 或 Intel Mac。
- 使用对应功能时，需在本机安装并登录 Codex 或 Claude Code。

## 安装

1. 下载 `CodexUsager-1.0.0.dmg`。
2. 打开 DMG，将 `CodexUsager.app` 拖入 `Applications`。
3. 首次启动时按 macOS 的安全提示完成打开操作。

可使用随附的 `CodexUsager-1.0.0.dmg.sha256` 校验下载文件。
