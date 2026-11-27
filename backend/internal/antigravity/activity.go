// Package antigravity joins the desktop app's local task state with its Stop events.
package antigravity

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"time"

	"junimo/backend/internal/processwatch"
	"junimo/backend/internal/quota"
)

const idle = "CASCADE_RUN_STATUS_IDLE"
const running = "CASCADE_RUN_STATUS_RUNNING"

type task struct {
	Conversation string `json:"conversation_id"`
	Title        string `json:"title"`
	Status       string `json:"status"`
	Background   int    `json:"not_fully_idle"`
	Killed       int    `json:"killed"`
	InputMillis  int64  `json:"input_ms"`
	InputStep    int    `json:"last_user_input_step_index"`
}

func (t task) eventID() string {
	data, _ := json.Marshal([]any{t.Conversation, t.InputMillis, t.InputStep})
	digest := sha256.Sum256(data)
	return hex.EncodeToString(digest[:])
}

type Event struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}
type Snapshot struct {
	IsAppRunning *bool           `json:"isAppRunning"`
	WeeklyQuota  *quota.Snapshot `json:"weeklyQuota,omitempty"`
	IsWorking    *bool           `json:"isWorking"`
	Events       []Event         `json:"events,omitempty"`
}

type Source struct{ db, events string }

func DesktopSource(home string) Source {
	return Source{
		db:     filepath.Join(home, ".gemini", "antigravity", "conversation_summaries.db"),
		events: filepath.Join(home, "Library", "Application Support", "Junimo", "antigravity-events"),
	}
}

type fileStamp struct {
	Size     int64
	Modified time.Time
}
type dbStamp struct{ DB, WAL fileStamp }

func stamp(path string) fileStamp {
	info, err := os.Stat(path)
	if err != nil {
		return fileStamp{}
	}
	return fileStamp{info.Size(), info.ModTime()}
}
func (s Source) version() dbStamp { return dbStamp{stamp(s.db), stamp(s.db + "-wal")} }

func (s Source) tasks(ctx context.Context, version dbStamp) ([]task, error) {
	if version.DB.Modified.IsZero() {
		return nil, os.ErrNotExist
	}
	uri := url.URL{Scheme: "file", Path: s.db, RawQuery: "mode=ro"}
	// When the writer has closed and removed its WAL, avoid creating auxiliary
	// files in Antigravity's directory. Reject a racing change below.
	if version.WAL.Modified.IsZero() {
		uri.RawQuery += "&immutable=1"
	}
	const query = "SELECT conversation_id,title,status,not_fully_idle,killed,CAST((julianday(last_user_input_time)-2440587.5)*86400000 AS INTEGER) AS input_ms,last_user_input_step_index FROM conversation_summaries WHERE nesting_depth=0 AND parent_conversation_id=''"
	out, err := exec.CommandContext(ctx, "/usr/bin/sqlite3", "-init", "/dev/null", "-batch", "-readonly", "-json", "-cmd", ".timeout 250", uri.String(), query).Output()
	if err != nil {
		return nil, err
	}
	if version.WAL.Modified.IsZero() && s.version() != version {
		return nil, errors.New("summary changed during read")
	}
	var rows []task
	if len(out) > 0 {
		err = json.Unmarshal(out, &rows)
	}
	return rows, err
}

type stopEvent struct {
	Conversation string `json:"conversationId"`
	Reason       string `json:"terminationReason"`
	Error        string `json:"error"`
	FullyIdle    bool   `json:"fullyIdle"`
	Artifacts    string `json:"artifactDirectoryPath"`
}

// RecordStop records the last Stop for a conversation without waiting for the
// desktop to commit its summary. File names contain no prompts or titles.
func (s Source) RecordStop(input io.Reader) error {
	var stop stopEvent
	if err := json.NewDecoder(io.LimitReader(input, 4<<20)).Decode(&stop); err != nil {
		return err
	}
	if stop.Conversation == "" {
		return nil
	}
	if stop.Artifacts != "" {
		// The global hooks file is shared by the desktop, CLI and IDE.
		root := filepath.Dir(s.db)
		artifacts := strings.Replace(stop.Artifacts, "~/.gemini/antigravity/", root+"/", 1)
		if filepath.Clean(artifacts) != filepath.Join(root, "brain", stop.Conversation) {
			return nil
		}
	}
	marker := filepath.Join(s.events, conversationKey(stop.Conversation))
	if !stop.FullyIdle || stop.Error != "" || (stop.Reason != "NO_TOOL_CALL" && stop.Reason != "model_stop") {
		err := os.Remove(marker)
		if os.IsNotExist(err) {
			return nil
		}
		return err
	}
	if err := os.MkdirAll(s.events, 0700); err != nil {
		return err
	}
	f, err := os.OpenFile(marker, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	// A one-byte write refreshes mtime even for repeated stops of the same chat.
	_, err = f.Write([]byte{1})
	closeErr := f.Close()
	return errors.Join(err, closeErr)
}

func conversationKey(id string) string {
	sum := sha256.Sum256([]byte(id))
	return hex.EncodeToString(sum[:])
}

type Monitor struct {
	source   Source
	started  time.Time
	watcher  *processwatch.Watcher
	version  dbStamp
	tasks    []task
	loaded   bool
	mu       sync.RWMutex
	snapshot Snapshot
}

func NewMonitor(source Source) *Monitor {
	return &Monitor{
		source:  source,
		started: time.Now(),
		watcher: processwatch.New("Antigravity"),
	}
}
func (m *Monitor) Snapshot() Snapshot {
	m.mu.RLock()
	defer m.mu.RUnlock()
	return m.snapshot
}

func (m *Monitor) refresh(ctx context.Context, now time.Time) {
	version := m.source.version()
	dbChanged := !m.loaded || m.version != version
	snapshot := Snapshot{IsAppRunning: m.watcher.IsRunning(ctx, now, dbChanged)}
	if dbChanged {
		rows, err := m.source.tasks(ctx, version)
		m.tasks, m.version, m.loaded = rows, version, err == nil
	}
	if m.loaded {
		snapshot.IsWorking = workingState(m.tasks, snapshot.IsAppRunning)
	}
	snapshot.Events = m.recentCompletions(now)
	m.mu.Lock()
	m.snapshot = snapshot
	m.mu.Unlock()
}

func workingState(tasks []task, appRunning *bool) *bool {
	known := true
	for _, row := range tasks {
		if row.Killed != 0 {
			continue
		}
		if row.Status == running || row.Background != 0 {
			return appRunning
		}
		if row.Status != idle {
			known = false
		}
	}
	if !known {
		return nil
	}
	return new(false)
}

func (m *Monitor) recentCompletions(now time.Time) []Event {
	entries, _ := os.ReadDir(m.source.events)
	recent := make(map[string]time.Time)
	for _, entry := range entries {
		if len(entry.Name()) != 64 || !entry.Type().IsRegular() {
			continue
		}
		info, err := entry.Info()
		if err != nil {
			continue
		}
		when := info.ModTime()
		if now.Sub(when) > 24*time.Hour {
			os.Remove(filepath.Join(m.source.events, entry.Name()))
		} else if !when.Before(m.started) && now.Sub(when) < 30*time.Second {
			recent[entry.Name()] = when
		}
	}
	var events []Event
	if len(recent) > 0 {
		for _, row := range m.tasks {
			if row.Status != idle || row.Killed != 0 || row.Background != 0 {
				continue
			}
			when, ok := recent[conversationKey(row.Conversation)]
			if ok && row.InputMillis > 0 && when.UnixMilli() >= row.InputMillis {
				event := Event{row.eventID(), row.Title}
				events = append(events, event)
			}
		}
		sort.Slice(events, func(i, j int) bool { return events[i].ID < events[j].ID })
	}
	return events
}

func (m *Monitor) Run(ctx context.Context) {
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		readCtx, cancel := context.WithTimeout(ctx, 1500*time.Millisecond)
		m.refresh(readCtx, time.Now())
		cancel()
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
