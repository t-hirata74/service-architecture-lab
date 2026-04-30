-- 'slack' ユーザーに slack_* 全データベースへのアクセス権を付与する。
-- MySQL 公式イメージの MYSQL_USER は MYSQL_DATABASE にしかアクセスできないため、
-- test / production_cache / production_queue 用に追加で grant が必要。
GRANT ALL PRIVILEGES ON `slack\_%`.* TO 'slack'@'%';
FLUSH PRIVILEGES;
