package core

import (
	"testing"
	"time"
)

func TestMessageFloodsCannotEvictState(t *testing.T) {
	if queueForMessage(Message{Type: DelayMessage}) == queueForMessage(Message{Type: LoadedMessage}) {
		t.Fatal("delays share state queue")
	}
	if queueForMessage(Message{Type: LogMessage}) == queueForMessage(Message{Type: GeoUpdateMessage}) {
		t.Fatal("logs share state queue")
	}
	if queueForMessage(Message{Type: RouteChangedMessage}) != stateMessageQueue {
		t.Fatal("route stamp not prioritized")
	}
	states, priority, bulk := make(chan Message, 32), make(chan Message, 512), make(chan Message, 512)
	states <- Message{Type: LoadedMessage, Data: "provider"}
	states <- Message{Type: GeoUpdateMessage, Data: GeoUpdateStatus{Type: "MMDB", Updating: false}}
	for i := 0; i < 500; i++ {
		enqueueLatest(priority, Message{Type: DelayMessage})
		enqueueLatest(bulk, Message{Type: LogMessage})
	}
	close(states)
	close(priority)
	close(bulk)
	var got []Message
	runMessageBatcher(states, priority, bulk, func(batch []Message) { got = append(got, batch...) })
	if len(got) != 1002 || got[0].Type != LoadedMessage || got[1].Type != GeoUpdateMessage {
		t.Fatal("state events lost or delayed behind floods")
	}
	firstBulk := -1
	for index, message := range got {
		if message.Type == LogMessage {
			firstBulk = index
			break
		}
	}
	if firstBulk < 0 || firstBulk > 18 {
		t.Fatalf("bulk events starved: %d", firstBulk)
	}
}

func TestEventEnqueueNeverWaitsForSlowConsumer(t *testing.T) {
	queue := make(chan Message, 2)
	started := time.Now()
	for i := 0; i < 10000; i++ {
		enqueueLatest(queue, Message{Type: LoadedMessage, Data: i})
	}
	if time.Since(started) > time.Second {
		t.Fatal("producer blocked")
	}
	<-queue
	if latest := (<-queue).Data; latest != 9999 {
		t.Fatalf("latest event missing: %v", latest)
	}
}
