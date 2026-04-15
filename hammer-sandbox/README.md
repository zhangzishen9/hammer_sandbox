# 大锤sand-box 🔨 - 终极 Sing-Box 运维管理系统

> **极致纯净 · 物理旋转 · 万能订阅**

本工具基于受尊敬的开源项目 [sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 的协议逻辑进行模块化重构与功能增强。感谢原作者 yonggekkk 为社区提供的卓越贡献。

---

---

## 🚀 核心杀手锏 (The "Hammer" Features)

### 1. WARP 物理动态池 (1-10路)
不再是死板的静态 IP。大锤支持配置 1-10 路并发 WARP 出站，并支持 **定时强制旋转 (Rotation)**。每隔几分钟，大锤会自动注销并重新申请全新的 Cloudflare 账号，让您的出口 IP 永远保持“动态新鲜”。

### 2. 三合一万能订阅 (Triple-Subscription)
一次同步，全平台支持。生成的订阅包含：
*   **Mihomo (Clash Meta)**: 内置“选择代理节点”、“负载均衡”、“自动选择”组。
*   **Sing-box (SFA/SFI)**: 专用的 JSON 客户端模板。
*   **Generic Base64**: 适配小火箭/Nekobox 等所有主流软件。

### 3. 二级开关大厅 (Protocol Control Center)
拒绝繁琐。通过二级可视化菜单，您可以像拨动耳机开关一样，一键开启或关闭特定协议，无需重写任何配置。

---

## 🛠️ 安装指令 (Quick Start)

在您的 VPS 上运行以下一键脚本即可开启“大锤”时代：

```bash
# 建议在 root 用户下执行
bash <(wget -qO- https://raw.githubusercontent.com/zhangzishen9/dashui-sandbox/main/install.sh)
```

> **快捷启动提示**: 安装完成后，在任何路径输入 `sb` 或 `dc` (大锤) 即可弹出看板。

---

## 🎨 视觉哲学
我们彻底移除了冗余的 Emoji 和地球图标。采用清爽的 **工业风 TUI** 界面，为您提供最直接、最高效的运维数据展示（实时公网 IP、地区、BBR状态、各协议端口快照）。

---

## 📦 项目结构

*   `menu.sh`: 管理主看板 (快捷入口: `sb`/`dc`)
*   `protocol_manager.sh`: 协议二级开关管理
*   `warp_pool.sh`: WARP 动态账号池管理
*   `config_gen.sh`: 灵活配置生成引擎
*   `sync_gitlab.sh`: 全量订阅同步工具

---
*Powered by Hammer-Architects.*
