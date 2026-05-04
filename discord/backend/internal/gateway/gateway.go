package gateway

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/gorilla/websocket"

	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/auth"
	"github.com/hiratatomoaki/service-architecture-lab/discord/backend/internal/store"
)

const identifyDeadline = 10 * time.Second

// Service exposes the HTTP handler for the WebSocket /gateway endpoint.
type Service struct {
	Log               *slog.Logger
	Store             *store.Store
	JWTSecret         []byte
	Registry          *Registry
	HeartbeatInterval time.Duration
	AllowedOrigins    []string
}

func (s *Service) upgrader() *websocket.Upgrader {
	return &websocket.Upgrader{
		ReadBufferSize:  4096,
		WriteBufferSize: 4096,
		CheckOrigin: func(r *http.Request) bool {
			origin := r.Header.Get("Origin")
			if origin == "" {
				return true // non-browser client (curl / tests)
			}
			for _, a := range s.AllowedOrigins {
				if a == origin {
					return true
				}
			}
			return false
		},
	}
}

// HandleGateway is the HTTP handler. Token is verified BEFORE upgrade so we
// can return a real 401, then again inside IDENTIFY (per ADR 0004).
func (s *Service) HandleGateway(w http.ResponseWriter, r *http.Request) {
	token := strings.TrimSpace(r.URL.Query().Get("token"))
	if token == "" {
		http.Error(w, "missing token", http.StatusUnauthorized)
		return
	}
	claims, err := auth.ParseUserToken(s.JWTSecret, token)
	if err != nil {
		http.Error(w, "invalid token", http.StatusUnauthorized)
		return
	}
	user, err := s.Store.UserByID(r.Context(), claims.UserID)
	if err != nil {
		http.Error(w, "user lookup failed", http.StatusUnauthorized)
		return
	}

	conn, err := s.upgrader().Upgrade(w, r, nil)
	if err != nil {
		s.Log.Warn("ws upgrade failed", slog.Any("err", err))
		return
	}

	if err := s.handshake(conn, user, token); err != nil {
		s.Log.Info("ws handshake failed", slog.Int64("user_id", user.ID), slog.Any("err", err))
		_ = conn.Close()
		return
	}
}

// handshake sends HELLO, awaits IDENTIFY, verifies membership, registers the
// client, sends READY, and starts the read/write pumps. Blocks until readPump
// returns.
func (s *Service) handshake(conn *websocket.Conn, user *store.User, originalToken string) error {
	hello, err := MarshalFrame(OpHello, "", HelloData{
		HeartbeatIntervalMs: s.HeartbeatInterval.Milliseconds(),
	})
	if err != nil {
		return err
	}
	_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
	if err := conn.WriteMessage(websocket.TextMessage, hello); err != nil {
		return err
	}
	_ = conn.SetWriteDeadline(time.Time{})

	_ = conn.SetReadDeadline(time.Now().Add(identifyDeadline))
	_, raw, err := conn.ReadMessage()
	if err != nil {
		return err
	}
	_ = conn.SetReadDeadline(time.Time{})

	var f Frame
	if err := json.Unmarshal(raw, &f); err != nil || f.Op != OpIdentify {
		return s.invalid(conn, "expected IDENTIFY")
	}
	var id IdentifyData
	if err := json.Unmarshal(f.D, &id); err != nil || id.GuildID <= 0 {
		return s.invalid(conn, "invalid IDENTIFY payload")
	}

	// Token re-verification (ADR 0004): defend against URL/log leakage by
	// requiring a matching token in the IDENTIFY body.
	claims, err := auth.ParseUserToken(s.JWTSecret, id.Token)
	if err != nil || claims.UserID != user.ID {
		return s.invalid(conn, "token mismatch")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if _, err := s.Store.Membership(ctx, id.GuildID, user.ID); err != nil {
		if errors.Is(err, store.ErrNotFound) {
			return s.invalid(conn, "not a member of this guild")
		}
		return s.invalid(conn, "membership lookup failed")
	}

	guild, err := s.Store.GuildByID(ctx, id.GuildID)
	if err != nil {
		return s.invalid(conn, "guild lookup failed")
	}
	channels, err := s.Store.ChannelsByGuild(ctx, id.GuildID)
	if err != nil {
		return s.invalid(conn, "channel list failed")
	}
	rChannels := make([]ReadyChannel, 0, len(channels))
	for _, ch := range channels {
		rChannels = append(rChannels, ReadyChannel{ID: ch.ID, Name: ch.Name})
	}

	hub := s.Registry.GetOrCreate(id.GuildID)
	client := NewClient(hub, conn, user.ID, user.Username)

	// Start writePump first so READY/PRESENCE_UPDATE can drain.
	go client.WritePump()

	hub.RequestRegister(client)

	ready, err := MarshalFrame(OpDispatch, EventReady, ReadyData{
		User:     ReadyUser{ID: user.ID, Username: user.Username},
		Guild:    ReadyGuild{ID: guild.ID, Name: guild.Name},
		Channels: rChannels,
	})
	if err == nil {
		client.trySend(ready)
	}

	client.ReadPump() // blocks until disconnect
	return nil
}

// invalid sends an INVALID_SESSION dispatch and returns an error so the caller
// closes the connection.
func (s *Service) invalid(conn *websocket.Conn, reason string) error {
	payload, _ := MarshalFrame(OpDispatch, EventInvalidSession, InvalidSessionData{Reason: reason})
	_ = conn.SetWriteDeadline(time.Now().Add(writeWait))
	_ = conn.WriteMessage(websocket.TextMessage, payload)
	return errors.New(reason)
}
