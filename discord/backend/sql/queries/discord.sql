-- name: CreateUser :execresult
INSERT INTO users (username, password_hash) VALUES (?, ?);

-- name: GetUserByUsername :one
SELECT id, username, password_hash, created_at FROM users WHERE username = ? LIMIT 1;

-- name: GetUserByID :one
SELECT id, username, password_hash, created_at FROM users WHERE id = ? LIMIT 1;

-- name: CreateGuild :execresult
INSERT INTO guilds (name, owner_id) VALUES (?, ?);

-- name: GetGuildByID :one
SELECT id, name, owner_id, created_at FROM guilds WHERE id = ? LIMIT 1;

-- name: ListGuildsForUser :many
SELECT g.id, g.name, g.owner_id, g.created_at
FROM guilds g
INNER JOIN memberships m ON m.guild_id = g.id
WHERE m.user_id = ?
ORDER BY g.id ASC;

-- name: CreateMembership :exec
INSERT INTO memberships (guild_id, user_id, role) VALUES (?, ?, ?);

-- name: GetMembership :one
SELECT guild_id, user_id, role, joined_at
FROM memberships
WHERE guild_id = ? AND user_id = ? LIMIT 1;

-- name: CreateChannel :execresult
INSERT INTO channels (guild_id, name) VALUES (?, ?);

-- name: ListChannelsByGuildID :many
SELECT id, guild_id, name, created_at
FROM channels
WHERE guild_id = ?
ORDER BY id ASC;

-- name: GetChannelByID :one
SELECT id, guild_id, name, created_at FROM channels WHERE id = ? LIMIT 1;

-- name: CreateMessage :execresult
INSERT INTO messages (channel_id, user_id, body) VALUES (?, ?, ?);

-- name: ListLatestMessages :many
SELECT m.id, m.channel_id, m.user_id, m.body, m.created_at, u.username AS author_username
FROM messages m
INNER JOIN users u ON u.id = m.user_id
WHERE m.channel_id = ?
ORDER BY m.id DESC
LIMIT ?;

-- name: ListMessagesBefore :many
SELECT m.id, m.channel_id, m.user_id, m.body, m.created_at, u.username AS author_username
FROM messages m
INNER JOIN users u ON u.id = m.user_id
WHERE m.channel_id = ? AND m.id < ?
ORDER BY m.id DESC
LIMIT ?;

-- name: ListRecentMessagesForChannel :many
SELECT m.id, m.user_id, m.body, u.username AS author_username
FROM messages m
INNER JOIN users u ON u.id = m.user_id
WHERE m.channel_id = ?
ORDER BY m.id DESC
LIMIT ?;
