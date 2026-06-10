-- e2e 用 (linear_test) と prisma migrate dev の shadow DB (linear_shadow)。
-- 初回 `docker compose up` 時のみ実行される。既存 volume には `docker compose down -v` 後に再適用。
CREATE DATABASE IF NOT EXISTS linear_test;
CREATE DATABASE IF NOT EXISTS linear_shadow;
GRANT ALL PRIVILEGES ON `linear\_test`.* TO 'linear'@'%';
GRANT ALL PRIVILEGES ON `linear\_shadow`.* TO 'linear'@'%';
FLUSH PRIVILEGES;
