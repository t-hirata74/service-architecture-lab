package gateway

import (
	"encoding/json"
	"sync"
	"sync/atomic"
	"time"

	"github.com/gorilla/websocket"
)

const (
	clientSendBuffer = 64
	writeWait        = 10 * time.Second
	readLimitBytes   = 1 << 16 // 64 KiB
)

// Client represents an authenticated, identified WebSocket connection
// belonging to one Hub (one guild).
//
// Concurrency model:
//   - Send: written to by Hub goroutine and (rarely) by readPump (HEARTBEAT_ACK).
//     Never closed; lifecycle is gated by Stop instead.
//   - Stop: closed exactly once via Close(); both pumps and Hub use it.
//   - Conn writes: serialized through writePump; readPump never writes to Conn.
//   - LastHB: atomic, written by readPump, read by Hub goroutine.
type Client struct {
	Hub      *Hub
	Conn     *websocket.Conn
	UserID   int64
	Username string

	Send chan []byte
	Stop chan struct{}

	LastHB    atomic.Int64 // unix nano of last HEARTBEAT
	closeOnce sync.Once
}

func NewClient(hub *Hub, conn *websocket.Conn, userID int64, username string) *Client {
	c := &Client{
		Hub:      hub,
		Conn:     conn,
		UserID:   userID,
		Username: username,
		Send:     make(chan []byte, clientSendBuffer),
		Stop:     make(chan struct{}),
	}
	c.LastHB.Store(time.Now().UnixNano())
	return c
}

// Close marks the client as stopping. Idempotent.
// Close does NOT close c.Send (Hub may still try to enqueue; writes use select+Stop).
func (c *Client) Close() {
	c.closeOnce.Do(func() {
		close(c.Stop)
	})
}

// trySend non-blockingly enqueues a payload for writePump.
// Returns false if the buffer is full (caller should treat the client as slow).
func (c *Client) trySend(payload []byte) bool {
	select {
	case <-c.Stop:
		return false
	default:
	}
	select {
	case c.Send <- payload:
		return true
	default:
		return false
	}
}

// ReadPump reads frames from the WebSocket. It updates LastHB on heartbeats and
// enqueues HEARTBEAT_ACK responses. Exits on read error or Stop.
//
// On exit it requests Hub unregistration so presence/cleanup runs even when the
// connection drops without an explicit close frame.
func (c *Client) ReadPump() {
	defer func() {
		c.Hub.RequestUnregister(c)
		c.Close()
	}()
	c.Conn.SetReadLimit(readLimitBytes)
	for {
		_, data, err := c.Conn.ReadMessage()
		if err != nil {
			return
		}
		var f Frame
		if err := json.Unmarshal(data, &f); err != nil {
			continue // ignore malformed frames after IDENTIFY
		}
		switch f.Op {
		case OpHeartbeat:
			c.LastHB.Store(time.Now().UnixNano())
			ack, err := MarshalFrame(OpHeartbeatAck, "", nil)
			if err != nil {
				continue
			}
			// Drop ACK if buffer full or stopping; client retries on next heartbeat.
			select {
			case c.Send <- ack:
			case <-c.Stop:
				return
			default:
			}
		case OpIdentify:
			// Re-identify after handshake is unsupported in MVP.
		default:
			// unknown op: ignore
		}
	}
}

// WritePump owns the Conn's write side.
func (c *Client) WritePump() {
	defer c.Conn.Close()
	for {
		select {
		case msg := <-c.Send:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.Conn.WriteMessage(websocket.TextMessage, msg); err != nil {
				return
			}
		case <-c.Stop:
			_ = c.Conn.SetWriteDeadline(time.Now().Add(writeWait))
			_ = c.Conn.WriteMessage(websocket.CloseMessage,
				websocket.FormatCloseMessage(websocket.CloseNormalClosure, ""))
			return
		}
	}
}
