package mobile

type ResultHandler interface{ OnResult(data []byte) error }
type TunHandler interface {
	Protect(fd int32) (bool, error)
	ResolveProcess(protocol int32, source, target string, uid int32) (string, error)
}

type tunCallbacks struct{ handler TunHandler }

func (c tunCallbacks) Protect(fd int) bool {
	protected, err := c.handler.Protect(int32(fd))
	return err == nil && protected
}
func (c tunCallbacks) ResolveProcess(protocol int, source, target string, uid int) string {
	name, err := c.handler.ResolveProcess(int32(protocol), source, target, int32(uid))
	if err != nil {
		return ""
	}
	return name
}
