package companion

import (
	"context"
	"sync"
)

// agentGate 根据桌面应用运行状态按需启停后台采集协程，并在重启前确保上一轮资源释放完成。
type agentGate struct {
	parent   context.Context
	run      func(context.Context)
	onPaused func()

	mu     sync.Mutex
	active bool
	cancel context.CancelFunc
	done   chan struct{}
}

func newAgentGate(parent context.Context, run func(context.Context), onPaused func()) *agentGate {
	return &agentGate{
		parent:   parent,
		run:      run,
		onPaused: onPaused,
	}
}

// SetActive 在目标应用启动时拉起采集，退出时取消上下文以暂停轮询并释放子进程。
func (g *agentGate) SetActive(active bool) {
	g.mu.Lock()
	if active == g.active {
		g.mu.Unlock()
		return
	}
	if !active {
		cancel := g.cancel
		g.active = false
		g.cancel = nil
		onPaused := g.onPaused
		g.mu.Unlock()
		if cancel != nil {
			cancel()
		}
		if onPaused != nil {
			onPaused()
		}
		return
	}

	prevDone := g.done
	if prevDone != nil {
		g.mu.Unlock()
		<-prevDone
		g.mu.Lock()
		if g.active || g.parent.Err() != nil {
			g.mu.Unlock()
			return
		}
	}
	if g.parent.Err() != nil {
		g.mu.Unlock()
		return
	}
	childCtx, cancel := context.WithCancel(g.parent)
	done := make(chan struct{})
	g.active = true
	g.cancel = cancel
	g.done = done
	g.mu.Unlock()

	go func() {
		defer close(done)
		g.run(childCtx)
	}()
}

// Stop 取消正在运行的采集并等待清理完成。
func (g *agentGate) Stop() {
	g.mu.Lock()
	cancel := g.cancel
	done := g.done
	g.active = false
	g.cancel = nil
	g.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if done != nil {
		<-done
	}
}
