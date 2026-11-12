package main

import (
	"core"
	"fmt"
	"os"
)

func main() {
	if len(os.Args) != 2 {
		fmt.Fprintln(os.Stderr, "A Core IPC endpoint is required")
		os.Exit(1)
	}
	core.Run(os.Args[1])
}
