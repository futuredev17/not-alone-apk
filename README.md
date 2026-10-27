# 🌙 Not alone (不孤单)

> "Death only kills one of your days; anxiety kills every one of them."
> “死亡只会杀死你的一天，而焦虑会杀死你的每一天。”

An open-source emotional companion app built with Flutter and AI. Designed for those who need a quiet space to be heard.
一个基于 Flutter 与 AI 开发的开源情绪陪伴应用。为需要被倾听的灵魂提供一个安静的角落。

## ✨ Core Features / 核心功能

**AI Tree Hole**: A gentle AI listener powered by a local/cloud LLM, strictly restricted to providing emotional support only.
**AI 树洞**：接入大语言模型的温柔倾听者，严格限制为仅提供情绪安慰与共情。

**Real-time Matching**: Anonymous, dual-consent WebSocket matching. You only connect when both agree.
**真人匹配**：基于 WebSocket 的匿名双向授权匹配，只有双方都同意才会建立连接。

**Safety Guard**: Built-in risk control intercepts extreme or self-harm keywords, providing emergency hotlines.
**安全风控**：内置底层敏感词拦截与极端情绪预警，并在必要时弹出紧急心理援助热线。

**Daily Nudges**: Local notifications at 8 AM, 12 PM, 4 PM, and 8 PM with randomized comforting quotes.
**每日鼓励**：无需联网，每天 8点/12点/16点/20点 准时推送本地随机暖心话语。

**Global Context**: Supports 6 languages (ZH/EN/JA/DE/ES/FR) and multi-country holiday calendars.
**全球视野**：支持中英日德西法 6 国语言切换，日历自动适配多国节假日。

**Privacy First**: Fully anonymous, no account required, all core data stays on your device.
**隐私至上**：完全匿名，无需注册，核心数据仅保存在本地。

## 🎯 The Purpose / 开发初衷

I built this app because I know what it feels like to be alone in the dark. This is not just a project; it's a digital shelter.
我开发这个应用，是因为我深知在黑暗中独行的滋味。这不仅仅是一个项目，更是一个数字避难所。

If it can make even one person feel a little warmer, it's worth it.
如果能让哪怕一个人感到一丝温暖，它就值得存在。

## 🧑‍💻 About the Developer / 关于开发者

A 17-year-old self-taught full-stack developer from China, aiming for a DevOps career in Germany.
一个来自中国的 17 岁自学全栈开发者，目标是在德国开启 DevOps 职业生涯。

GitHub: [@futuredev17](https://github.com/futuredev17)

## 🚀 Live Demo / 在线体验

**Web Version**: [http://47.83.136.229](http://47.83.136.229)
**网页版**：[http://47.83.136.229](http://47.83.136.229)

*Note: The AI feature runs on a lightweight CPU server, so responses might be slightly delayed.*
*注：AI功能运行于轻量级CPU服务器，回复可能会有轻微延迟。*

## 🛠 Tech Stack / 技术栈

*   **Framework**: Flutter & Dart
*   **AI Engine**: Ollama (Qwen 1.5B)
*   **Server**: Dart WebSocket, Nginx (Dockerized)
*   **Cloud**: Alibaba Cloud (ECS)
*   **CI/CD**: GitHub Actions
