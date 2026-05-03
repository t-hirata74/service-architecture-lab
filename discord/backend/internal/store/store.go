package store

import (
	"context"
	"database/sql"
	"errors"
	"time"
)

var ErrNotFound = errors.New("store: not found")

type User struct {
	ID           int64     `json:"id"`
	Username     string    `json:"username"`
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"created_at"`
}

type Guild struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	OwnerID   int64     `json:"owner_id"`
	CreatedAt time.Time `json:"created_at"`
}

type Membership struct {
	GuildID int64     `json:"guild_id"`
	UserID  int64     `json:"user_id"`
	Role    string    `json:"role"`
	JoinedAt time.Time `json:"joined_at"`
}

type Channel struct {
	ID        int64     `json:"id"`
	GuildID   int64     `json:"guild_id"`
	Name      string    `json:"name"`
	CreatedAt time.Time `json:"created_at"`
}

type Message struct {
	ID              int64     `json:"id"`
	ChannelID       int64     `json:"channel_id"`
	UserID          int64     `json:"user_id"`
	Body            string    `json:"body"`
	CreatedAt       time.Time `json:"created_at"`
	AuthorUsername  string    `json:"author_username,omitempty"`
}

type MessageSnippet struct {
	User     string `json:"user"`
	Username string `json:"username,omitempty"`
	Body     string `json:"body"`
}

type Store struct {
	DB *sql.DB
}

func (s *Store) CreateUser(ctx context.Context, username, passwordHash string) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO users (username, password_hash) VALUES (?, ?)`,
		username, passwordHash)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) UserByUsername(ctx context.Context, username string) (*User, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT id, username, password_hash, created_at FROM users WHERE username = ? LIMIT 1`,
		username)
	var u User
	if err := row.Scan(&u.ID, &u.Username, &u.PasswordHash, &u.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &u, nil
}

func (s *Store) UserByID(ctx context.Context, id int64) (*User, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT id, username, password_hash, created_at FROM users WHERE id = ? LIMIT 1`, id)
	var u User
	if err := row.Scan(&u.ID, &u.Username, &u.PasswordHash, &u.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &u, nil
}

func (s *Store) CreateGuild(ctx context.Context, name string, ownerID int64) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO guilds (name, owner_id) VALUES (?, ?)`, name, ownerID)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) GuildByID(ctx context.Context, id int64) (*Guild, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT id, name, owner_id, created_at FROM guilds WHERE id = ? LIMIT 1`, id)
	var g Guild
	if err := row.Scan(&g.ID, &g.Name, &g.OwnerID, &g.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &g, nil
}

func (s *Store) GuildsForUser(ctx context.Context, userID int64) ([]Guild, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT g.id, g.name, g.owner_id, g.created_at FROM guilds g
		 INNER JOIN memberships m ON m.guild_id = g.id
		 WHERE m.user_id = ? ORDER BY g.id ASC`,
		userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Guild
	for rows.Next() {
		var g Guild
		if err := rows.Scan(&g.ID, &g.Name, &g.OwnerID, &g.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

func (s *Store) CreateMembership(ctx context.Context, guildID, userID int64, role string) error {
	_, err := s.DB.ExecContext(ctx,
		`INSERT INTO memberships (guild_id, user_id, role) VALUES (?, ?, ?)`,
		guildID, userID, role)
	return err
}

func (s *Store) Membership(ctx context.Context, guildID, userID int64) (*Membership, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT guild_id, user_id, role, joined_at FROM memberships
		 WHERE guild_id = ? AND user_id = ? LIMIT 1`,
		guildID, userID)
	var m Membership
	if err := row.Scan(&m.GuildID, &m.UserID, &m.Role, &m.JoinedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &m, nil
}

func (s *Store) CreateChannel(ctx context.Context, guildID int64, name string) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO channels (guild_id, name) VALUES (?, ?)`, guildID, name)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) ChannelsByGuild(ctx context.Context, guildID int64) ([]Channel, error) {
	rows, err := s.DB.QueryContext(ctx,
		`SELECT id, guild_id, name, created_at FROM channels WHERE guild_id = ? ORDER BY id ASC`,
		guildID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Channel
	for rows.Next() {
		var c Channel
		if err := rows.Scan(&c.ID, &c.GuildID, &c.Name, &c.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) ChannelByID(ctx context.Context, id int64) (*Channel, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT id, guild_id, name, created_at FROM channels WHERE id = ? LIMIT 1`, id)
	var c Channel
	if err := row.Scan(&c.ID, &c.GuildID, &c.Name, &c.CreatedAt); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &c, nil
}

func (s *Store) CreateMessage(ctx context.Context, channelID, userID int64, body string) (int64, error) {
	res, err := s.DB.ExecContext(ctx,
		`INSERT INTO messages (channel_id, user_id, body) VALUES (?, ?, ?)`,
		channelID, userID, body)
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (s *Store) MessagesForChannel(ctx context.Context, channelID int64, before *int64, limit int) ([]Message, error) {
	if limit <= 0 || limit > 100 {
		limit = 50
	}
	var rows *sql.Rows
	var err error
	if before == nil {
		rows, err = s.DB.QueryContext(ctx,
			`SELECT m.id, m.channel_id, m.user_id, m.body, m.created_at, u.username
			 FROM messages m INNER JOIN users u ON u.id = m.user_id
			 WHERE m.channel_id = ?
			 ORDER BY m.id DESC LIMIT ?`,
			channelID, limit)
	} else {
		rows, err = s.DB.QueryContext(ctx,
			`SELECT m.id, m.channel_id, m.user_id, m.body, m.created_at, u.username
			 FROM messages m INNER JOIN users u ON u.id = m.user_id
			 WHERE m.channel_id = ? AND m.id < ?
			 ORDER BY m.id DESC LIMIT ?`,
			channelID, *before, limit)
	}
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Message
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.ChannelID, &m.UserID, &m.Body, &m.CreatedAt, &m.AuthorUsername); err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, rows.Err()
}

func (s *Store) MessageByID(ctx context.Context, id int64) (*Message, error) {
	row := s.DB.QueryRowContext(ctx,
		`SELECT m.id, m.channel_id, m.user_id, m.body, m.created_at, u.username
		 FROM messages m INNER JOIN users u ON u.id = m.user_id
		 WHERE m.id = ? LIMIT 1`,
		id)
	var m Message
	if err := row.Scan(&m.ID, &m.ChannelID, &m.UserID, &m.Body, &m.CreatedAt, &m.AuthorUsername); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	return &m, nil
}

func (s *Store) RecentMessageSnippets(ctx context.Context, channelID int64, limit int) ([]MessageSnippet, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := s.DB.QueryContext(ctx,
		`SELECT m.id, m.user_id, m.body, u.username
		 FROM messages m INNER JOIN users u ON u.id = m.user_id
		 WHERE m.channel_id = ?
		 ORDER BY m.id DESC LIMIT ?`,
		channelID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []MessageSnippet
	for rows.Next() {
		var id, uid int64
		var body, uname string
		if err := rows.Scan(&id, &uid, &body, &uname); err != nil {
			return nil, err
		}
		out = append(out, MessageSnippet{User: uname, Username: uname, Body: body})
	}
	return out, rows.Err()
}
