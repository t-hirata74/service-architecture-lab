-- 'youtube' ユーザーに youtube_* 全データベースへのアクセス権を付与する。
-- MySQL 公式イメージの MYSQL_USER は MYSQL_DATABASE にしかアクセスできないため、
-- test / production_cache / production_queue 用に追加で grant が必要。
-- (Solid Queue / Solid Cache は専用 DB を切る運用想定)
GRANT ALL PRIVILEGES ON `youtube\_%`.* TO 'youtube'@'%';
FLUSH PRIVILEGES;
