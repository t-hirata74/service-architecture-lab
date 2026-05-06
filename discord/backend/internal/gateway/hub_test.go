package gateway

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"
)

// fakeClient builds a Client without a real WebSocket connection. WritePump is
// not started; the test reads c.Send directly.
func fakeClient(hub *Hub, userID int64, username string, buf int) *Client {
	if buf <= 0 {
		buf = clientSendBuffer
	}
	c := &Client{
		Hub: hub, UserID: userID, Username: username,
		Send: make(chan []byte, buf),
		Stop: make(chan struct{}),
	}
	c.LastHB.Store(time.Now().UnixNano())
	return c
}

func discardLogger() *slog.Logger {
	return slog.New(slog.NewJSONHandler(io.Discard, nil))
}

// drainKind reads all currently-buffered frames from c.Send and counts events
// matching `wantT`. Non-blocking.
func drainKind(c *Client, wantT string) int {
	n := 0
	for {
		select {
		case raw := <-c.Send:
			var f Frame
			if err := json.Unmarshal(raw, &f); err == nil && f.T == wantT {
				n++
			}
		default:
			return n
		}
	}
}

func TestHubBroadcastReachesRegisteredClient(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := NewHub(1, 200*time.Millisecond, discardLogger())
	go hub.Run(ctx)

	a := fakeClient(hub, 10, "alice", 0)
	b := fakeClient(hub, 11, "bob", 0)
	if !hub.RequestRegister(a) || !hub.RequestRegister(b) {
		t.Fatal("register should not be full")
	}

	// Allow Run to process register events.
	time.Sleep(50 * time.Millisecond)

	payload, _ := MarshalFrame(OpDispatch, EventMessageCreate, MessageCreateData{ID: 1, Body: "hi"})
	if !hub.Broadcast(payload) {
		t.Fatal("broadcast queue should not be full")
	}

	time.Sleep(50 * time.Millisecond)

	if got := drainKind(a, EventMessageCreate); got != 1 {
		t.Errorf("alice MESSAGE_CREATE = %d, want 1", got)
	}
	if got := drainKind(b, EventMessageCreate); got != 1 {
		t.Errorf("bob MESSAGE_CREATE = %d, want 1", got)
	}
}

func TestHubUnregisterStopsBroadcast(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := NewHub(1, 500*time.Millisecond, discardLogger())
	go hub.Run(ctx)

	a := fakeClient(hub, 10, "alice", 0)
	hub.RequestRegister(a)
	time.Sleep(30 * time.Millisecond)

	hub.RequestUnregister(a)
	time.Sleep(30 * time.Millisecond)

	select {
	case <-a.Stop:
	default:
		t.Fatal("client should have been stopped on unregister")
	}

	payload, _ := MarshalFrame(OpDispatch, EventMessageCreate, MessageCreateData{ID: 2, Body: "after"})
	hub.Broadcast(payload)
	time.Sleep(30 * time.Millisecond)

	if got := drainKind(a, EventMessageCreate); got != 0 {
		t.Errorf("alice should not receive MESSAGE_CREATE after unregister, got %d", got)
	}
}

func TestHubHeartbeatTimeoutEvictsClient(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := NewHub(1, 100*time.Millisecond, discardLogger())
	go hub.Run(ctx)

	a := fakeClient(hub, 10, "alice", 0)
	// Set lastHB way in the past so the next ticker pass evicts.
	a.LastHB.Store(time.Now().Add(-time.Second).UnixNano())
	hub.RequestRegister(a)

	// ticker fires every interval/2 = 50ms; cutoff is 1.5*100ms = 150ms.
	deadline := time.After(time.Second)
	for {
		select {
		case <-a.Stop:
			return
		case <-deadline:
			t.Fatal("client was not evicted on heartbeat timeout")
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func TestHubSlowConsumerDropped(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := NewHub(1, time.Second, discardLogger())
	go hub.Run(ctx)

	// buffer=1 so it fills fast.
	slow := fakeClient(hub, 10, "slow", 1)
	hub.RequestRegister(slow)
	time.Sleep(20 * time.Millisecond)

	// Pour more messages than the buffer can hold; readers never drain.
	for i := 0; i < 5; i++ {
		p, _ := MarshalFrame(OpDispatch, EventMessageCreate, MessageCreateData{ID: int64(i), Body: "x"})
		hub.Broadcast(p)
	}

	deadline := time.After(time.Second)
	for {
		select {
		case <-slow.Stop:
			return
		case <-deadline:
			t.Fatal("slow consumer was not dropped")
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func TestHubMultiTabPresence(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := NewHub(1, time.Second, discardLogger())
	go hub.Run(ctx)

	// observer watches presence broadcasts. Hub no longer broadcasts a
	// client's own online event to itself, so no drain needed here.
	obs := fakeClient(hub, 99, "observer", 0)
	hub.RequestRegister(obs)
	time.Sleep(20 * time.Millisecond)

	tab1 := fakeClient(hub, 10, "alice", 0)
	tab2 := fakeClient(hub, 10, "alice", 0)
	hub.RequestRegister(tab1)
	hub.RequestRegister(tab2)
	time.Sleep(40 * time.Millisecond)

	// Only one online broadcast for first tab; second is a no-op.
	if got := drainKind(obs, EventPresenceUpdate); got != 1 {
		t.Errorf("expected 1 PRESENCE_UPDATE(online) for first tab, got %d", got)
	}

	hub.RequestUnregister(tab1)
	time.Sleep(40 * time.Millisecond)

	// Closing tab1 alone should NOT broadcast offline.
	if got := drainKind(obs, EventPresenceUpdate); got != 0 {
		t.Errorf("expected 0 PRESENCE_UPDATE while tab2 still open, got %d", got)
	}

	hub.RequestUnregister(tab2)
	time.Sleep(40 * time.Millisecond)

	if got := drainKind(obs, EventPresenceUpdate); got != 1 {
		t.Errorf("expected 1 PRESENCE_UPDATE(offline) after last tab, got %d", got)
	}
}

// A late joiner must observe peers that were already online — the snapshot is
// returned synchronously by the Hub goroutine alongside register, so the
// READY frame can seed presence without racing the next PRESENCE_UPDATE.
func TestHubRegisterWithSnapshotReturnsExistingOnlineUsers(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := NewHub(1, time.Second, discardLogger())
	go hub.Run(ctx)

	alice := fakeClient(hub, 10, "alice", 0)
	if !hub.RequestRegister(alice) {
		t.Fatal("alice register should not be full")
	}
	time.Sleep(20 * time.Millisecond)

	bob := fakeClient(hub, 11, "bob", 0)
	snap, ok := hub.RequestRegisterWithSnapshot(bob, time.Second)
	if !ok {
		t.Fatal("bob register-with-snapshot should succeed")
	}
	if len(snap) != 1 || snap[0].UserID != 10 || snap[0].Username != "alice" {
		t.Fatalf("expected snapshot=[alice], got %+v", snap)
	}
	for _, p := range snap {
		if p.UserID == bob.UserID {
			t.Errorf("snapshot must exclude self, got %+v", p)
		}
	}
}

// The first member to join sees an empty snapshot — they are alone in the guild.
func TestHubRegisterWithSnapshotEmptyForFirstMember(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	hub := NewHub(1, time.Second, discardLogger())
	go hub.Run(ctx)

	first := fakeClient(hub, 10, "alice", 0)
	snap, ok := hub.RequestRegisterWithSnapshot(first, time.Second)
	if !ok {
		t.Fatal("register should succeed")
	}
	if len(snap) != 0 {
		t.Errorf("expected empty snapshot for first member, got %+v", snap)
	}
}
