# ops-lab

运维方向的学习与实践记录。所有内容都部署在真实云服务器上，可在线访问。

**线上地址：<http://39.107.154.203>**

---

## 这个仓库是什么

一台从零搭建的云服务器，以及围绕它做的运维实践：

- 手工初始化系统（时区、swap、基础安全）
- 用 Docker Compose 部署 Web 服务
- 宿主机 Nginx 反向代理，作为唯一公网入口
- 用 Shell 脚本 + crontab 实现每日自动备份与过期清理

## 架构

```
浏览器 ──:80──▶ 宿主机 Nginx（反向代理，透传 X-Forwarded-For）
                     │
                     ▼
              127.0.0.1:8080（仅绑定回环，不对外暴露）
                     │
              Docker 容器 nginx:alpine
                     │ 只读挂载
                 ./html
```

备份链路：

```
cron(0 3 * * *) ──▶ /opt/scripts/backup.sh ──▶ /opt/backup/*.tar.gz（保留 7 天）
```

## 环境

| 组件 | 版本 / 规格 |
| --- | --- |
| 云服务器 | 阿里云 ECS · 华北2（北京）· 2 vCPU / 2 GiB |
| 操作系统 | Ubuntu 22.04.5 LTS（内核 5.15） |
| Docker | 29.9.3 |
| Docker Compose | v5.7.1 |
| Nginx | Ubuntu 官方包 |

## 目录结构

```
.
├── README.md
├── web/
│   ├── docker-compose.yml      # 容器编排
│   ├── html/
│   │   └── index.html          # 站点页面
│   └── nginx/
│       └── myweb.conf          # 宿主机 Nginx 站点配置
├── scripts/
│   └── backup.sh               # 备份脚本
└── docs/
    └── troubleshooting.md      # 踩坑与排障记录
```

## 关键设计取舍

| 决策 | 原因 |
| --- | --- |
| 容器端口绑定 `127.0.0.1:8080` | 只允许本机访问，公网流量必须经 Nginx，减少攻击面 |
| 宿主机 Nginx 做反向代理 | 便于统一处理 TLS、限流、访问日志；容器可随时替换而不影响入口 |
| `volumes: :ro` 只读挂载 | 容器即使被攻破也改不了宿主机文件 |
| `restart: always` | 服务器或 Docker 重启后服务自动恢复 |
| 备份保留 7 天 | 覆盖一周内的误操作，又不至于占满磁盘（40 GiB） |
| 安全组只开 22 / 80 / 443 | 数据库等端口绝不对公网开放，避免被自动化脚本爆破 |

## 部署步骤（可复现）

```bash
# 1. 系统初始化
timedatectl set-timezone Asia/Shanghai
fallocate -l 2G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab

# 2. 启动容器
cd /opt/myweb && docker compose up -d

# 3. 配置 Nginx 反向代理
ln -sf /etc/nginx/sites-available/myweb /etc/nginx/sites-enabled/myweb
nginx -t && systemctl reload nginx

# 4. 备份脚本
chmod +x /opt/scripts/backup.sh
/opt/scripts/backup.sh
```

## 验证

```bash
# 容器状态
docker compose -f /opt/myweb/docker-compose.yml ps

# 服务可达性
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1

# 备份结果
cat /var/log/myweb-backup.log
tar -tzf /opt/backup/myweb_*.tar.gz | head

# 定时任务
crontab -l
```

## 待办

- [ ] 配置 HTTPS（需要域名 + ICP 备案）
- [ ] 接入 Prometheus + Grafana 监控
- [ ] SSH 改为密钥登录并禁用密码认证
