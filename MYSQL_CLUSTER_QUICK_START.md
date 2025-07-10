# MySQL 主从复制集群 - 快速启动指南

## 🎯 一键部署

已完成 MySQL 主从复制集群的完整配置！现在可以一键启动高可用的数据库集群。

## 🚀 立即开始

### 1. 验证配置

```bash
# 验证所有配置文件
./test_cluster_config.sh
```

### 2. 启动集群

```bash
# 启动 MySQL 主从复制集群
./deploy_mysql_cluster.sh start
```

### 3. 验证状态

```bash
# 查看集群运行状态
./deploy_mysql_cluster.sh status

# 检查主从复制状态
./deploy_mysql_cluster.sh check-replication
```

## 📍 连接信息

启动成功后，可通过以下端口访问：

| 服务 | 端口 | 用途 | 连接示例 |
|------|------|------|----------|
| MySQL 主服务器 | 3306 | 写操作 | `mysql -h localhost -P 3306 -u root -p` |
| MySQL 从服务器 | 3307 | 读操作 | `mysql -h localhost -P 3307 -u root -p` |
| HAProxy 写端口 | 3308 | 负载均衡写 | `mysql -h localhost -P 3308 -u root -p` |
| HAProxy 读端口 | 3309 | 负载均衡读 | `mysql -h localhost -P 3309 -u root -p` |
| HAProxy 统计页面 | 8404 | 监控面板 | `http://localhost:8404/stats` |
| MySQL 监控指标 | 9104 | Prometheus | `http://localhost:9104/metrics` |

## 🔧 集群架构

```
应用层
  ↓
HAProxy 负载均衡 (读写分离)
  ↓                ↓
MySQL Master  →  MySQL Slave
  (写操作)      (读操作 + 副本)
```

## 🛠️ 常用命令

```bash
# 启动集群
./deploy_mysql_cluster.sh start

# 停止集群
./deploy_mysql_cluster.sh stop

# 重启集群
./deploy_mysql_cluster.sh restart

# 查看状态
./deploy_mysql_cluster.sh status

# 检查复制
./deploy_mysql_cluster.sh check-replication

# 备份数据
./deploy_mysql_cluster.sh backup

# 查看日志
./deploy_mysql_cluster.sh logs

# 实时监控
./deploy_mysql_cluster.sh monitor

# 清理资源
./deploy_mysql_cluster.sh cleanup
```

## ⚖️ 应用集成示例

### Python/FastAPI

```python
from sqlalchemy import create_engine

# 写操作数据库连接
write_engine = create_engine("mysql+pymysql://root:fzbird20250615@localhost:3308/gallerydb")

# 读操作数据库连接  
read_engine = create_engine("mysql+pymysql://root:fzbird20250615@localhost:3309/gallerydb")

# 使用示例
def create_user(user_data):
    # 写操作使用主服务器
    with write_engine.connect() as conn:
        conn.execute("INSERT INTO users ...")

def get_users():
    # 读操作使用从服务器
    with read_engine.connect() as conn:
        return conn.execute("SELECT * FROM users").fetchall()
```

### Node.js

```javascript
const mysql = require('mysql2');

// 写操作连接（主服务器）
const writeConnection = mysql.createConnection({
  host: 'localhost',
  port: 3308,
  user: 'root',
  password: 'fzbird20250615',
  database: 'gallerydb'
});

// 读操作连接（从服务器）
const readConnection = mysql.createConnection({
  host: 'localhost',
  port: 3309,
  user: 'root',
  password: 'fzbird20250615',
  database: 'gallerydb'
});

// 使用示例
function createUser(userData) {
  return writeConnection.promise().execute(
    'INSERT INTO users SET ?', userData
  );
}

function getUsers() {
  return readConnection.promise().execute(
    'SELECT * FROM users'
  );
}
```

## 🔍 监控和管理

### HAProxy 监控面板

访问：`http://localhost:8404/stats`
- 用户名：`admin`
- 密码：`admin123`

可以查看：
- 后端服务器状态
- 连接数统计
- 响应时间
- 健康检查结果

### MySQL 性能指标

访问：`http://localhost:9104/metrics`

获取 Prometheus 格式的监控指标，包括：
- 查询统计
- 连接数
- 缓冲池使用率
- 复制状态

## 🚨 故障排除

### 如果启动失败

```bash
# 查看详细日志
./deploy_mysql_cluster.sh logs

# 检查容器状态
docker ps -a

# 重新配置复制
./deploy_mysql_cluster.sh setup-replication
```

### 如果复制中断

```bash
# 检查复制状态
./deploy_mysql_cluster.sh check-replication

# 重新启动复制
./deploy_mysql_cluster.sh setup-replication
```

### 端口冲突

如果端口被占用，编辑 `mysql-cluster.env` 修改端口配置：

```bash
MYSQL_MASTER_PORT=3316
MYSQL_SLAVE_PORT=3317
MYSQL_PROXY_WRITE_PORT=3318
MYSQL_PROXY_READ_PORT=3319
```

## 💾 数据备份

### 手动备份

```bash
# 创建完整备份
./deploy_mysql_cluster.sh backup

# 备份文件位置
ls -la mysql-cluster-backups/
```

### 自动备份

集群配置了自动备份计划（每天凌晨2点），备份文件保存7天。

## 🔒 安全建议

1. **修改默认密码**：编辑 `mysql-cluster.env` 中的密码
2. **限制网络访问**：配置防火墙只允许必要的端口
3. **定期更新**：保持 Docker 镜像和系统更新
4. **监控日志**：定期检查错误日志

## 📖 详细文档

- 完整部署指南：`MYSQL_CLUSTER_README.md`
- 配置文件说明：`mysql-cluster-config/` 目录
- 管理脚本：`deploy_mysql_cluster.sh`

## ✅ 下一步

1. 启动集群：`./deploy_mysql_cluster.sh start`
2. 验证运行：`./deploy_mysql_cluster.sh status`
3. 测试连接：使用上述连接信息
4. 集成应用：参考应用集成示例
5. 配置监控：访问监控页面

---

🎉 **恭喜！** 您现在拥有了一个高可用的 MySQL 主从复制集群，支持读写分离、负载均衡和自动故障检测！ 