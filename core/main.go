//go:build !cgo

package main

import (
	"fmt"
	"os"
)

func main() {
	args := os.Args
	if len(args) <= 1 {
		fmt.Println("Arguments error")
		os.Exit(1)
	}
	go exitOnTermination()
	defer releaseOnExit()
	startServer(args[1])
}
