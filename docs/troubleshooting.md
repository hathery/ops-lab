# 踩坑与排障记录

按实际遇到的时间顺序整理。每条记录：**现象 → 原因 → 解决 → 经验**。

---

## 1. 学生机默认镜像不是 Ubuntu

**现象**：下单页镜像默认显示 `Alibaba Cloud Linux 3.2104 LTS 64位`，很容易直接下单。

**原因**：阿里云自研发行版是默认选项，出于成本考虑放在第一位。

**解决**：镜像处切到「操作系统」→ 选 `Ubuntu 22.04 64位`。

**经验**：Alibaba Cloud Linux 用 `yum`/`dnf`，Ubuntu 用 `apt`。两者包管理、服务路径、默认配置都不同，混用会让所有教程失效。**买之前一定确认镜像。**

---

## 2. 带宽选 0 Mbps → 没有公网 IP

**现象**：付款成功，但实例只有内网 IP `172.31.x.x`，`ssh` 直接 `Connection timed out`。

**原因**：购买页带宽默认 `0 Mbps`，"按使用流量"计费下 0 表示不分配公网 IP。

**解决**：带宽改为 `5 Mbps`（按使用流量，无预付费用），或购买后到控制台「修改带宽」。

**经验**：云服务器的"公网 IP"和"带宽"是绑定的，**没有带宽就没有公网 IP**。付款页那句小字提示别跳过。

---

## 3. 安全组默认不放通 80 / 443

**现象**：Nginx 已启动，`curl 127.0.0.1` 返回 200，但浏览器打不开公网 IP。

**原因**：新建实例的默认安全组只放通了 `22`、`3389`、`ICMP`。

**解决**：安全组入方向添加 `80/80` 和 `443/443`，授权对象 `0.0.0.0/0`。

**经验**：排查顺序固定为 **进程 → 本机端口 → 防火墙 → 安全组 → 公网链路**，一层层往外，不要跳步。

---

## 4. 3389 端口对公网开放毫无意义

**现象**：默认安全组里有 `RDP(3389)` 放通 `0.0.0.0/0`。

**原因**：安全组是通用模板，同时适配 Windows 和 Linux 实例。

**解决**：删除该规则。Ubuntu 上不存在远程桌面服务。

**经验**：**最小权限原则** —— 不放通任何用不到的服务端口。同理，`3306`(MySQL)、`6379`(Redis) 绝不能对 `0.0.0.0/0` 开放，暴露后通常在数小时内被自动化脚本攻破。

---

## 5. 容器刚启动时 curl 返回空

**现象**：`docker compose up -d` 后立刻 `curl 127.0.0.1:8080`，没有任何输出。

**原因**：`docker compose ps` 显示 `Up Less than a second`，nginx 进程尚未开始监听端口。

**解决**：等待 1–2 秒后重试，或用循环探测：

```bash
for i in $(seq 1 10); do
    curl -sf http://127.0.0.1:8080 >/dev/null && break
    sleep 1
done
```

**经验**：**容器 Up ≠ 服务就绪**。生产环境要靠健康检查（healthcheck）判断，而不是容器状态。

---

## 6. Docker Hub 拉镜像超时

**现象**：`docker run hello-world` 卡在 `Pulling from library/hello-world` 不动。

**原因**：Docker Hub 在国内访问受限。

**解决**：配置阿里云专属镜像加速器（控制台 → 容器镜像服务 → 镜像工具 → 镜像加速器）：

```bash
mkdir -p /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{
  "registry-mirrors": ["https://<你的专属地址>.mirror.aliyuncs.com"]
}
EOF
systemctl daemon-reload && systemctl restart docker
docker info | grep -A 2 "Registry Mirrors"
```

**经验**：`daemon.json` 是 Docker 守护进程的配置入口，改完必须 `daemon-reload` + `restart`。改错会导致 Docker 起不来，**改之前先备份**。

---

## 7. Nginx 默认站点抢占 80 端口

**现象**：配好反向代理后，浏览器打开还是 "Welcome to nginx!"。

**原因**：`/etc/nginx/sites-enabled/default` 仍然存在，它的 `default_server` 优先级更高。

**解决**：

```bash
rm -f /etc/nginx/sites-enabled/default
ln -sf /etc/nginx/sites-available/myweb /etc/nginx/sites-enabled/myweb
nginx -t && systemctl reload nginx
```

**经验**：`nginx -t` 必须在 `reload` 之前跑。配置语法错时 reload 会让**整个站点直接下线**。

---

## 8. SSH 断开后误在本地 PowerShell 执行 Linux 命令

**现象**：提示符变成 `PS C:\Users\Administrator>`，执行 `ln`、`nginx -t` 全部报"无法识别为 cmdlet"。

**原因**：SSH 会话已断开，命令全部落在了本地 Windows 上。

**解决**：重新 `ssh root@<IP>` 连回服务器。

**经验**：**粘贴命令前先看提示符**。`root@hostname:~#` 才是服务器，`PS C:\...>` 是本机。另外这些命令在 Windows 上不存在，只是报错，**不会破坏服务器**，不用慌。

长期方案：用 `tmux` 保持会话，断线后 `tmux attach` 即可恢复现场。

---

## 9. heredoc 粘贴中断，卡在 `>` 提示符

**现象**：粘贴多行 `cat > file <<'EOF'` 时中途断开，终端停在 `>` 等待输入。

**原因**：heredoc 需要读到结束标记 `EOF` 才结束，缺了就一直在等待。

**解决**：单独输入一行 `EOF` 回车，即可结束。

**经验**：`>` 是**续行提示符**，不是报错。卡住时先看提示符是不是 `>`，再决定输入 `EOF` 还是 `Ctrl+C`。

---

## 10. 备份脚本只跑不验

**现象**：脚本执行成功，日志显示"备份完成"。

**风险**：备份文件可能因为磁盘满、权限错误等原因损坏，但日志看不出来。

**解决**：每次交付前验证归档可读：

```bash
tar -tzf /opt/backup/myweb_*.tar.gz | head
```

**经验**：**未经恢复验证的备份等于没有备份。** 定期做一次完整恢复演练，比备份本身更重要。
