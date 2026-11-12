package timezone

import (
	"testing"
	"time"
)

func TestSystemLocationReadsAndroidZone(t *testing.T) {
	location, err := systemLocation("Asia/Shanghai\n")
	if err != nil {
		t.Fatal(err)
	}
	_, offset := time.Date(2026, 11, 12, 0, 0, 0, 0, location).Zone()
	if offset != 8*3600 {
		t.Fatalf("got offset %d", offset)
	}
	if _, err := systemLocation("Invalid/Zone"); err == nil {
		t.Fatal("accepted invalid zone")
	}
}
