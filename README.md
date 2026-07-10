# WorkMemory

## 中文简介

WorkMemory 是一款 macOS 本地工作记忆应用。它把窗口、网页、输入与 OCR 采集聚合成工作会话，再将会话提炼为可检索的记忆、项目和行动项。

### 主要能力

- 今日工作会话与长期记忆分层管理
- 本地语义检索与全文检索组合的 Ask Memory，可回跳引用证据
- 项目归档、焦点置顶、AI 总结与行动项抽取
- PDF、DOCX、XLSX、PPTX、CSV、Markdown 和文本文件分块索引
- 手动导出行动项到 Apple Reminders
- 数据库迁移备份、健康状态和首次启用引导

## English Overview

WorkMemory is a local macOS work-memory app that groups captured window, web, typing, and OCR context into work sessions, then turns those sessions into searchable memories, projects, summaries, and actions.

## Requirements

- macOS 13 or later
- Xcode 15.4 or later for local builds
- An OpenAI-compatible model API key for AI summaries, action extraction, document summaries, and Ask Memory answers

## Build

```bash
swift build
swift test
./script/build_and_run.sh --dmg
```

The DMG script builds a universal release binary for Apple Silicon and Intel Macs. Set `WORKMEMORY_SIGN_IDENTITY` to override the detected signing identity.
