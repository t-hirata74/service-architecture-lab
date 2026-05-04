package gateway

import (
	"context"
	"log/slog"
	"time"
)

// Hub owns all clients connected to one guild. Per ADR 0002, a single goroutine
// (Run) is the sole owner of `clients` and `presence`; other goroutines
// communicate via channels only.
type Hub struct {
	GuildID           int64
	HeartbeatInterval time.Duration
	Log               *slog.Logger

	register   chan *Client
	unregister chan *Client
	broadcast  chan []byte

	// owned by Run goroutine
	clients  map[*Client]struct{}
	presence map[int64]*presenceEntry // user_id -> entry
}

type presenceEntry struct {
	username string
	conns    int
}

func NewHub(guildID int64, hbInterval time.Duration, log *slog.Logger) *Hub {
	if hbInterval <= 0 {
		hbInterval = 10 * time.Second
	}
	return &Hub{
		GuildID:           guildID,
		HeartbeatInterval: hbInterval,
		Log:               log,
		register:          make(chan *Client, 16),
		unregister:        make(chan *Client, 16),
		broadcast:         make(chan []byte, 256),
		clients:           make(map[*Client]struct{}),
		presence:          make(map[int64]*presenceEntry),
	}
}

// RequestRegister enqueues a register event for the Hub goroutine.
// Returns false if the Hub queue is full or the Hub has stopped; the caller
// should treat this as a failed handshake and close the client.
func (h *Hub) RequestRegister(c *Client) bool {
	select {
	case h.register <- c:
		return true
	default:
		return false
	}
}

// RequestUnregister enqueues an unregister event. Safe from any goroutine.
// Falls back to a non-blocking send so a stopped Hub won't deadlock callers.
func (h *Hub) RequestUnregister(c *Client) {
	select {
	case h.unregister <- c:
	default:
		// Hub is shutting down or its unregister buffer is saturated.
		// Closing the client directly is safe (idempotent) — the writePump exits
		// and the connection is closed; presence cleanup just won't be broadcast.
		c.Close()
	}
}

// Broadcast enqueues a pre-marshaled payload to be fanned out to all clients.
// Returns false if the broadcast queue is full (caller may log and continue).
func (h *Hub) Broadcast(payload []byte) bool {
	select {
	case h.broadcast <- payload:
		return true
	default:
		return false
	}
}

// Run is the Hub's single goroutine; it owns the clients/presence maps.
// Stops when ctx is canceled.
func (h *Hub) Run(ctx context.Context) {
	tickEvery := h.HeartbeatInterval / 2
	if tickEvery <= 0 {
		tickEvery = time.Second
	}
	ticker := time.NewTicker(tickEvery)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			for c := range h.clients {
				c.Close()
			}
			h.clients = nil
			h.presence = nil
			return

		case c := <-h.register:
			// Broadcast PRESENCE_UPDATE(online) to *existing* clients before
			// adding c. The new client will get presence state via READY-side
			// flows and doesn't need its own online event.
			entry, ok := h.presence[c.UserID]
			if !ok {
				h.fanoutPresence(c.UserID, c.Username, "online")
				h.presence[c.UserID] = &presenceEntry{username: c.Username, conns: 1}
			} else {
				entry.conns++
			}
			h.clients[c] = struct{}{}

		case c := <-h.unregister:
			h.removeClient(c)

		case payload := <-h.broadcast:
			h.fanout(payload)

		case <-ticker.C:
			h.checkHeartbeats()
		}
	}
}

func (h *Hub) checkHeartbeats() {
	cutoff := time.Now().Add(-h.HeartbeatInterval * 3 / 2).UnixNano()
	var dead []*Client
	for c := range h.clients {
		if c.LastHB.Load() < cutoff {
			dead = append(dead, c)
		}
	}
	for _, c := range dead {
		h.removeClient(c)
	}
}

// removeClient deletes c from the registry, decrements presence, broadcasts
// PRESENCE_UPDATE(offline) if the user is now fully gone, and signals the
// client to stop. Safe to call multiple times for the same client.
func (h *Hub) removeClient(c *Client) {
	if _, ok := h.clients[c]; !ok {
		c.Close()
		return
	}
	delete(h.clients, c)
	c.Close()

	entry, ok := h.presence[c.UserID]
	if !ok {
		return
	}
	entry.conns--
	if entry.conns <= 0 {
		delete(h.presence, c.UserID)
		h.fanoutPresence(c.UserID, entry.username, "offline")
	}
}

// fanout enqueues payload to every client. Slow consumers (Send buffer full)
// are collected and removed AFTER iteration so we never mutate clients during
// range. removeClient triggers fanoutPresence, which recursively calls fanout —
// safe because by then the original iteration has finished.
func (h *Hub) fanout(payload []byte) {
	var slow []*Client
	for c := range h.clients {
		if !c.trySend(payload) {
			slow = append(slow, c)
		}
	}
	for _, c := range slow {
		if h.Log != nil {
			h.Log.Warn("hub drop slow consumer",
				slog.Int64("guild_id", h.GuildID),
				slog.Int64("user_id", c.UserID))
		}
		h.removeClient(c)
	}
}

func (h *Hub) fanoutPresence(userID int64, username, status string) {
	payload, err := MarshalFrame(OpDispatch, EventPresenceUpdate, PresenceUpdateData{
		UserID: userID, Username: username, Status: status,
	})
	if err != nil {
		return
	}
	h.fanout(payload)
}
