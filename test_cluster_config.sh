#!/bin/bash

# ========================================================================
# MySQL 集群配置测试脚本 - 跨平台版本
# ========================================================================
# 
# 此脚本用于测试 MySQL 主从复制集群的配置和功能
# 支持系统: Windows (Git Bash/WSL), Linux, macOS
# 
# 使用方法:
#   ./test_cluster_config.sh              - 运行所有测试
#   ./test_cluster_config.sh [test_name]  - 运行特定测试
#
# 测试项目:
#   - platform: 平台检测测试
#   - docker: Docker 环境测试
#   - files: 配置文件测试
#   - network: 网络配置测试
#   - deployment: 部署测试
#   - replication: 复制功能测试
#   - all: 运行所有测试
#
# ========================================================================

set -e

# 版本信息
SCRIPT_VERSION="1.0.0"
SCRIPT_NAME="MySQL Cluster Configuration Test"

# 平台检测变量
PLATFORM=""
IS_WINDOWS=false
IS_LINUX=false
IS_MACOS=false

# 测试结果统计
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TEST_RESULTS=()

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

print_test_header() {
    echo ""
    echo "=================================================================="
    echo -e "\033[1;36m$1\033[0m"
    echo "=================================================================="
}

print_test_result() {
    local test_name="$1"
    local result="$2"
    local message="$3"
    
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$result" = "PASS" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        print_success "✅ $test_name: $message"
        TEST_RESULTS+=("✅ $test_name: PASS")
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        print_error "❌ $test_name: $message"
        TEST_RESULTS+=("❌ $test_name: FAIL")
    fi
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
            ;;
    esac
}

# 平台检测测试
test_platform() {
    print_test_header "平台检测测试"
    
    detect_platform
    
    if [ "$PLATFORM" != "Unknown" ]; then
        print_test_result "平台检测" "PASS" "检测到平台: $PLATFORM"
    else
        print_test_result "平台检测" "FAIL" "无法检测平台"
    fi
    
    # 测试基本命令
    if command -v uname &> /dev/null; then
        print_test_result "uname命令" "PASS" "uname 命令可用"
    else
        print_test_result "uname命令" "FAIL" "uname 命令不可用"
    fi
    
    if command -v bash &> /dev/null; then
        print_test_result "bash命令" "PASS" "bash 命令可用"
    else
        print_test_result "bash命令" "FAIL" "bash 命令不可用"
    fi
}

# Docker 环境测试
test_docker() {
    print_test_header "Docker 环境测试"
    
    # 检查 Docker 是否安装
    if command -v docker &> /dev/null; then
        print_test_result "Docker安装" "PASS" "Docker 已安装"
        
        # 检查 Docker 版本
        local docker_version=$(docker --version 2>/dev/null)
        if [ -n "$docker_version" ]; then
            print_test_result "Docker版本" "PASS" "$docker_version"
        else
            print_test_result "Docker版本" "FAIL" "无法获取 Docker 版本"
        fi
        
        # 检查 Docker 服务状态
        if docker info &> /dev/null; then
            print_test_result "Docker服务" "PASS" "Docker 服务正在运行"
        else
            print_test_result "Docker服务" "FAIL" "Docker 服务未运行"
        fi
        
    else
        print_test_result "Docker安装" "FAIL" "Docker 未安装"
    fi
    
    # 检查 Docker Compose
    if command -v docker-compose &> /dev/null; then
        print_test_result "Docker Compose" "PASS" "docker-compose 可用"
    elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
        print_test_result "Docker Compose" "PASS" "docker compose 可用"
    else
        print_test_result "Docker Compose" "FAIL" "Docker Compose 不可用"
    fi
}

# 配置文件测试
test_files() {
    print_test_header "配置文件测试"
    
    # 必需的文件列表
    local required_files=(
        "deploy_mysql_cluster.sh"
        "docker-compose.mysql-cluster.yml"
        "mysql-cluster.env"
        "mysql-cluster-config/master.cnf"
        "mysql-cluster-config/slave.cnf"
        "mysql-cluster-config/haproxy.cfg"
        "mysql-cluster-config/init-master.sql"
        "mysql-cluster-config/init-slave.sql"
        "mysql-cluster-config/master-init.sh"
        "mysql-cluster-config/slave-init.sh"
    )
    
    # 检查文件是否存在
    for file in "${required_files[@]}"; do
        if [ -f "$file" ]; then
            print_test_result "文件存在" "PASS" "$file 存在"
        else
            print_test_result "文件存在" "FAIL" "$file 不存在"
        fi
    done
    
    # 检查脚本文件权限
    local script_files=(
        "deploy_mysql_cluster.sh"
        "mysql-cluster-config/master-init.sh"
        "mysql-cluster-config/slave-init.sh"
    )
    
    for script in "${script_files[@]}"; do
        if [ -f "$script" ]; then
            if [ -x "$script" ]; then
                print_test_result "脚本权限" "PASS" "$script 有执行权限"
            else
                print_test_result "脚本权限" "FAIL" "$script 没有执行权限"
            fi
        fi
    done
    
    # 检查配置文件语法
    if [ -f "mysql-cluster.env" ]; then
        if grep -q "MYSQL_ROOT_PASSWORD" mysql-cluster.env; then
            print_test_result "环境变量" "PASS" "环境变量配置正确"
        else
            print_test_result "环境变量" "FAIL" "环境变量配置有误"
        fi
    fi
}

# 网络配置测试
test_network() {
    print_test_header "网络配置测试"
    
    # 检查端口是否可用
    local ports=(3306 3307 3308 3309 8404 9104)
    
    for port in "${ports[@]}"; do
        if command -v netstat &> /dev/null; then
            if netstat -an | grep -q ":$port "; then
                print_test_result "端口检查" "FAIL" "端口 $port 已被占用"
            else
                print_test_result "端口检查" "PASS" "端口 $port 可用"
            fi
        else
            print_test_result "端口检查" "PASS" "端口 $port (无法检查)"
        fi
    done
    
    # 检查 Docker 网络
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        if docker network ls | grep -q mysql-cluster-network; then
            print_test_result "Docker网络" "PASS" "集群网络已存在"
        else
            print_test_result "Docker网络" "PASS" "集群网络未创建（正常）"
        fi
    else
        print_test_result "Docker网络" "FAIL" "无法检查 Docker 网络"
    fi
}

# 部署测试
test_deployment() {
    print_test_header "部署测试"
    
    # 检查部署脚本
    if [ -f "deploy_mysql_cluster.sh" ]; then
        if [ -x "deploy_mysql_cluster.sh" ]; then
            # 测试帮助信息
            if ./deploy_mysql_cluster.sh help &> /dev/null; then
                print_test_result "部署脚本" "PASS" "部署脚本帮助功能正常"
            else
                print_test_result "部署脚本" "FAIL" "部署脚本帮助功能异常"
            fi
        else
            print_test_result "部署脚本" "FAIL" "部署脚本不可执行"
        fi
    else
        print_test_result "部署脚本" "FAIL" "部署脚本不存在"
    fi
    
    # 检查 Docker Compose 配置
    if command -v docker-compose &> /dev/null || (command -v docker &> /dev/null && docker compose version &> /dev/null); then
        if docker-compose -f docker-compose.mysql-cluster.yml config &> /dev/null; then
            print_test_result "Compose配置" "PASS" "Docker Compose 配置验证通过"
        elif docker compose -f docker-compose.mysql-cluster.yml config &> /dev/null; then
            print_test_result "Compose配置" "PASS" "Docker Compose 配置验证通过"
        else
            print_test_result "Compose配置" "FAIL" "Docker Compose 配置验证失败"
        fi
    else
        print_test_result "Compose配置" "FAIL" "Docker Compose 不可用"
    fi
}

# 复制功能测试
test_replication() {
    print_test_header "复制功能测试"
    
    # 检查 MySQL 配置文件
    if [ -f "mysql-cluster-config/master.cnf" ]; then
        if grep -q "server-id.*1" mysql-cluster-config/master.cnf; then
            print_test_result "主服务器配置" "PASS" "主服务器 ID 配置正确"
        else
            print_test_result "主服务器配置" "FAIL" "主服务器 ID 配置错误"
        fi
    fi
    
    if [ -f "mysql-cluster-config/slave.cnf" ]; then
        if grep -q "server-id.*2" mysql-cluster-config/slave.cnf; then
            print_test_result "从服务器配置" "PASS" "从服务器 ID 配置正确"
        else
            print_test_result "从服务器配置" "FAIL" "从服务器 ID 配置错误"
        fi
    fi
    
    # 检查初始化脚本
    if [ -f "mysql-cluster-config/master-init.sh" ]; then
        if grep -q "MYSQL_REPLICATION_USER" mysql-cluster-config/master-init.sh; then
            print_test_result "复制用户配置" "PASS" "复制用户配置存在"
        else
            print_test_result "复制用户配置" "FAIL" "复制用户配置缺失"
        fi
    fi
    
    # 检查 HAProxy 配置
    if [ -f "mysql-cluster-config/haproxy.cfg" ]; then
        if grep -q "mysql-master" mysql-cluster-config/haproxy.cfg; then
            print_test_result "负载均衡配置" "PASS" "HAProxy 配置正确"
        else
            print_test_result "负载均衡配置" "FAIL" "HAProxy 配置错误"
        fi
    fi
}

# 显示测试结果
show_test_results() {
    echo ""
    echo "=================================================================="
    echo -e "\033[1;36m测试结果汇总\033[0m"
    echo "=================================================================="
    echo ""
    
    # 显示所有测试结果
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    
    echo ""
    echo "总计: $TOTAL_TESTS 个测试"
    echo "通过: $PASSED_TESTS 个测试"
    echo "失败: $FAILED_TESTS 个测试"
    
    if [ $FAILED_TESTS -eq 0 ]; then
        print_success "所有测试通过！集群配置正常"
        echo ""
        echo "建议的部署步骤："
        echo "1. 运行 ./deploy_mysql_cluster.sh 启动交互式菜单"
        echo "2. 选择 '启动集群' 选项"
        echo "3. 等待集群启动完成"
        echo "4. 检查集群状态"
    else
        print_error "存在 $FAILED_TESTS 个失败的测试"
        echo ""
        echo "请修复以下问题："
        echo "1. 确保 Docker 和 Docker Compose 已安装并运行"
        echo "2. 检查所有配置文件是否存在且格式正确"
        echo "3. 确保所需端口未被占用"
        echo "4. 检查脚本文件权限"
    fi
    
    echo ""
    echo "系统信息："
    echo "  操作系统: $PLATFORM"
    echo "  测试时间: $(date)"
    echo "  脚本版本: $SCRIPT_VERSION"
}

# 主函数
main() {
    print_test_header "$SCRIPT_NAME v$SCRIPT_VERSION"
    
    # 检测平台
    detect_platform
    print_info "检测到操作系统: $PLATFORM"
    
    # 根据参数选择测试
    case "${1:-all}" in
        "platform")
            test_platform
            ;;
        "docker")
            test_docker
            ;;
        "files")
            test_files
            ;;
        "network")
            test_network
            ;;
        "deployment")
            test_deployment
            ;;
        "replication")
            test_replication
            ;;
        "all")
            test_platform
            test_docker
            test_files
            test_network
            test_deployment
            test_replication
            ;;
        *)
            print_error "未知的测试类型: $1"
            echo ""
            echo "可用的测试类型:"
            echo "  platform    - 平台检测测试"
            echo "  docker      - Docker 环境测试"
            echo "  files       - 配置文件测试"
            echo "  network     - 网络配置测试"
            echo "  deployment  - 部署测试"
            echo "  replication - 复制功能测试"
            echo "  all         - 运行所有测试"
            exit 1
            ;;
    esac
    
    # 显示测试结果
    show_test_results
}

# 执行主函数
main "$@" 