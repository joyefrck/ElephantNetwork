package core

import (
	"errors"
	"strings"
	"unicode"

	"github.com/metacubex/mihomo/adapter/inbound"
	"github.com/metacubex/mihomo/component/auth"
	"github.com/metacubex/mihomo/config"
	"github.com/metacubex/mihomo/hub/route"
	authStore "github.com/metacubex/mihomo/listener/auth"
)

func localControllerConfig(cfg *config.Config, params *UpdateParams) *route.Config {
	controller := cfg.Controller
	if params.ExternalController != nil {
		controller.ExternalController = *params.ExternalController
	}
	if params.Secret != nil {
		controller.Secret = *params.Secret
	}
	if len(controller.Secret) < 32 || strings.ContainsFunc(controller.Secret, func(r rune) bool {
		return unicode.IsSpace(r) || unicode.IsControl(r)
	}) {
		controller.ExternalController = ""
	}
	controller.ExternalControllerTLS = ""
	controller.ExternalControllerUnix = ""
	controller.ExternalControllerPipe = ""
	return &route.Config{Addr: controller.ExternalController, Secret: controller.Secret}
}

func patchLocalController(cfg *config.Config, params *UpdateParams) {
	old := *cfg.Controller
	next := localControllerConfig(cfg, params)
	if old.ExternalController == next.Addr && old.Secret == next.Secret &&
		old.ExternalControllerTLS == "" && old.ExternalControllerUnix == "" &&
		old.ExternalControllerPipe == "" {
		return
	}
	route.ReCreateServer(next)
}

func applyAuthentication(cfg *config.Config, authentication []string) error {
	users := make([]auth.AuthUser, 0, len(authentication))
	for _, line := range authentication {
		user, pass, found := strings.Cut(line, ":")
		if !found || user == "" || pass == "" || strings.ContainsFunc(user, func(r rune) bool {
			return unicode.IsSpace(r) || unicode.IsControl(r)
		}) || strings.ContainsFunc(pass, unicode.IsControl) {
			return errors.New("invalid local proxy credentials")
		}
		users = append(users, auth.AuthUser{User: user, Pass: pass})
	}
	cfg.General.Authentication = authentication
	cfg.Users = users
	cfg.General.SkipAuthPrefixes = nil
	inbound.SetSkipAuthPrefixes(nil)
	authStore.Default.SetAuthenticator(auth.NewAuthenticator(users))
	return nil
}
