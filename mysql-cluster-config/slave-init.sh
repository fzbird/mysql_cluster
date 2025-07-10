#!/bin/bash

# ========================================================================
# MySQL 从服务器初始化脚本 - 增强版
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

log_info "开始初始化 MySQL 从服务器..."

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
    
    if [ -z "$MYSQL_MASTER_HOST" ]; then
        log_warning "MYSQL_MASTER_HOST 环境变量未设置，使用默认值 'mysql-master'"
        MYSQL_SOURCE_HOST="mysql-master"
    fi
    
    if [ -z "$MYSQL_MASTER_PORT" ]; then
        log_warning "MYSQL_MASTER_PORT 环境变量未设置，使用默认值 '3306'"
        MYSQL_SOURCE_PORT="3306"
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

# 等待主服务器就绪
wait_for_master() {
    log_info "等待主服务器就绪..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if mysqladmin ping -h"${MYSQL_MASTER_HOST}" -P"${MYSQL_MASTER_PORT}" -u"root" -p"${MYSQL_ROOT_PASSWORD}" --silent 2>/dev/null; then
            log_success "主服务器已就绪"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_info "等待主服务器就绪... (尝试 $attempt/$max_attempts)"
        sleep 5
    done
    
    log_error "等待主服务器就绪超时"
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
    if [ -f "/tmp/slave-initialized" ]; then
        log_info "从服务器已经初始化过，跳过初始化步骤"
        return 0
    fi
    
    # 创建临时 SQL 文件
    local temp_sql="/tmp/slave-init-temp.sql"
    
    cat > "$temp_sql" <<-EOSQL
-- 从服务器初始化 SQL 脚本
-- 生成时间: $(date)

-- 设置 GTID 模式
SET GLOBAL enforce_gtid_consistency = ON;
SET GLOBAL gtid_mode = OFF_PERMISSIVE;
SET GLOBAL gtid_mode = ON_PERMISSIVE;
SET GLOBAL gtid_mode = ON;

-- 确保从服务器是只读的
SET GLOBAL read_only = 1;
SET GLOBAL super_read_only = 1;

-- 停止从服务器复制（如果正在运行）
STOP REPLICA;

-- 重置从服务器状态
RESET REPLICA ALL;

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

-- 插入从服务器状态记录
INSERT INTO cluster_status (server_role, status) VALUES ('slave', 'initialized')
    ON DUPLICATE KEY UPDATE status = 'initialized', last_update = CURRENT_TIMESTAMP;

-- 显示数据库信息
SHOW DATABASES;

-- 显示从服务器状态
SHOW REPLICA STATUS\G
EOSQL
    
    # 执行 SQL 文件
    if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" < "$temp_sql"; then
        log_success "SQL 初始化执行成功"
        
        # 删除临时文件
        rm -f "$temp_sql"
        
    else
        log_error "SQL 初始化执行失败"
        rm -f "$temp_sql"
        exit 1
    fi
}

# 配置主从复制
configure_replication() {
    log_info "配置主从复制..."
    
    # 检查是否已经配置过复制
    if [ -f "/tmp/slave-initialized" ]; then
        log_info "从服务器已经配置过复制，检查复制状态..."
        check_replication_status
        return 0
    fi
    
    # 创建临时 SQL 文件
    local temp_sql="/tmp/slave-replication-temp.sql"
    
    cat > "$temp_sql" <<-EOSQL
-- 配置主从复制
-- 生成时间: $(date)

-- 停止从服务器复制
STOP REPLICA;

-- 重置从服务器状态
RESET REPLICA ALL;

-- 配置主服务器连接
CHANGE REPLICATION SOURCE TO
    SOURCE_HOST='${MYSQL_MASTER_HOST}',
    SOURCE_PORT=${MYSQL_MASTER_PORT},
    SOURCE_USER='${MYSQL_REPLICATION_USER}',
    SOURCE_PASSWORD='${MYSQL_REPLICATION_PASSWORD}',
    SOURCE_AUTO_POSITION=1;

-- 启动从服务器复制
        START REPLICA;
        
        -- 显示从服务器状态
        SHOW REPLICA STATUS\G
EOSQL
    
    # 执行 SQL 文件
    if mysql -u root -p"${MYSQL_ROOT_PASSWORD}" < "$temp_sql"; then
        log_success "复制配置执行成功"
        
        # 删除临时文件
        rm -f "$temp_sql"
        
        # 创建初始化完成标记
        touch /tmp/slave-initialized
        echo "$(date): Slave initialization completed" > /tmp/slave-initialized
        
    else
        log_error "复制配置执行失败"
        rm -f "$temp_sql"
        exit 1
    fi
}

# 检查复制状态
check_replication_status() {
    log_info "检查从服务器复制状态..."
    
    # 等待复制开始
    sleep 10
    
    # 获取复制状态
    local slave_status=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW REPLICA STATUS\G" 2>/dev/null)
    
    if [ -z "$slave_status" ]; then
        log_error "无法获取从服务器状态"
        return 1
    fi
    
    # 解析复制状态
    local io_running=$(echo "$slave_status" | grep "Replica_IO_Running" | awk '{print $2}')
    local sql_running=$(echo "$slave_status" | grep "Replica_SQL_Running" | awk '{print $2}')
    local last_error=$(echo "$slave_status" | grep "Last_Error" | cut -d: -f2-)
    local seconds_behind=$(echo "$slave_status" | grep "Seconds_Behind_Source" | awk '{print $2}')
    
    log_info "从服务器复制状态："
    log_info "  IO线程运行状态: $io_running"
    log_info "  SQL线程运行状态: $sql_running"
    
    if [ "$io_running" = "Yes" ] && [ "$sql_running" = "Yes" ]; then
        log_success "✅ MySQL主从复制运行正常"
        if [ "$seconds_behind" != "NULL" ] && [ "$seconds_behind" != "0" ]; then
            log_info "  复制延迟: ${seconds_behind}秒"
        else
            log_info "  复制延迟: 0秒 (实时同步)"
        fi
        return 0
    else
        log_warning "⚠️ MySQL主从复制存在问题"
        if [ -n "$last_error" ] && [ "$last_error" != " " ]; then
            log_error "  错误信息: $last_error"
        fi
        return 1
    fi
}

# 验证从服务器配置
verify_configuration() {
    log_info "验证从服务器配置..."
    
    # 检查只读模式
    local read_only=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GLOBAL VARIABLES LIKE 'read_only';" -s -N 2>/dev/null | awk '{print $2}')
    
    if [ "$read_only" = "ON" ]; then
        log_success "只读模式已启用"
    else
        log_warning "只读模式未启用"
    fi
    
    # 检查超级只读模式
    local super_read_only=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GLOBAL VARIABLES LIKE 'super_read_only';" -s -N 2>/dev/null | awk '{print $2}')
    
    if [ "$super_read_only" = "ON" ]; then
        log_success "超级只读模式已启用"
    else
        log_warning "超级只读模式未启用"
    fi
    
    # 检查 GTID 模式
    local gtid_mode=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW GLOBAL VARIABLES LIKE 'gtid_mode';" -s -N 2>/dev/null | awk '{print $2}')
    
    if [ "$gtid_mode" = "ON" ]; then
        log_success "GTID 模式已启用"
    else
        log_error "GTID 模式未启用"
        return 1
    fi
    
    # 检查数据库
    local db_exists=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "SHOW DATABASES LIKE '${MYSQL_DATABASE}';" -s -N 2>/dev/null)
    
    if [ -n "$db_exists" ]; then
        log_success "数据库 ${MYSQL_DATABASE} 存在"
    else
        log_error "数据库 ${MYSQL_DATABASE} 不存在"
        return 1
    fi
    
    log_success "从服务器配置验证完成"
}

# 测试复制功能
test_replication() {
    log_info "测试复制功能..."
    
    # 检查复制状态
    if ! check_replication_status; then
        log_error "复制状态异常，无法进行测试"
        return 1
    fi
    
    # 在主服务器上创建测试数据
    log_info "在主服务器上创建测试数据..."
    
    if mysql -h"${MYSQL_MASTER_HOST}" -P"${MYSQL_MASTER_PORT}" -u"root" -p"${MYSQL_ROOT_PASSWORD}" -e "
        USE ${MYSQL_DATABASE};
        INSERT INTO cluster_status (server_role, status) VALUES ('test', 'replication_test')
            ON DUPLICATE KEY UPDATE status = 'replication_test', last_update = CURRENT_TIMESTAMP;
    " 2>/dev/null; then
        log_success "测试数据创建成功"
        
        # 等待复制同步
        sleep 5
        
        # 检查从服务器是否同步了数据
        local test_data=$(mysql -u root -p"${MYSQL_ROOT_PASSWORD}" -e "
            USE ${MYSQL_DATABASE};
            SELECT COUNT(*) FROM cluster_status WHERE server_role = 'test' AND status = 'replication_test';
        " -s -N 2>/dev/null)
        
        if [ "$test_data" -gt 0 ]; then
            log_success "✅ 复制功能测试通过"
            
            # 清理测试数据
            mysql -h"${MYSQL_MASTER_HOST}" -P"${MYSQL_MASTER_PORT}" -u"root" -p"${MYSQL_ROOT_PASSWORD}" -e "
                USE ${MYSQL_DATABASE};
                DELETE FROM cluster_status WHERE server_role = 'test';
            " 2>/dev/null || log_warning "清理测试数据失败"
            
            return 0
        else
            log_error "❌ 复制功能测试失败"
            return 1
        fi
    else
        log_error "无法在主服务器上创建测试数据"
        return 1
    fi
}

# 主函数
main() {
    log_info "==================== 从服务器初始化开始 ===================="
    
    # 检查是否已经初始化过
    if [ -f "/tmp/slave-initialized" ]; then
        log_info "从服务器已经初始化过"
        log_info "初始化信息: $(cat /tmp/slave-initialized)"
        check_replication_status
        log_info "==================== 从服务器初始化结束 ===================="
        return 0
    fi
    
    # 执行初始化步骤
    check_env_vars
    create_directories
    wait_for_mysql
    wait_for_master
    execute_sql_init
    configure_replication
    check_replication_status
    verify_configuration
    
    # 测试复制功能
    if test_replication; then
        log_success "从服务器初始化和复制测试全部完成！"
    else
        log_warning "从服务器初始化完成，但复制测试失败"
    fi
    
    log_info "==================== 从服务器初始化结束 ===================="
}

# 执行主函数
main "$@" 