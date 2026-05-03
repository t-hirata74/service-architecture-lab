-- pytest-django が `test_<DATABASE>` を CREATE するために必要な権限を付与。
-- mysql コンテナ初回起動時のみ実行される (docker-entrypoint-initdb.d 規約)。
GRANT ALL PRIVILEGES ON `test\_instagram\_development`.* TO 'instagram'@'%';
GRANT CREATE, DROP ON *.* TO 'instagram'@'%';
FLUSH PRIVILEGES;
