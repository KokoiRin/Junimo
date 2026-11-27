// Package quota 定义各 Agent 共享的额度快照契约与后台轮询监控器。
package quota

// Status 表示某个额度事实源的当前可用状态。
type Status string

const (
	StatusLoading     Status = "loading"
	StatusAvailable   Status = "available"
	StatusUnavailable Status = "unavailable"
)

// Window 表示单个额度周期的剩余比例与重置时间。
type Window struct {
	RemainingPercent      int   `json:"remainingPercent"`
	WindowDurationMinutes int   `json:"windowDurationMinutes"`
	ResetsAt              int64 `json:"resetsAt"`
}

// Snapshot 是后端向外壳公开的标准额度快照，各 Agent 适配器共用同一数据结构。
type Snapshot struct {
	Status      Status  `json:"status"`
	Primary     *Window `json:"primary,omitempty"`
	Secondary   *Window `json:"secondary,omitempty"`
	Message     string  `json:"message,omitempty"`
	RefreshedAt string  `json:"refreshedAt,omitempty"`
}
