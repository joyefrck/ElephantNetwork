package core

import (
	"context"
	"sync"
	"time"
)

type probeTask struct {
	cancel  context.CancelFunc
	expires time.Time
}

var probeTasks = struct {
	sync.Mutex
	entries map[string]*probeTask
}{entries: map[string]*probeTask{}}

func beginProbeTask(id string) (context.Context, func()) {
	ctx, cancel := context.WithCancel(context.Background())
	if id == "" {
		return ctx, cancel
	}
	probeTasks.Lock()
	now := time.Now()
	for key, task := range probeTasks.entries {
		if task.cancel == nil && now.After(task.expires) {
			delete(probeTasks.entries, key)
		}
	}
	_, exists := probeTasks.entries[id]
	if exists || len(probeTasks.entries) >= 1024 {
		cancel()
		probeTasks.Unlock()
		return ctx, func() {}
	}
	task := &probeTask{cancel: cancel}
	probeTasks.entries[id] = task
	probeTasks.Unlock()
	return ctx, func() {
		cancel()
		probeTasks.Lock()
		if probeTasks.entries[id] == task {
			delete(probeTasks.entries, id)
		}
		probeTasks.Unlock()
	}
}

func cancelProbeTask(id string) {
	probeTasks.Lock()
	defer probeTasks.Unlock()
	if task := probeTasks.entries[id]; task != nil && task.cancel != nil {
		task.cancel()
	}
	if len(probeTasks.entries) < 1024 || probeTasks.entries[id] != nil {
		probeTasks.entries[id] = &probeTask{expires: time.Now().Add(2 * time.Minute)}
	}
}

func cancelProbeTasks() {
	probeTasks.Lock()
	defer probeTasks.Unlock()
	for _, task := range probeTasks.entries {
		if task.cancel != nil {
			task.cancel()
		}
	}
}

type CancelProbeParams struct {
	TaskID string `json:"task-id"`
}
