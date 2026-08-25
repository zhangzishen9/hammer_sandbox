# 大锤sand-box 🔨 - 终极 Sing-Box 运维管理系统

> **极致纯净 · 物理旋转 · 万能订阅**

本工具基于受尊敬的开源项目 [sing-box-yg](https://github.com/yonggekkk/sing-box-yg) 的协议逻辑进行模块化重构与功能增强。感谢原作者 yonggekkk 为社区提供的卓越贡献。

---

---

## 🚀 核心杀手锏 (The "Hammer" Features)

### 1. WARP 内部动态出口池
大锤支持服务端内部 WARP 出口池及定时旋转。WARP 仅用于域名分流或统一出口，不再为每一路 WARP 创建、开放或发布独立公网代理节点。

### 2. Clash 独立订阅
每个订阅拥有独立凭据、端口、协议组合、配额和到期时间，并通过机器 IP 直接分发给 Clash Verge/Mihomo 客户端。

### 3. 二级开关大厅 (Protocol Control Center)
拒绝繁琐。通过二级可视化菜单，您可以像拨动耳机开关一样，一键开启或关闭特定协议，无需重写任何配置。

### 4. 独立 Token 订阅分发
可为不同使用者创建独立订阅 Token 和代理凭据，分别配置协议组合、流量配额、重置日和到期时间。每台 VPS 会通过 `http://机器IP:16000/sub/随机Token` 直接提供订阅，无需 GitLab 或域名。所有用户共享五个主协议端口，由 Sing-Box V2Ray API 按凭据独立计量；超额、到期或停用后会撤销对应用户凭据。

---

## 🛠️ 安装指令 (Quick Start)

在您的 VPS 上运行以下一键脚本即可开启“大锤”时代：

```bash
# 建议在 root 用户下执行
bash <(wget -qO- https://raw.githubusercontent.com/zhangzishen9/hammer_sandbox/main/hammer-sandbox/install.sh)
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
*   `subscription_server.sh`: 独立订阅的本机管理入口
*   `subscription_manager.py`: 独立凭据、流量计量和订阅分发服务

---
*Powered by Hammer-Architects.*
