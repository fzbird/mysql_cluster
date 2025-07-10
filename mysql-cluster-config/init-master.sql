-- ========================================================================
-- MySQL 主服务器初始化脚本
-- ========================================================================

-- 设置全局配置
SET GLOBAL enforce_gtid_consistency = ON;
SET GLOBAL gtid_mode = OFF_PERMISSIVE;
SET GLOBAL gtid_mode = ON_PERMISSIVE;
SET GLOBAL gtid_mode = ON;

-- 创建复制用户
CREATE USER IF NOT EXISTS 'replicator'@'%' IDENTIFIED WITH mysql_native_password BY 'repl_password';
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';

-- 创建监控用户
CREATE USER IF NOT EXISTS 'monitor'@'%' IDENTIFIED WITH mysql_native_password BY 'monitor_password';
GRANT PROCESS, REPLICATION CLIENT, SELECT ON *.* TO 'monitor'@'%';

-- 创建应用只读用户（用于从服务器）
CREATE USER IF NOT EXISTS 'gallery_reader'@'%' IDENTIFIED WITH mysql_native_password BY 'reader_password';
GRANT SELECT ON gallerydb.* TO 'gallery_reader'@'%';

-- 创建应用读写用户（用于主服务器）
CREATE USER IF NOT EXISTS 'gallery_writer'@'%' IDENTIFIED WITH mysql_native_password BY 'writer_password';
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, ALTER, INDEX ON gallerydb.* TO 'gallery_writer'@'%';

-- 刷新权限
FLUSH PRIVILEGES;

-- 启用二进制日志
FLUSH BINARY LOGS;

-- 显示主服务器状态（用于配置从服务器）
SHOW MASTER STATUS;

-- 创建Gallery数据库（如果不存在）
CREATE DATABASE IF NOT EXISTS gallerydb CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci; 