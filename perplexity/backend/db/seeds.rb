# Phase 2: corpus:ingest を呼ぶだけの薄い shim。本体は lib/tasks/corpus.rake.
#
# 実行: bundle exec rails db:seed   または   bundle exec rake corpus:ingest
# 前提: ai-worker が :8030 で起動していること。
Rake::Task["corpus:ingest"].invoke
