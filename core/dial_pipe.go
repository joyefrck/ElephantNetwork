//go:build windows && !cgo

package core

import (
	"io"

	"github.com/Microsoft/go-winio"
)

func dial(path string) (io.ReadWriteCloser, error) {
	return winio.DialPipe(path, nil)
}
