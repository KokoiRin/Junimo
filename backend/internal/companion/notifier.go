package companion

import (
	"context"
	"sync"
	"time"
)

// changeNotifier 以递增版本号和广播通道支持长轮询，变更时零延迟唤醒全部等待方。
type changeNotifier struct {
	mu      sync.Mutex
	version uint64
	ch      chan struct{}
}

func newChangeNotifier() *changeNotifier {
	return &changeNotifier{version: 1, ch: make(chan struct{})}
}

func (n *changeNotifier) Version() uint64 {
	n.mu.Lock()
	defer n.mu.Unlock()
	return n.version
}

func (n *changeNotifier) Notify() {
	n.mu.Lock()
	n.version++
	close(n.ch)
	n.ch = make(chan struct{})
	n.mu.Unlock()
}

// Wait 阻塞到版本变化、超时、客户端取消或服务关闭，返回最新版本号以及是否检测到变更。
func (n *changeNotifier) Wait(ctx context.Context, shutdown <-chan struct{}, after uint64, timeout time.Duration) (uint64, bool) {
	n.mu.Lock()
	if n.version != after {
		v := n.version
		n.mu.Unlock()
		return v, true
	}
	ch := n.ch
	n.mu.Unlock()

	if timeout <= 0 {
		return n.Version(), false
	}
	timer := time.NewTimer(timeout)
	defer func() {
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
	}()

	select {
	case <-ch:
		return n.Version(), true
	case <-timer.C:
		return n.Version(), false
	case <-ctx.Done():
		return n.Version(), false
	case <-shutdown:
		return n.Version(), false
	}
}
