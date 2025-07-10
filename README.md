# MySQL 主从集群服务

## 概述

这个目录包含 MySQL 主从复制集群的完整配置和管理工具。该集群提供高可用性、读写分离和自动故障转移功能。

## 目录结构

```
mysql_cluster/
├── docker-compose.mysql-cluster.yml    # 主从集群 Docker Compose 配置
├── mysql-cluster.env                   # 集群环境变量配置
├── deploy_mysql_cluster.sh            # 集群部署和管理脚本
├── test_cluster_config.sh             # 集群配置验证脚本
├── MYSQL_CLUSTER_README.md            # 详细技术文档
├── MYSQL_CLUSTER_QUICK_START.md       # 快速开始指南
├── mysql-cluster-config/               # MySQL 配置文件目录
│   ├── master.cnf                     # 主库配置
│   ├── slave.cnf                      # 从库配置
│   ├── haproxy.cfg                    # 负载均衡配置
│   ├── init-master.sql                # 主库初始化脚本
│   ├── init-slave.sql                 # 从库初始化脚本
│   ├── master-init.sh                 # 主库启动脚本
│   └── slave-init.sh                  # 从库启动脚本
├── mysql-cluster-logs/                # 集群日志目录
└── mysql-cluster-data/                # 集群数据目录
```

## 快速开始

### 1. 启动集群

```bash
# 启动 MySQL 主从集群
./deploy_mysql_cluster.sh start

# 查看集群状态
./deploy_mysql_cluster.sh status
```

### 2. 验证集群

```bash
# 验证集群配置
./test_cluster_config.sh
```

### 3. 访问服务

- **主库（写）**: localhost:3306
- **从库（读）**: localhost:3307  
- **负载均衡器**: localhost:3308 (读写分离)
- **负载均衡器（只读）**: localhost:3309 (只读)
- **HAProxy 统计**: http://localhost:8404
- **监控指标**: http://localhost:9104/metrics

## 管理命令

```bash
# 集群管理
./deploy_mysql_cluster.sh start          # 启动集群
./deploy_mysql_cluster.sh stop           # 停止集群
./deploy_mysql_cluster.sh restart        # 重启集群
./deploy_mysql_cluster.sh status         # 查看状态

# 备份和监控
./deploy_mysql_cluster.sh backup         # 备份数据
./deploy_mysql_cluster.sh monitor        # 查看监控信息
./deploy_mysql_cluster.sh logs           # 查看日志

# 故障处理
./deploy_mysql_cluster.sh failover       # 手动故障转移
./deploy_mysql_cluster.sh repair         # 修复集群
```

## 连接配置

### 读写分离连接
```python
# 写操作连接主库
WRITE_DB_URL = "mysql+pymysql://root:cluster_root_pass@localhost:3306/your_db"

# 读操作连接从库
READ_DB_URL = "mysql+pymysql://root:cluster_root_pass@localhost:3307/your_db"

# 负载均衡连接（推荐）
CLUSTER_DB_URL = "mysql+pymysql://root:cluster_root_pass@localhost:3308/your_db"
```

## 特性

- ✅ **主从复制**: 自动数据同步
- ✅ **读写分离**: 优化性能和负载分布  
- ✅ **高可用性**: 自动故障检测和转移
- ✅ **负载均衡**: HAProxy 提供智能路由
- ✅ **监控和日志**: 完整的性能监控
- ✅ **自动备份**: 定期数据备份
- ✅ **健康检查**: 实时状态监控

## 网络配置

- **网络名称**: `mysql-cluster-network`
- **子网**: `172.24.0.0/16`
- **主库 IP**: `172.24.0.10`
- **从库 IP**: `172.24.0.11`
- **HAProxy IP**: `172.24.0.12`

## 数据卷

- `mysql_master_data` - 主库数据持久化
- `mysql_slave_data` - 从库数据持久化
- `mysql_cluster_logs` - 集群日志存储

## 安全配置

### 默认密码
- **Root 密码**: `cluster_root_pass`
- **复制用户**: `replication_user` / `replication_pass`

⚠️ **重要**: 生产环境请修改 `mysql-cluster.env` 中的默认密码。

## 故障排除

### 常见问题
1. **主从同步失败**: 检查网络连接和复制用户权限
2. **HAProxy 连接失败**: 验证后端服务器状态
3. **监控数据缺失**: 检查 MySQL Exporter 配置

### 诊断命令
```bash
# 检查复制状态
docker exec mysql_master mysql -u root -p -e "SHOW MASTER STATUS;"
docker exec mysql_slave mysql -u root -p -e "SHOW SLAVE STATUS\G;"

# 检查 HAProxy 状态
docker exec haproxy cat /var/log/haproxy.log

# 查看集群网络
docker network inspect mysql-cluster-network
```

## 文档

- **MYSQL_CLUSTER_README.md** - 完整技术文档
- **MYSQL_CLUSTER_QUICK_START.md** - 快速开始指南

## 支持

如需帮助，请：
1. 查看详细文档
2. 检查服务日志
3. 运行配置验证脚本

---

**注意**: 此集群适用于生产环境，但建议在部署前进行充分测试。 