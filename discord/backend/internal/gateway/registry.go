package gateway

import (
	"context"
	"log/slog"
	"sync"
	"time"
)

// Registry owns the set of per-guild Hubs. Hubs are created lazily on first
// access; a single registry-wide context is used to stop all Hubs on shutdown.
//
// Per ADR 0001 / 0002 the goal is a single-process, in-memory map. Hub.Run
// goroutines are started by GetOrCreate and live until ctx is canceled.
type Registry struct {
	ctx               context.Context
	heartbeatInterval time.Duration
	log               *slog.Logger

	mu   sync.Mutex
	hubs map[int64]*Hub
}

func NewRegistry(ctx context.Context, hbInterval time.Duration, log *slog.Logger) *Registry {
	return &Registry{
		ctx:               ctx,
		heartbeatInterval: hbInterval,
		log:               log,
		hubs:              make(map[int64]*Hub),
	}
}

func (r *Registry) GetOrCreate(guildID int64) *Hub {
	r.mu.Lock()
	defer r.mu.Unlock()
	if h, ok := r.hubs[guildID]; ok {
		return h
	}
	h := NewHub(guildID, r.heartbeatInterval, r.log)
	r.hubs[guildID] = h
	go h.Run(r.ctx)
	return h
}

// Get returns the existing Hub for a guild, or nil. Used by REST broadcast
// paths that should NOT spawn a Hub for a guild with no listeners.
func (r *Registry) Get(guildID int64) *Hub {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.hubs[guildID]
}
