-- ========================================================================
-- MySQL 从服务器初始化脚本
-- ========================================================================

-- GTID模式已在Docker启动参数中配置，无需在此设置

-- 确保从服务器是只读的
SET GLOBAL read_only = 1;
SET GLOBAL super_read_only = 1;

-- 停止从服务器复制（如果正在运行）
STOP SLAVE;

-- 重置从服务器状态
RESET SLAVE ALL;

-- 配置主服务器连接信息
-- 注意：这个配置将在容器启动后通过脚本动态设置
-- CHANGE MASTER TO 语句将在 slave-init.sh 中执行

-- 创建数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS gallerydb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; 