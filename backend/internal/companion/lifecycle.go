package companion

import (
	"context"
	"time"
)

// 由外壳启动的后端随父进程退出，避免外壳崩溃后留下占用端口的孤儿后端。
func cancelWhenParentExits(ctx context.Context, cancel context.CancelFunc, originalParent int, currentParent func() int) {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()
	for {
		if originalParent <= 1 || currentParent() != originalParent {
			cancel()
			return
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
