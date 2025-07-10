# MySQL 主从复制集群部署指南

## 🎯 概述

本文档介绍如何部署和管理高可用的 MySQL 主从复制集群，包含读写分离、负载均衡和监控功能。

## 🏗️ 架构图

```
┌─────────────────────────────────────────────────────────────┐
│                   MySQL 集群架构                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐     │
│  │   应用层    │    │   应用层    │    │   应用层    │     │
│  │  (写操作)   │    │  (读操作)   │    │  (智能路由) │     │
│  └─────┬───────┘    └─────┬───────┘    └─────┬───────┘     │
│        │                  │                  │             │
│        │ :3308           │ :3309           │ :3310        │
│        └─────────┬───────────┴─────────┬────────┘          │
│                  │                     │                   │
│              ┌───▼─────────────────────▼───┐               │
│              │      HAProxy 负载均衡器     │               │
│              │     (读写分离 + 监控)        │               │
│              └───┬─────────────────────┬───┘               │
│                  │                     │                   │
│              :3306│                 :3306│                 │
│                  │                     │                   │
│       ┌──────────▼──┐               ┌──▼──────────┐        │
│       │ MySQL Master│◄─────────────►│MySQL Slave  │        │
│       │  (主服务器) │   主从复制    │ (从服务器)  │        │
│       │   写操作    │               │   读操作    │        │
│       └─────────────┘               └─────────────┘        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## 🚀 快速开始

### 1. 启动集群

```bash
# 启动 MySQL 主从复制集群
./deploy_mysql_cluster.sh start
```

### 2. 验证状态

```bash
# 查看集群状态
./deploy_mysql_cluster.sh status

# 检查复制状态
./deploy_mysql_cluster.sh check-replication
```

### 3. 连接测试

```bash
# 连接主服务器（写操作）
mysql -h localhost -P 3306 -u root -p

# 连接从服务器（读操作）
mysql -h localhost -P 3307 -u root -p

# 通过负载均衡器连接
mysql -h localhost -P 3308 -u root -p  # 写操作
mysql -h localhost -P 3309 -u root -p  # 读操作
```

## 📋 详细配置

### 核心组件

| 组件 | 容器名 | 端口 | 说明 |
|------|--------|------|------|
| MySQL 主服务器 | `mysql_master` | 3306 | 处理写操作和数据同步 |
| MySQL 从服务器 | `mysql_slave` | 3307 | 处理读操作，数据副本 |
| HAProxy 负载均衡 | `mysql_proxy` | 3308/3309 | 读写分离和负载均衡 |
| 监控服务 | `mysql_monitor` | 9104 | 性能监控和指标收集 |

### 端口映射

```bash
# 直接连接
localhost:3306  → MySQL 主服务器
localhost:3307  → MySQL 从服务器

# 负载均衡连接
localhost:3308  → 写操作（指向主服务器）
localhost:3309  → 读操作（指向从服务器）

# 监控页面
localhost:8404  → HAProxy 统计页面
localhost:9104  → MySQL 监控指标
```

### 环境变量配置

编辑 `mysql-cluster.env` 文件自定义配置：

```bash
# 基本配置
MYSQL_ROOT_PASSWORD=your_password
MYSQL_DATABASE=your_database

# 复制配置
MYSQL_REPLICATION_USER=replicator
MYSQL_REPLICATION_PASSWORD=repl_password

# 端口配置
MYSQL_MASTER_PORT=3306
MYSQL_SLAVE_PORT=3307
```

## 🔧 管理命令

### 基础操作

```bash
# 启动集群
./deploy_mysql_cluster.sh start

# 停止集群
./deploy_mysql_cluster.sh stop

# 重启集群
./deploy_mysql_cluster.sh restart

# 查看状态
./deploy_mysql_cluster.sh status
```

### 复制管理

```bash
# 配置主从复制
./deploy_mysql_cluster.sh setup-replication

# 检查复制状态
./deploy_mysql_cluster.sh check-replication

# 故障转移（手动）
./deploy_mysql_cluster.sh failover
```

### 维护操作

```bash
# 备份数据
./deploy_mysql_cluster.sh backup

# 查看日志
./deploy_mysql_cluster.sh logs

# 实时监控
./deploy_mysql_cluster.sh monitor

# 清理资源
./deploy_mysql_cluster.sh cleanup
```

## 📊 监控和管理

### HAProxy 统计页面

访问 `http://localhost:8404/stats` 查看负载均衡状态：

- 用户名: `admin`
- 密码: `admin123`

### MySQL 监控指标

访问 `http://localhost:9104/metrics` 获取 Prometheus 格式的监控指标。

### 健康检查

```bash
# 检查容器状态
docker ps | grep mysql

# 检查主从复制延迟
./deploy_mysql_cluster.sh check-replication

# 查看性能指标
docker stats mysql_master mysql_slave
```

## 💾 数据备份和恢复

### 自动备份

集群会自动创建备份，存储在 `mysql-cluster-backups/` 目录：

```bash
# 手动备份
./deploy_mysql_cluster.sh backup

# 查看备份文件
ls -la mysql-cluster-backups/
```

### 数据恢复

```bash
# 从备份文件恢复
docker exec -i mysql_master mysql -u root -p your_database < backup_file.sql
```

## ⚖️ 读写分离配置

### 应用层配置

在应用中配置不同的数据库连接：

```python
# Python 示例
# 写操作连接
WRITE_DB_URL = "mysql+pymysql://root:password@localhost:3308/gallerydb"

# 读操作连接
READ_DB_URL = "mysql+pymysql://gallery_reader:password@localhost:3309/gallerydb"
```

```javascript
// Node.js 示例
const writeConnection = mysql.createConnection({
  host: 'localhost',
  port: 3308,
  user: 'gallery_writer',
  password: 'password',
  database: 'gallerydb'
});

const readConnection = mysql.createConnection({
  host: 'localhost',
  port: 3309,
  user: 'gallery_reader',
  password: 'password',
  database: 'gallerydb'
});
```

### 用户权限

集群自动创建以下用户：

| 用户 | 权限 | 用途 |
|------|------|------|
| `root` | 全部权限 | 管理用户 |
| `replicator` | 复制权限 | 主从复制 |
| `gallery_writer` | 读写权限 | 应用写操作 |
| `gallery_reader` | 只读权限 | 应用读操作 |
| `monitor` | 监控权限 | 性能监控 |

## 🚨 故障处理

### 常见问题

#### 1. 复制中断

```bash
# 检查复制状态
./deploy_mysql_cluster.sh check-replication

# 重新配置复制
./deploy_mysql_cluster.sh setup-replication
```

#### 2. 主服务器故障

```bash
# 查看容器状态
docker ps -a

# 查看日志
./deploy_mysql_cluster.sh logs

# 重启容器
docker restart mysql_master
```

#### 3. 从服务器延迟

```bash
# 检查复制延迟
./deploy_mysql_cluster.sh check-replication

# 查看从服务器日志
docker logs mysql_slave
```

### 紧急恢复

如果主服务器完全失效：

1. 停止复制：`docker exec mysql_slave mysql -u root -p -e "STOP SLAVE;"`
2. 提升从服务器为主服务器：`docker exec mysql_slave mysql -u root -p -e "RESET SLAVE ALL;"`
3. 修改应用配置指向新的主服务器
4. 启动新的从服务器

## 🔒 安全配置

### 密码管理

- 定期更换数据库密码
- 使用强密码策略
- 限制网络访问

### 网络安全

```bash
# 仅允许本地访问
iptables -A INPUT -p tcp --dport 3306 -s localhost -j ACCEPT
iptables -A INPUT -p tcp --dport 3306 -j DROP
```

### SSL 配置

可以在 `mysql-cluster.env` 中启用 SSL：

```bash
MYSQL_ENABLE_SSL=true
MYSQL_SSL_CERT_PATH=/path/to/cert.pem
MYSQL_SSL_KEY_PATH=/path/to/key.pem
```

## 📈 性能调优

### 内存配置

在 `mysql-cluster.env` 中调整内存设置：

```bash
MYSQL_INNODB_BUFFER_POOL_SIZE=512M
MYSQL_MAX_CONNECTIONS=2000
```

### 连接优化

```bash
# 监控连接数
docker exec mysql_master mysql -u root -p -e "SHOW STATUS LIKE 'Threads_connected';"

# 查看慢查询
docker exec mysql_master mysql -u root -p -e "SHOW STATUS LIKE 'Slow_queries';"
```

## 🛠️ 扩展配置

### 添加更多从服务器

1. 复制从服务器配置
2. 修改 `server-id`
3. 添加到 `docker-compose.mysql-cluster.yml`
4. 配置 HAProxy 后端

### 集成到现有项目

1. 修改应用的数据库连接配置
2. 实现读写分离逻辑
3. 添加健康检查和故障转移

## 📞 支持和维护

### 日志位置

- 容器日志: `docker logs <container_name>`
- MySQL 日志: `mysql-cluster-logs/`
- HAProxy 日志: 通过 `docker logs mysql_proxy`

### 性能监控

- HAProxy 统计: http://localhost:8404/stats
- MySQL 指标: http://localhost:9104/metrics
- 系统监控: `docker stats`

### 版本升级

1. 备份当前数据
2. 停止集群
3. 更新镜像版本
4. 重新启动集群
5. 验证功能正常

---

**注意**: 此集群配置适用于中小型应用。生产环境请根据实际需求调整配置参数。 