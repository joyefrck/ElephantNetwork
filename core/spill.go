package main

import (
	"encoding/json"
	"fmt"
	"github.com/metacubex/mihomo/constant"
	"os"
	"path/filepath"
	"strings"
)

const responseSpillThreshold = 1 << 20

func spillResponse(id string, data []byte) []byte {
	if len(data) <= responseSpillThreshold {
		return data
	}
	path, err := writeSpilledResponse(data)
	if err != nil {
		result, _ := json.Marshal(MethodResponse{ID: id, Error: &MethodError{
			Code: "spill_error", Message: err.Error(),
		}})
		return result
	}
	result, _ := json.Marshal(MethodResponse{ID: id, File: path})
	return result
}

func writeSpilledResponse(data []byte) (path string, err error) {
	directory := filepath.Join(constant.Path.HomeDir(), "responses")
	if err = os.MkdirAll(directory, 0755); err != nil {
		return
	}
	info, err := os.Lstat(directory)
	if err != nil {
		return "", err
	}
	if !info.IsDir() {
		return "", fmt.Errorf("invalid Core response directory")
	}
	file, err := os.CreateTemp(directory, "response-*.json")
	if err != nil {
		return "", err
	}
	path = file.Name()
	defer func() {
		file.Close()
		if err != nil {
			os.Remove(path)
		}
	}()
	if err = file.Chmod(0644); err != nil {
		return
	}
	if _, err = file.Write(data); err != nil {
		return
	}
	err = file.Close()
	return
}

func cleanupSpilledResponses() {
	directory := filepath.Join(constant.Path.HomeDir(), "responses")
	info, err := os.Lstat(directory)
	if err != nil || !info.IsDir() {
		return
	}
	entries, err := os.ReadDir(directory)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.Type().IsRegular() && strings.HasPrefix(entry.Name(), "response-") && strings.HasSuffix(entry.Name(), ".json") {
			_ = os.Remove(filepath.Join(directory, entry.Name()))
		}
	}
}
