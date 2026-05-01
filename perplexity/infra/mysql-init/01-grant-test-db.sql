-- Rails の test DB を perplexity ユーザが触れるようにする (db:test:prepare 用)
CREATE DATABASE IF NOT EXISTS perplexity_test
  CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
GRANT ALL PRIVILEGES ON perplexity_test.* TO 'perplexity'@'%';
FLUSH PRIVILEGES;
