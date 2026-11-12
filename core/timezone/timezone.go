package timezone

import (
	"strings"
	"time"
	_ "time/tzdata"
)

func systemLocation(name string) (*time.Location, error) {
	return time.LoadLocation(strings.TrimSpace(name))
}
