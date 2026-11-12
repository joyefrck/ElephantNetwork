//go:build !android

package core

import "testing"

type unexpectedEventEncoding struct{ called *bool }

func (value unexpectedEventEncoding) MarshalJSON() ([]byte, error) {
	*value.called = true
	return []byte(`{}`), nil
}
func TestDisconnectedCoreSkipsEventEncoding(t *testing.T) {
	old := eventConnected.Swap(false)
	defer eventConnected.Store(old)
	called := false
	sendMessageBatch([]Message{{Type: RequestMessage, Data: unexpectedEventEncoding{called: &called}}})
	if called {
		t.Fatal("encoded event without a listener")
	}
}
