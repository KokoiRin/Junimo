package antigravity

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// 桌面开启时，任一主会话运行或留有后台工作就点亮圆环，关闭桌面后遗留的运行记录和已终止的任务都保持静止。
func TestWorkingState(t *testing.T) {
	for _, tc := range []struct {
		rows       []task
		open, want bool
	}{
		{[]task{{Status: idle}, {Status: running}}, true, true},
		{[]task{{Status: idle, Background: 1}}, true, true},
		{[]task{{Status: running}}, false, false},
		{[]task{{Status: running, Killed: 1}}, true, false},
		{[]task{{Status: idle}}, true, false},
	} {
		got := workingState(tc.rows, &tc.open)
		if got == nil || *got != tc.want {
			t.Fatalf("rows=%+v open=%v got=%v", tc.rows, tc.open, got)
		}
	}
	if workingState([]task{{Status: "new-status"}}, nil) != nil {
		t.Fatal("unknown status must stay unknown")
	}
}

// 同一任务先发停止事件再写入空闲状态时只产生一个稳定完成标识，后续输入、启动前的历史和子任务都不能沿用它。
func TestStopAndSummary(t *testing.T) {
	dir := t.TempDir()
	source := Source{db: filepath.Join(dir, "conversation_summaries.db"), events: filepath.Join(dir, "events")}
	sql := func(statement string) {
		t.Helper()
		if out, err := exec.Command("/usr/bin/sqlite3", "-init", "/dev/null", source.db, statement).CombinedOutput(); err != nil {
			t.Fatalf("sqlite: %s %v", out, err)
		}
	}
	m := NewMonitor(source)
	record := func(id string) {
		t.Helper()
		if err := source.RecordStop(strings.NewReader(`{"terminationReason":"NO_TOOL_CALL","conversationId":"` + id + `","fullyIdle":true}`)); err != nil {
			t.Fatal(err)
		}
	}
	record("root")
	record("child")
	sql(`CREATE TABLE conversation_summaries(conversation_id,title,status,not_fully_idle,killed,last_user_input_time,last_user_input_step_index,nesting_depth,parent_conversation_id);
    INSERT INTO conversation_summaries VALUES('root','Example','CASCADE_RUN_STATUS_IDLE',1,0,'2000-01-01 10:00:00+00:00',5,0,''),
    ('child','Child','CASCADE_RUN_STATUS_IDLE',0,0,'2000-01-01 10:00:00+00:00',3,1,'root')`)
	read := func() []Event { m.refresh(context.Background(), time.Now()); return m.Snapshot().Events }
	if len(read()) != 0 {
		t.Fatal("background work still running")
	}
	sql("UPDATE conversation_summaries SET not_fully_idle=0")
	events := read()
	if len(events) != 1 || events[0].Title != "Example" {
		t.Fatalf("eligible events: %+v", events)
	}
	record("root")
	if again := read(); len(again) != 1 || again[0].ID != events[0].ID {
		t.Fatal("duplicate stop changed event identity")
	}
	m = NewMonitor(source)
	if len(read()) != 0 {
		t.Fatal("replayed a historical stop")
	}
	m.started = m.started.Add(-time.Minute)
	sql("UPDATE conversation_summaries SET last_user_input_time='2099-01-01 10:00:00+00:00'")
	if len(read()) != 0 {
		t.Fatal("old stop associated with a newer input")
	}
}

// 正常结束信号可以登记，而取消、错误、步数耗尽、后台未结束和来自其他客户端的信号都不能产生完成标记。
func TestStopReasons(t *testing.T) {
	for _, tc := range []struct {
		fields string
		want   bool
	}{
		{`"terminationReason":"model_stop","fullyIdle":true`, true},
		{`"terminationReason":"USER_CANCELED","fullyIdle":true`, false},
		{`"terminationReason":"ERROR","fullyIdle":true`, false},
		{`"terminationReason":"max_steps_exceeded","fullyIdle":true`, false},
		{`"terminationReason":"NO_TOOL_CALL","fullyIdle":true,"error":"failed"`, false},
		{`"terminationReason":"model_stop","fullyIdle":false`, false},
		{`"terminationReason":"model_stop","fullyIdle":true,"artifactDirectoryPath":"/tmp/other-client/brain/test"`, false},
	} {
		source := DesktopSource(t.TempDir())
		if err := source.RecordStop(strings.NewReader(`{"conversationId":"test",` + tc.fields + `}`)); err != nil {
			t.Fatal(err)
		}
		files, _ := os.ReadDir(source.events)
		if (len(files) > 0) != tc.want {
			t.Fatalf("%s: %v", tc.fields, files)
		}
	}
}
