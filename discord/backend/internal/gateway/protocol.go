package gateway

import "encoding/json"

const (
	OpDispatch     = 0
	OpHeartbeat    = 1
	OpIdentify     = 2
	OpHello        = 10
	OpHeartbeatAck = 11
)

const (
	EventReady           = "READY"
	EventMessageCreate   = "MESSAGE_CREATE"
	EventPresenceUpdate  = "PRESENCE_UPDATE"
	EventInvalidSession  = "INVALID_SESSION"
)

// Frame is the wire envelope for every WebSocket message.
type Frame struct {
	Op int             `json:"op"`
	T  string          `json:"t,omitempty"`
	D  json.RawMessage `json:"d,omitempty"`
}

type HelloData struct {
	HeartbeatIntervalMs int64 `json:"heartbeat_interval"`
}

type IdentifyData struct {
	Token   string `json:"token"`
	GuildID int64  `json:"guild_id"`
}

type ReadyUser struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
}

type ReadyGuild struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type ReadyChannel struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
}

type ReadyPresence struct {
	UserID   int64  `json:"user_id"`
	Username string `json:"username"`
}

type ReadyData struct {
	User      ReadyUser       `json:"user"`
	Guild     ReadyGuild      `json:"guild"`
	Channels  []ReadyChannel  `json:"channels"`
	Presences []ReadyPresence `json:"presences"`
}

type PresenceUpdateData struct {
	UserID   int64  `json:"user_id"`
	Username string `json:"username"`
	Status   string `json:"status"` // "online" | "offline"
}

type MessageCreateData struct {
	ID             int64  `json:"id"`
	ChannelID      int64  `json:"channel_id"`
	GuildID        int64  `json:"guild_id"`
	UserID         int64  `json:"user_id"`
	AuthorUsername string `json:"author_username"`
	Body           string `json:"body"`
	CreatedAt      string `json:"created_at"`
}

type InvalidSessionData struct {
	Reason string `json:"reason"`
}

func MarshalFrame(op int, t string, d any) ([]byte, error) {
	var raw json.RawMessage
	if d != nil {
		b, err := json.Marshal(d)
		if err != nil {
			return nil, err
		}
		raw = b
	}
	return json.Marshal(Frame{Op: op, T: t, D: raw})
}
