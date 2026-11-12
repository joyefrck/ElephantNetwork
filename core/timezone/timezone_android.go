package timezone

import (
	"os/exec"
	"time"
)

func init() {
	name, err := exec.Command("/system/bin/getprop", "persist.sys.timezone").Output()
	if err != nil {
		return
	}
	location, err := systemLocation(string(name))
	if err == nil {
		time.Local = location
	}
}
