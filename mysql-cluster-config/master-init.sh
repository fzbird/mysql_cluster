#!/bin/bash

# ========================================================================
# MySQL 主服务器初始化脚本 - 增强版
# ========================================================================

set -e

# 日志函数
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $1"
}

log_warning() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
}

# 错误处理函数
handle_error() {
    local exit_code=$?
    local line_number=$1
    log_error "脚本在第 $line_number 行发生错误，退出码: $exit_code"
    exit $exit_code
}

# 设置错误处理
trap 'handle_error $LINENO' ERR

log_info "开始初始化 MySQL 主服务器..."

# 检查必要的环境变量
check_env_vars() {
    log_info "检查环境变量..."
    
    if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
        log_error "MYSQL_ROOT_PASSWORD 环境变量未设置"
        exit 1
    fi
    
    if [ -z "$MYSQL_DATABASE" ]; then
        log_warning "MYSQL_DATABASE 环境变量未设置，使用默认值 'gallerydb'"
        MYSQL_DATABASE="gallerydb"
    fi
    
    if [ -z "$MYSQL_REPLICATION_USER" ]; then
        log_warning "MYSQL_REPLICATION_USER 环境变量未设置，使用默认值 'replicator'"
        MYSQL_REPLICATION_USER="replicator"
    fi
    
    if [ -z "$MYSQL_REPLICATION_PASSWORD" ]; then
        log_warning "MYSQL_REPLICATION_PASSWORD 环境变量未设置，使用默认值 'repl_password_2024'"
        MYSQL_REPLICATION_PASSWORD="repl_password_2024"
    fi
    
    log_success "环境变量检查完成"
}

# 等待 MySQL 服务启动
wait_for_mysql() {
    log_info "等待 MySQL 服务启动..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if mysqladmin ping -h"localhost" -u"root" -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
            log_success "MySQL 服务已启动"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_info "等待 MySQL 启动... (尝试 $attempt/$max_attempts)"
        sleep 2
    done
    
    log_error "等待 MySQL 启动超时"
    exit 1
}

# 创建必要的目录
create_directories() {
    log_info "创建必要的目录..."
    
    # 创建日志目录
    mkdir -p /var/log/mysql
    
    # 确保 mysql 用户拥有目录权限
    if id "mysql" &>/dev/null; then
        chown -R mysql:mysql /var/log/mysql
    else
        log_warning "mysql 用户不存在，跳过权限设置"
    fi
    
    # 创建数据目录（如果不存在）
    mkdir -p /var/lib/mysql
    
    log_success "目录创建完成"
}

# 执行 SQL 初始化
execute_sql_init() {
    log_info "执行 SQL 初始化..."
    
    # 检查是否已经初始化过
    if [ -f "/tmp/master-initialized" ]; then
        log_info "主服务器已经初始化过，跳过初始化步骤"
        return 0
    fi
    
    # 创建临时 SQL 文件
    local temp_sql="/tmp/master-init-temp.sql"
    
    cat > "$temp_sql" <<-EOSQL
-- 主服务器初始化 SQL 脚本
-- 生成时间: $(date)

-- 设置 GTID 模式
SET GLOBAL enforce_gtid_consistency = ON;
SET GLOBAL gtid_mode = OFF_PERMISSIVE;
SET GLOBAL gtid_mode = ON_PERMISSIVE;
SET GLOBAL gtid_mode = ON;

-- 创建复制用户
DROP USER IF EXISTS '${MYSQL_REPLICATION_USER}'@'%';
CREATE USER '${MYSQL_REPLICATION_USER}'@'%' IDENTIFIED WITH mysql_native_password BY '${MYSQL_REPLICATION_PASSWORD}';
GRANT REPLICATION SLAVE ON *.* TO '${MYSQL_REPLICATION_USER}'@'%';

-- 创建监控用户
DROP USER IF EXISTS 'monitor'@'%';
CREATE USER 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'monitor_password_2024';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'monitor'@'%';

-- 创建应用只读用户（用于从服务器）
DROP USER IF EXISTS 'gallery_reader'@'%';
CREATE USER 'gallery_reader'@'%' IDENTIFIED WITH mysql_native_password BY 'reader_password_2024';
GRANT SELECT ON ${MYSQL_DATABASE}.* TO 'gallery_reader'@'%';

-- 创建应用读写用户（用于主服务器）
DROP USER IF EXISTS 'gallery_writer'@'%';
CREATE USER 'gallery_writer'@'%' IDENTIFIED WITH mysql_native_password BY 'writer_password_2024';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX ON ${MYSQL_DATABASE}.* TO 'gallery_writer'@'%';

-- 创建数据库管理员用户
DROP USER IF EXISTS 'gallery_admin'@'%';
CREATE USER 'gallery_admin'@'%' IDENTIFIED WITH mysql_native_password BY 'admin_password_2024';
GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO 'gallery_admin'@'%';

-- 刷新权限
FLUSH PRIVILEGES;

-- 启用二进制日志
FLUSH BINARY LOGS;

-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS ${MYSQL_DATABASE} 
    CHARACTER SET utf8mb4 
    COLLATE utf8mb4_unicode_ci;

-- 使用新创建的数据库
USE ${MYSQL_DATABASE};

-- 创建示例表（可选，用于测试）
CREATE TABLE IF NOT EXISTS cluster_status (
    id INT AUTO_INCREMENT PRIMARY KEY,
    server_role VARCHAR(50) NOT NULL,
    status VARCHAR(50) NOT NULL,
    last_update TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_server_role (server_role)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 插入主服务器状态记录
INSERT INTO cluster_status (server_role, status) VALUES ('master', 'initialized')
    ON DUPLICATE KEY UPDATE status = 'initialized', last_update = CURRENT_TIMESTAMP;

-- 显示创建的用户
SELECT user, host FROM mysql.user WHERE user IN ('${MYSQL_REPLICATION_USER}', 'monitor', 'gallery_reader', 'gallery_writer', 'gallery_admin');

-- 显示数据库信息
SHOW DATABASES;

-- 显示主服务器状态
SHOW MASTER STATUS;
EOSQL
    
    # 执行 SQL 文件
    if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" < "$temp_sql"; then
        log_success "SQL 初始化执行成功"
        
        # 删除临时文件
        rm -f "$temp_sql"
        
        # 创建初始化完成标记
        touch /tmp/master-initialized
        echo "$(date): Master initialization completed" > /tmp/master-initialized
        
    else
        log_error "SQL 初始化执行失败"
        rm -f "$temp_sql"
        exit 1
    fi
}

# 显示主服务器状态
show_master_status() {
    log_info "显示主服务器状态..."
    
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW MASTER STATUS;" 2>/dev/null || {
        log_error "无法获取主服务器状态"
        return 1
    }
    
    log_info "显示 GTID 状态..."
    mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GLOBAL VARIABLES LIKE 'gtid%';" 2>/dev/null || {
        log_warning "无法获取 GTID 状态"
    }
}

# 验证配置
verify_configuration() {
    log_info "验证主服务器配置..."
    
    # 检查二进制日志是否启用
    local binlog_status=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GLOBAL VARIABLES LIKE 'log_bin';" -s -N 2>/dev/null | awk '{print $2}')
    
    if [ "$binlog_status" = "ON" ]; then
        log_success "二进制日志已启用"
    else
        log_error "二进制日志未启用"
        return 1
    fi
    
    # 检查 GTID 模式
    local gtid_mode=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GLOBAL VARIABLES LIKE 'gtid_mode';" -s -N 2>/dev/null | awk '{print $2}')
    
    if [ "$gtid_mode" = "ON" ]; then
        log_success "GTID 模式已启用"
    else
        log_error "GTID 模式未启用"
        return 1
    fi
    
    # 检查复制用户
    local repl_user_count=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT COUNT(*) FROM mysql.user WHERE user='${MYSQL_REPLICATION_USER}';" -s -N 2>/dev/null)
    
    if [ "$repl_user_count" -gt 0 ]; then
        log_success "复制用户创建成功"
    else
        log_error "复制用户创建失败"
        return 1
    fi
    
    # 检查数据库
    local db_exists=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES LIKE '${MYSQL_DATABASE}';" -s -N 2>/dev/null)
    
    if [ -n "$db_exists" ]; then
        log_success "数据库 ${MYSQL_DATABASE} 创建成功"
    else
        log_error "数据库 ${MYSQL_DATABASE} 创建失败"
        return 1
    fi
    
    log_success "主服务器配置验证完成"
}

# 主函数
main() {
    log_info "==================== 主服务器初始化开始 ===================="
    
    # 检查是否已经初始化过
    if [ -f "/tmp/master-initialized" ]; then
        log_info "主服务器已经初始化过"
        log_info "初始化信息: $(cat /tmp/master-initialized)"
        show_master_status
        log_info "==================== 主服务器初始化结束 ===================="
        return 0
    fi
    
    # 执行初始化步骤
    check_env_vars
    create_directories
    wait_for_mysql
    execute_sql_init
    show_master_status
    verify_configuration
    
    log_success "主服务器初始化完成！"
    log_info "==================== 主服务器初始化结束 ===================="
}

# 执行主函数
main "$@" 