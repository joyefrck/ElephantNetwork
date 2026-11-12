package core

import "time"

const (
	messageBatchInterval = 16 * time.Millisecond
	messageBatchSize     = 32
	messageQueueSize     = 256
	messagePriorityBurst = 8
)

var (
	stateMessageQueue    = make(chan Message, messageQueueSize)
	priorityMessageQueue = make(chan Message, messageQueueSize)
	bulkMessageQueue     = make(chan Message, messageQueueSize)
)

func init() {
	go runMessageBatcher(stateMessageQueue, priorityMessageQueue, bulkMessageQueue, sendMessageBatch)
}

func queueForMessage(message Message) chan Message {
	switch message.Type {
	case LogMessage, RequestMessage:
		return bulkMessageQueue
	case DelayMessage:
		return priorityMessageQueue
	default:
		return stateMessageQueue
	}
}

func sendMessage(message Message) {
	if !hasMessageListener() {
		return
	}
	enqueueLatest(queueForMessage(message), message)
}

func enqueueLatest(queue chan Message, message Message) {
	select {
	case queue <- message:
		return
	default:
	}
	select {
	case <-queue:
	default:
	}
	select {
	case queue <- message:
	default:
	}
}

func runMessageBatcher(stateMessages, priorityMessages, bulkMessages <-chan Message, send func([]Message)) {
	timer := time.NewTimer(messageBatchInterval)
	if !timer.Stop() {
		<-timer.C
	}
	defer timer.Stop()
	var deadline <-chan time.Time
	batch := make([]Message, 0, messageBatchSize)
	flush := func() {
		if len(batch) == 0 {
			return
		}
		if !timer.Stop() {
			select {
			case <-timer.C:
			default:
			}
		}
		deadline = nil
		current := append([]Message(nil), batch...)
		batch = batch[:0]
		send(current)
	}
	appendMessage := func(message Message) {
		if len(batch) == 0 {
			timer.Reset(messageBatchInterval)
			deadline = timer.C
		}
		batch = append(batch, message)
		if len(batch) >= messageBatchSize {
			flush()
		}
	}
	drain := func(queue *<-chan Message, budget int) bool {
		progress := false
		for i := 0; i < budget && *queue != nil; i++ {
			select {
			case message, ok := <-*queue:
				progress = true
				if !ok {
					*queue = nil
					return progress
				}
				appendMessage(message)
			default:
				return progress
			}
		}
		return progress
	}
	accept := func(queue *<-chan Message, message Message, ok bool) {
		if !ok {
			*queue = nil
		} else {
			appendMessage(message)
		}
	}
	for stateMessages != nil || priorityMessages != nil || bulkMessages != nil {
		select {
		case <-deadline:
			flush()
		default:
		}
		progress := drain(&stateMessages, messagePriorityBurst)
		progress = drain(&priorityMessages, messagePriorityBurst) || progress
		progress = drain(&bulkMessages, 1) || progress
		if progress {
			continue
		}
		if stateMessages == nil && priorityMessages == nil && bulkMessages == nil {
			break
		}
		select {
		case message, ok := <-stateMessages:
			accept(&stateMessages, message, ok)
		case message, ok := <-priorityMessages:
			accept(&priorityMessages, message, ok)
		case message, ok := <-bulkMessages:
			accept(&bulkMessages, message, ok)
		case <-deadline:
			flush()
		}
	}
	flush()
}
