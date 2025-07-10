#!/bin/bash

# ========================================================================
# MySQL 主从复制集群管理脚本 - 跨平台交互式版本
# ========================================================================
# 
# 支持系统: Windows (Git Bash/WSL), Linux, macOS
# 此脚本用于管理 MySQL 主从复制集群，提供完整的集群生命周期管理
# 
# 使用方法:
#   ./deploy_mysql_cluster.sh                  - 启动交互式菜单
#   ./deploy_mysql_cluster.sh [command]        - 直接执行命令
#
# 支持命令:
#   start, stop, restart, status, setup-replication, check-replication
#   failover, backup, cleanup, logs, monitor, interactive
#
# ========================================================================

set -e

# 版本信息
SCRIPT_VERSION="2.0.0"
SCRIPT_NAME="MySQL Cluster Manager"

# 平台检测变量
PLATFORM=""
IS_WINDOWS=false
IS_LINUX=false
IS_MACOS=false
DOCKER_COMPOSE_CMD=""

# 颜色输出函数
print_info() {
    echo -e "\033[1;34m[INFO]\033[0m $1"
}

print_success() {
    echo -e "\033[1;32m[SUCCESS]\033[0m $1"
}

print_warning() {
    echo -e "\033[1;33m[WARNING]\033[0m $1"
}

print_error() {
    echo -e "\033[1;31m[ERROR]\033[0m $1"
}

print_separator() {
    echo "=================================================================="
}

print_title() {
    echo ""
    print_separator
    echo -e "\033[1;36m$1\033[0m"
    print_separator
}

# 平台检测函数
detect_platform() {
    case "$(uname -s)" in
        Linux*)
            PLATFORM="Linux"
            IS_LINUX=true
            ;;
        Darwin*)
            PLATFORM="macOS"
            IS_MACOS=true
            ;;
        CYGWIN*|MINGW*|MSYS*)
            PLATFORM="Windows"
            IS_WINDOWS=true
            ;;
        *)
            PLATFORM="Unknown"
            print_warning "未知的操作系统平台: $(uname -s)"
            ;;
    esac
    
    print_info "检测到操作系统: $PLATFORM"
}

# 检测 Docker Compose 命令
detect_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
    else
        print_error "未找到 Docker Compose 命令"
        return 1
    fi
    
    print_info "使用 Docker Compose 命令: $DOCKER_COMPOSE_CMD"
}

# 路径标准化函数（Windows兼容）
normalize_path() {
    local path="$1"
    
    if [ "$IS_WINDOWS" = true ]; then
        # Windows 路径处理
        path=$(echo "$path" | sed 's|\\|/|g')
        # 处理盘符
        if [[ "$path" =~ ^[A-Za-z]: ]]; then
            path="/${path:0:1}${path:2}"
        fi
    fi
    
    echo "$path"
}

# 配置变量
COMPOSE_FILE="docker-compose.mysql-cluster.yml"
ENV_FILE="mysql-cluster.env"
CLUSTER_NETWORK="mysql-cluster-network"
MASTER_CONTAINER="mysql_master"
SLAVE_CONTAINER="mysql_slave"
PROXY_CONTAINER="mysql_proxy"
MONITOR_CONTAINER="mysql_monitor"

# 检查系统要求
check_requirements() {
    print_info "检查系统要求..."
    
    # 检查 Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker 未安装或不在 PATH 中"
        print_info "请访问 https://docs.docker.com/get-docker/ 安装 Docker"
        return 1
    fi
    
    # 检查 Docker Compose
    if ! detect_docker_compose; then
        print_error "Docker Compose 未安装或不在 PATH 中"
        print_info "请访问 https://docs.docker.com/compose/install/ 安装 Docker Compose"
        return 1
    fi
    
    # 检查配置文件
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "找不到配置文件: $COMPOSE_FILE"
        return 1
    fi
    
    # 检查 Docker 服务状态
    if ! docker info &> /dev/null; then
        print_error "Docker 服务未运行，请启动 Docker 服务"
        return 1
    fi
    
    print_success "系统要求检查通过"
    return 0
}

# 显示系统信息
show_system_info() {
    print_title "系统信息"
    echo "操作系统: $PLATFORM"
    echo "Docker 版本: $(docker --version)"
    echo "Docker Compose: $DOCKER_COMPOSE_CMD"
    echo "脚本版本: $SCRIPT_VERSION"
    echo "工作目录: $(pwd)"
    echo ""
}

# 初始化集群环境
init_cluster() {
    print_info "初始化MySQL集群环境..."
    
    # 创建必要的目录
    local dirs=(
        "mysql-cluster-data/master"
        "mysql-cluster-data/slave"
        "mysql-cluster-logs/master"
        "mysql-cluster-logs/slave"
        "mysql-cluster-config"
        "mysql-cluster-backups"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            print_info "创建目录: $dir"
            mkdir -p "$dir"
        fi
    done
    
    # 设置目录权限（仅在 Linux/macOS 上）
    if [ "$IS_LINUX" = true ] || [ "$IS_MACOS" = true ]; then
        chmod 755 mysql-cluster-data mysql-cluster-logs mysql-cluster-config mysql-cluster-backups
        find mysql-cluster-data mysql-cluster-logs -type d -exec chmod 755 {} \;
    fi
    
    # 设置脚本执行权限
    local scripts=(
        "mysql-cluster-config/master-init.sh"
        "mysql-cluster-config/slave-init.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            chmod +x "$script"
        fi
    done
    
    # 网络由 Docker Compose 自动管理，无需手动创建
    print_info "网络将由 Docker Compose 自动管理"
    
    print_success "集群环境初始化完成"
}

# 等待容器就绪
wait_for_container() {
    local container_name="$1"
    local max_wait="${2:-120}"
    local wait_count=0
    
    print_info "等待容器 $container_name 就绪..."
    
    while [ $wait_count -lt $max_wait ]; do
        if docker ps | grep -q "$container_name"; then
            local health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container_name" 2>/dev/null || echo "unknown")
            if [ "$health_status" = "healthy" ] || [ "$health_status" = "unknown" ]; then
                print_success "容器 $container_name 已就绪"
                return 0
            fi
        fi
        sleep 2
        wait_count=$((wait_count + 2))
        echo -n "."
    done
    
    echo ""
    print_error "等待容器 $container_name 就绪超时"
    return 1
}

# 启动集群
start_cluster() {
    print_title "启动 MySQL 主从复制集群"
    
    if ! check_requirements; then
        return 1
    fi
    
    init_cluster
    
    # 检查容器是否已在运行
    if docker ps | grep -q "$MASTER_CONTAINER\|$SLAVE_CONTAINER"; then
        print_warning "集群容器已在运行"
        show_cluster_status
        return 0
    fi
    
    # 启动集群
    print_info "启动集群容器..."
    if [ -f "$ENV_FILE" ]; then
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d
    else
        $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" up -d
    fi
    
    # 等待容器启动
    if wait_for_container "$MASTER_CONTAINER" 120 && wait_for_container "$SLAVE_CONTAINER" 120; then
        print_success "MySQL集群启动成功！"
        
        # 等待初始化完成
        print_info "等待集群初始化完成..."
        sleep 20
        
        # 检查复制状态
        if check_replication_status; then
            print_success "集群复制配置正常"
        else
            print_warning "集群复制可能需要手动配置"
            print_info "您可以运行: $0 setup-replication"
        fi
        
        show_cluster_status
        show_connection_info
    else
        print_error "MySQL集群启动失败"
        show_cluster_logs
        return 1
    fi
}

# 停止集群
stop_cluster() {
    print_title "停止 MySQL 主从复制集群"
    
    if ! docker ps | grep -q "$MASTER_CONTAINER\|$SLAVE_CONTAINER"; then
        print_warning "集群容器未在运行"
        return 0
    fi
    
    print_info "停止集群容器..."
    $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down
    print_success "MySQL集群已停止"
}

# 重启集群
restart_cluster() {
    print_title "重启 MySQL 主从复制集群"
    
    stop_cluster
    sleep 5
    start_cluster
}

# 配置主从复制
setup_replication() {
    print_title "配置 MySQL 主从复制"
    
    if ! docker ps | grep -q "$MASTER_CONTAINER\|$SLAVE_CONTAINER"; then
        print_error "集群容器未运行，请先启动集群"
        return 1
    fi
    
    # 等待容器完全启动
    print_info "等待容器就绪..."
    if ! wait_for_container "$MASTER_CONTAINER" 60 || ! wait_for_container "$SLAVE_CONTAINER" 60; then
        print_error "容器未就绪，无法配置复制"
        return 1
    fi
    
    # 获取环境变量
    local root_password repl_user repl_password
    
    if [ -f "$ENV_FILE" ]; then
        root_password=$(grep "^MYSQL_ROOT_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
        repl_user=$(grep "^MYSQL_REPLICATION_USER=" "$ENV_FILE" | cut -d'=' -f2)
        repl_password=$(grep "^MYSQL_REPLICATION_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    fi
    
    root_password="${root_password:-fzbird20250615}"
    repl_user="${repl_user:-replicator}"
    repl_password="${repl_password:-repl_password_2024}"
    
    print_info "配置从服务器复制..."
    
    # 在从服务器上执行复制配置
    if docker exec -i "$SLAVE_CONTAINER" mysql -u root -p"$root_password" <<-EOSQL
        STOP SLAVE;
        RESET SLAVE ALL;
        CHANGE REPLICATION SOURCE TO
            SOURCE_HOST='mysql-master',
            SOURCE_PORT=3306,
            SOURCE_USER='$repl_user',
            SOURCE_PASSWORD='$repl_password',
            SOURCE_AUTO_POSITION=1;
        START SLAVE;
EOSQL
    then
        print_success "复制配置完成"
        sleep 10
        check_replication_status
    else
        print_error "复制配置失败"
        return 1
    fi
}

# 检查复制状态
check_replication_status() {
    print_title "检查 MySQL 主从复制状态"
    
    if ! docker ps | grep -q "$SLAVE_CONTAINER"; then
        print_error "从服务器容器未运行"
        return 1
    fi
    
    # 获取root密码
    local root_password
    if [ -f "$ENV_FILE" ]; then
        root_password=$(grep "^MYSQL_ROOT_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    fi
    root_password="${root_password:-fzbird20250615}"
    
    # 检查从服务器状态
    print_info "从服务器复制状态："
    local slave_status
    if slave_status=$(docker exec "$SLAVE_CONTAINER" mysql -u root -p"$root_password" -e "SHOW REPLICA STATUS\G" 2>/dev/null); then
        local io_running=$(echo "$slave_status" | grep "Replica_IO_Running" | awk '{print $2}')
        local sql_running=$(echo "$slave_status" | grep "Replica_SQL_Running" | awk '{print $2}')
        local last_error=$(echo "$slave_status" | grep "Last_Error" | cut -d: -f2-)
        local seconds_behind=$(echo "$slave_status" | grep "Seconds_Behind_Source" | awk '{print $2}')
        
        echo "  IO线程运行状态: $io_running"
        echo "  SQL线程运行状态: $sql_running"
        
        if [ "$io_running" = "Yes" ] && [ "$sql_running" = "Yes" ]; then
            print_success "✅ MySQL主从复制运行正常"
            if [ "$seconds_behind" != "NULL" ] && [ "$seconds_behind" != "0" ]; then
                echo "  复制延迟: ${seconds_behind}秒"
            else
                echo "  复制延迟: 0秒 (实时同步)"
            fi
            return 0
        else
            print_warning "⚠️ MySQL主从复制存在问题"
            if [ -n "$last_error" ] && [ "$last_error" != " " ]; then
                echo "  错误信息: $last_error"
            fi
            return 1
        fi
    else
        print_error "无法获取从服务器状态"
        return 1
    fi
}

# 显示集群状态
show_cluster_status() {
    print_title "MySQL 集群状态"
    
    # 容器状态
    local containers=("$MASTER_CONTAINER:MySQL主服务器" "$SLAVE_CONTAINER:MySQL从服务器" "$PROXY_CONTAINER:HAProxy负载均衡器" "$MONITOR_CONTAINER:MySQL监控服务")
    
    print_info "容器运行状态："
    for container_info in "${containers[@]}"; do
        local container_name=$(echo "$container_info" | cut -d':' -f1)
        local container_desc=$(echo "$container_info" | cut -d':' -f2)
        
        if docker ps | grep -q "$container_name"; then
            print_success "✅ $container_desc: 运行中"
        else
            print_warning "❌ $container_desc: 未运行"
        fi
    done
    
    # 网络状态
    echo ""
    if docker network ls | grep -q "$CLUSTER_NETWORK"; then
        print_success "✅ 集群网络: $CLUSTER_NETWORK 存在"
    else
        print_warning "❌ 集群网络: $CLUSTER_NETWORK 不存在"
    fi
    
    # 详细容器信息
    echo ""
    print_info "容器详细状态："
    docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" | grep -E "(mysql|haproxy|monitor)" | head -20 || echo "没有找到相关容器"
}

# 显示连接信息
show_connection_info() {
    print_title "MySQL 集群连接信息"
    
    local master_port slave_port proxy_write_port proxy_read_port stats_port monitor_port
    
    if [ -f "$ENV_FILE" ]; then
        master_port=$(grep "^MYSQL_SOURCE_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        slave_port=$(grep "^MYSQL_SLAVE_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        proxy_write_port=$(grep "^MYSQL_PROXY_WRITE_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        proxy_read_port=$(grep "^MYSQL_PROXY_READ_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        stats_port=$(grep "^MYSQL_PROXY_STATS_PORT=" "$ENV_FILE" | cut -d'=' -f2)
        monitor_port=$(grep "^MYSQL_MONITOR_PORT=" "$ENV_FILE" | cut -d'=' -f2)
    fi
    
    master_port="${master_port:-3306}"
    slave_port="${slave_port:-3307}"
    proxy_write_port="${proxy_write_port:-3308}"
    proxy_read_port="${proxy_read_port:-3309}"
    stats_port="${stats_port:-8404}"
    monitor_port="${monitor_port:-9104}"
    
    echo "📍 直接连接:"
    echo "  主服务器 (写操作): localhost:$master_port"
    echo "  从服务器 (读操作): localhost:$slave_port"
    echo ""
    echo "⚖️ 负载均衡连接:"
    echo "  写操作端口: localhost:$proxy_write_port"
    echo "  读操作端口: localhost:$proxy_read_port"
    echo ""
    echo "📊 监控和管理:"
    echo "  HAProxy统计页面: http://localhost:$stats_port/stats"
    echo "  MySQL监控指标: http://localhost:$monitor_port/metrics"
    echo ""
    echo "🔑 连接示例:"
    echo "  写操作: mysql -h localhost -P $master_port -u root -p"
    echo "  读操作: mysql -h localhost -P $slave_port -u root -p"
    echo "  应用连接(写): mysql+pymysql://root:password@localhost:$proxy_write_port/gallerydb"
    echo "  应用连接(读): mysql+pymysql://gallery_reader:password@localhost:$proxy_read_port/gallerydb"
}

# 显示集群日志
show_cluster_logs() {
    print_title "MySQL 集群日志"
    
    echo "请选择要查看的服务日志："
    echo "1. MySQL主服务器"
    echo "2. MySQL从服务器"
    echo "3. HAProxy负载均衡器"
    echo "4. MySQL监控服务"
    echo "5. 所有服务"
    echo "0. 返回主菜单"
    echo ""
    
    local choice
    read -p "请选择 (0-5): " choice
    
    case "$choice" in
        1)
            print_info "显示MySQL主服务器日志..."
            docker logs --tail=100 -f "$MASTER_CONTAINER" 2>/dev/null || echo "找不到主服务器容器"
            ;;
        2)
            print_info "显示MySQL从服务器日志..."
            docker logs --tail=100 -f "$SLAVE_CONTAINER" 2>/dev/null || echo "找不到从服务器容器"
            ;;
        3)
            print_info "显示HAProxy负载均衡器日志..."
            docker logs --tail=100 -f "$PROXY_CONTAINER" 2>/dev/null || echo "找不到负载均衡器容器"
            ;;
        4)
            print_info "显示MySQL监控服务日志..."
            docker logs --tail=100 -f "$MONITOR_CONTAINER" 2>/dev/null || echo "找不到监控服务容器"
            ;;
        5)
            print_info "显示所有服务日志..."
            $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" logs --tail=50 -f
            ;;
        0)
            return 0
            ;;
        *)
            print_error "无效选择"
            return 1
            ;;
    esac
}

# 备份集群数据
backup_cluster() {
    print_title "备份 MySQL 集群数据"
    
    if ! docker ps | grep -q "$MASTER_CONTAINER"; then
        print_error "主服务器容器未运行，无法备份"
        return 1
    fi
    
    local backup_dir="mysql-cluster-backups"
    local backup_file="cluster_backup_$(date +%Y%m%d_%H%M%S).sql"
    
    mkdir -p "$backup_dir"
    
    print_info "开始备份到: $backup_dir/$backup_file"
    
    # 获取配置
    local mysql_password mysql_db
    if [ -f "$ENV_FILE" ]; then
        mysql_password=$(grep "^MYSQL_ROOT_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
        mysql_db=$(grep "^MYSQL_DATABASE=" "$ENV_FILE" | cut -d'=' -f2)
    fi
    
    mysql_password="${mysql_password:-fzbird20250615}"
    mysql_db="${mysql_db:-gallerydb}"
    
    if docker exec "$MASTER_CONTAINER" mysqldump -u root -p"$mysql_password" \
        --single-transaction --routines --triggers --events \
        --add-drop-database --databases "$mysql_db" > "$backup_dir/$backup_file"; then
        print_success "集群数据备份完成: $backup_dir/$backup_file"
        ls -lh "$backup_dir/$backup_file" 2>/dev/null || echo "备份文件大小: $(stat -c%s "$backup_dir/$backup_file" 2>/dev/null || echo "未知") 字节"
    else
        print_error "集群数据备份失败"
        return 1
    fi
}

# 故障转移
failover() {
    print_title "MySQL 集群故障转移"
    
    print_warning "⚠️ 故障转移是一个危险操作，请确保您了解其后果"
    echo "此操作将："
    echo "1. 停止从服务器复制"
    echo "2. 将从服务器切换为主服务器"
    echo "3. 需要手动更新应用配置"
    echo ""
    
    local confirm
    read -p "确认执行故障转移？(输入 'YES' 确认): " confirm
    
    if [ "$confirm" != "YES" ]; then
        print_info "故障转移已取消"
        return 0
    fi
    
    print_info "开始故障转移操作..."
    
    # 获取root密码
    local root_password
    if [ -f "$ENV_FILE" ]; then
        root_password=$(grep "^MYSQL_ROOT_PASSWORD=" "$ENV_FILE" | cut -d'=' -f2)
    fi
    root_password="${root_password:-fzbird20250615}"
    
    # 在从服务器上执行故障转移
    if docker exec -i "$SLAVE_CONTAINER" mysql -u root -p"$root_password" <<-EOSQL
        STOP SLAVE;
        RESET SLAVE ALL;
        SET GLOBAL read_only = 0;
        SET GLOBAL super_read_only = 0;
        FLUSH PRIVILEGES;
EOSQL
    then
        print_success "故障转移完成"
        print_warning "请更新应用配置，将写操作指向从服务器端口"
        print_info "新的主服务器: localhost:$(grep "^MYSQL_SLAVE_PORT=" "$ENV_FILE" | cut -d'=' -f2 || echo "3307")"
    else
        print_error "故障转移失败"
        return 1
    fi
}

# 监控集群状态
monitor_cluster() {
    print_title "MySQL 集群实时监控"
    
    print_info "按 Ctrl+C 退出监控模式"
    echo ""
    
    while true; do
        # 清屏（跨平台兼容）
        if command -v clear &> /dev/null; then
            clear
        elif command -v cls &> /dev/null; then
            cls
        else
            printf '\033[2J\033[H'
        fi
        
        echo "🔍 MySQL集群实时监控 (按Ctrl+C退出)"
        echo "更新时间: $(date)"
        echo ""
        
        show_cluster_status
        
        if docker ps | grep -q "$SLAVE_CONTAINER"; then
            echo ""
            if ! check_replication_status; then
                print_warning "复制状态异常，建议检查配置"
            fi
        fi
        
        echo ""
        echo "下次更新: 10秒后..."
        sleep 10
    done
}

# 清理集群资源
cleanup_cluster() {
    print_title "清理 MySQL 集群资源"
    
    print_warning "⚠️ 这将删除所有集群容器、网络和镜像"
    echo "数据文件将会保留，除非您选择删除"
    echo ""
    
    local confirm
    read -p "确认清理集群资源？(输入 'YES' 确认): " confirm
    
    if [ "$confirm" != "YES" ]; then
        print_info "清理操作已取消"
        return 0
    fi
    
    # 停止集群
    print_info "停止集群..."
    stop_cluster
    
    # 删除容器、网络和镜像
    print_info "清理容器和镜像..."
    $DOCKER_COMPOSE_CMD -f "$COMPOSE_FILE" down --rmi all --volumes --remove-orphans
    
    # 清理网络
    print_info "清理网络..."
    docker network rm "$CLUSTER_NETWORK" 2>/dev/null || true
    
    # 询问是否删除数据目录
    echo ""
    local delete_data
    read -p "是否删除数据目录？(输入 'YES' 确认): " delete_data
    if [ "$delete_data" = "YES" ]; then
        print_warning "删除数据目录..."
        rm -rf mysql-cluster-data mysql-cluster-logs
        print_success "数据目录已删除"
    else
        print_info "数据目录已保留"
    fi
    
    print_success "集群资源清理完成"
}

# 显示帮助信息
show_help() {
    print_title "$SCRIPT_NAME v$SCRIPT_VERSION"
    echo "MySQL 主从复制集群管理脚本"
    echo ""
    echo "使用方法:"
    echo "  $0                          启动交互式菜单"
    echo "  $0 [命令]                   直接执行命令"
    echo ""
    echo "可用命令:"
    echo "  start                       启动MySQL集群"
    echo "  stop                        停止MySQL集群"
    echo "  restart                     重启MySQL集群"
    echo "  status                      查看集群状态"
    echo "  setup-replication          配置主从复制"
    echo "  check-replication          检查复制状态"
    echo "  failover                    手动故障转移"
    echo "  backup                      备份集群数据"
    echo "  logs                        查看集群日志"
    echo "  monitor                     监控集群状态"
    echo "  cleanup                     清理集群资源"
    echo "  help                        显示帮助信息"
    echo "  interactive                 启动交互式菜单"
    echo ""
    echo "系统信息:"
    echo "  平台: $PLATFORM"
    echo "  Docker: $(docker --version 2>/dev/null || echo "未安装")"
    echo "  Docker Compose: $DOCKER_COMPOSE_CMD"
    echo ""
}

# 交互式主菜单
interactive_menu() {
    while true; do
        # 清屏
        if command -v clear &> /dev/null; then
            clear
        elif command -v cls &> /dev/null; then
            cls
        else
            printf '\033[2J\033[H'
        fi
        
        print_title "$SCRIPT_NAME v$SCRIPT_VERSION"
        echo "MySQL 主从复制集群管理 - 交互式菜单"
        echo ""
        echo "系统信息: $PLATFORM | Docker Compose: $DOCKER_COMPOSE_CMD"
        echo ""
        echo "请选择操作:"
        echo "  1. 启动集群"
        echo "  2. 停止集群"
        echo "  3. 重启集群"
        echo "  4. 查看集群状态"
        echo "  5. 配置主从复制"
        echo "  6. 检查复制状态"
        echo "  7. 查看集群日志"
        echo "  8. 备份集群数据"
        echo "  9. 监控集群状态"
        echo " 10. 故障转移"
        echo " 11. 清理集群资源"
        echo " 12. 显示连接信息"
        echo " 13. 系统信息"
        echo " 14. 帮助信息"
        echo "  0. 退出"
        echo ""
        
        local choice
        read -p "请选择操作 (0-14): " choice
        
        case "$choice" in
            1)
                start_cluster
                ;;
            2)
                stop_cluster
                ;;
            3)
                restart_cluster
                ;;
            4)
                show_cluster_status
                if docker ps | grep -q "$SLAVE_CONTAINER"; then
                    echo ""
                    check_replication_status
                fi
                ;;
            5)
                setup_replication
                ;;
            6)
                check_replication_status
                ;;
            7)
                show_cluster_logs
                ;;
            8)
                backup_cluster
                ;;
            9)
                monitor_cluster
                ;;
            10)
                failover
                ;;
            11)
                cleanup_cluster
                ;;
            12)
                show_connection_info
                ;;
            13)
                show_system_info
                ;;
            14)
                show_help
                ;;
            0)
                print_info "退出程序"
                exit 0
                ;;
            *)
                print_error "无效选择，请重试"
                ;;
        esac
        
        # 等待用户按键继续
        echo ""
        read -p "按 Enter 键继续..."
    done
}

# 主函数
main() {
    # 检测平台
    detect_platform
    
    # 如果没有参数，启动交互式菜单
    if [ $# -eq 0 ]; then
        interactive_menu
        exit 0
    fi
    
    # 处理命令行参数
    case "${1:-}" in
        "start")
            start_cluster
            ;;
        "stop")
            stop_cluster
            ;;
        "restart")
            restart_cluster
            ;;
        "status")
            if check_requirements; then
                show_cluster_status
                if docker ps | grep -q "$SLAVE_CONTAINER"; then
                    echo ""
                    check_replication_status
                fi
                show_connection_info
            fi
            ;;
        "setup-replication")
            setup_replication
            ;;
        "check-replication")
            check_replication_status
            ;;
        "failover")
            failover
            ;;
        "backup")
            backup_cluster
            ;;
        "logs")
            show_cluster_logs
            ;;
        "monitor")
            monitor_cluster
            ;;
        "cleanup")
            cleanup_cluster
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        "interactive")
            interactive_menu
            ;;
        *)
            print_error "未知命令: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@" 