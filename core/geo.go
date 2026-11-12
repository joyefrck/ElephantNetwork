package core

import (
	"fmt"
	"net/url"
	"sync"

	"github.com/metacubex/mihomo/component/geodata"
	"github.com/metacubex/mihomo/component/updater"
)

var geoDownloaders = map[string]func() error{
	"MMDB":    updater.UpdateMMDB,
	"ASN":     updater.UpdateASN,
	"GEOIP":   updater.UpdateGeoIp,
	"GEOSITE": updater.UpdateGeoSite,
}
var geoUpdateLocks = map[string]*sync.Mutex{"MMDB": {}, "ASN": {}, "GEOIP": {}, "GEOSITE": {}}

func validateGeoURLs(urls map[string]string) error {
	for key, value := range urls {
		switch key {
		case "mmdb", "asn", "geoip", "geosite", "geo-ip", "geo-site":
		default:
			return fmt.Errorf("unknown Geo resource: %s", key)
		}
		parsed, err := url.Parse(value)
		if err != nil || parsed.Host == "" || parsed.Scheme != "https" && parsed.Scheme != "http" || parsed.User != nil {
			return fmt.Errorf("invalid Geo URL for %s", key)
		}
	}
	return nil
}

func applyGeoURLs(urls map[string]string) {
	for key, value := range urls {
		switch key {
		case "mmdb":
			geodata.SetMmdbUrl(value)
			if currentConfig != nil {
				currentConfig.General.GeoXUrl.Mmdb = value
			}
		case "asn":
			geodata.SetASNUrl(value)
			if currentConfig != nil {
				currentConfig.General.GeoXUrl.ASN = value
			}
		case "geoip", "geo-ip":
			geodata.SetGeoIpUrl(value)
			if currentConfig != nil {
				currentConfig.General.GeoXUrl.GeoIp = value
			}
		case "geosite", "geo-site":
			geodata.SetGeoSiteUrl(value)
			if currentConfig != nil {
				currentConfig.General.GeoXUrl.GeoSite = value
			}
		}
	}
}

func handleUpdateGeoData(params *GeoParams) string {
	download, ok := geoDownloaders[params.Type]
	if !ok {
		return "unknown Geo resource"
	}
	if err := validateGeoURLs(params.URLs); err != nil {
		return err.Error()
	}
	lock := geoUpdateLocks[params.Type]
	if !lock.TryLock() {
		return "Geo resource is already updating"
	}
	defer lock.Unlock()
	runLock.Lock()
	if isExiting.Load() {
		runLock.Unlock()
		return "Core is stopping"
	}
	applyGeoURLs(params.URLs)
	runLock.Unlock()
	if err := download(); err != nil {
		return err.Error()
	}
	return ""
}
