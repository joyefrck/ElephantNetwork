//go:build !cgo

package main

import (
	"fmt"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"
)

var exitCleanupOnce sync.Once
var exitCleanupDone = make(chan struct{})

func releaseOnExit() {
	isExiting.Store(true)
	if !isInit.Load() {
		return
	}
	exitCleanupOnce.Do(func() { go func() { defer close(exitCleanupDone); handleShutdown() }() })
	select {
	case <-exitCleanupDone:
	case <-time.After(3 * time.Second):
		fmt.Fprintln(os.Stderr, "[ERROR] core cleanup did not finish before exit")
	}
}

func exitOnTermination() {
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, os.Interrupt, syscall.SIGTERM)
	<-signals
	releaseOnExit()
	os.Exit(0)
}
