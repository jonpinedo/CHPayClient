// config.go — Persistencia de configuración en %APPDATA%\CHPayDesktop\config.json
// El device_id se obtiene del MachineGuid del registro de Windows.
package main

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"golang.org/x/sys/windows/registry"
)

const (
	cfgDirName  = "CHPayDesktop"
	cfgFileName = "config.json"
)

type Config struct {
	APIURL         string `json:"api_url"`
	DeviceID       string `json:"device_id"`
	DeviceName     string `json:"device_name"`
	PermanentToken string `json:"permanent_token"`
	DeviceStatus   string `json:"device_status"`
	DebugMode      bool   `json:"debug_mode"`
}

var globalConfig = Config{
	APIURL:       "http://chpay-api.private",
	DeviceStatus: "not_registered",
}

func cfgDir() string {
	appdata := os.Getenv("APPDATA")
	if appdata == "" {
		home, _ := os.UserHomeDir()
		appdata = home
	}
	return filepath.Join(appdata, cfgDirName)
}

func cfgFile() string { return filepath.Join(cfgDir(), cfgFileName) }

// getMachineGUID reads the Windows MachineGuid from the registry.
func getMachineGUID() string {
	key, err := registry.OpenKey(
		registry.LOCAL_MACHINE,
		`SOFTWARE\Microsoft\Cryptography`,
		registry.QUERY_VALUE|registry.WOW64_64KEY,
	)
	if err != nil {
		return ""
	}
	defer key.Close()
	val, _, err := key.GetStringValue("MachineGuid")
	if err != nil {
		return ""
	}
	guid := strings.ToUpper(strings.TrimSpace(val))
	if len(guid) == 36 && strings.Count(guid, "-") == 4 {
		return guid
	}
	return ""
}

func resolveDeviceID() string {
	guid := getMachineGUID()
	if guid != "" {
		return "HW-" + guid
	}
	return ""
}

// newUUID generates a random UUID v4 as a fallback device ID.
func newUUID() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x",
		b[0:4], b[4:6], b[6:8], b[8:10], b[10:])
}

// configLoad reads config.json and resolves the device ID.
func configLoad() {
	_ = os.MkdirAll(cfgDir(), 0755)
	data, err := os.ReadFile(cfgFile())
	if err == nil {
		var loaded Config
		if json.Unmarshal(data, &loaded) == nil {
			globalConfig = loaded
			// Fill in any missing defaults
			if globalConfig.APIURL == "" {
				globalConfig.APIURL = "http://chpay-api.private"
			}
			if globalConfig.DeviceStatus == "" {
				globalConfig.DeviceStatus = "not_registered"
			}
		}
	}

	hwID := resolveDeviceID()
	storedID := globalConfig.DeviceID

	if hwID != "" {
		if storedID != hwID {
			if storedID != "" && strings.HasPrefix(storedID, "HW-") {
				// Different machine → clear credentials for security
				globalConfig.PermanentToken = ""
				globalConfig.DeviceStatus = "not_registered"
			}
			globalConfig.DeviceID = hwID
			configSave()
		}
	} else if storedID == "" {
		globalConfig.DeviceID = newUUID()
		configSave()
	}
}

func configSave() {
	_ = os.MkdirAll(cfgDir(), 0755)
	data, err := json.MarshalIndent(globalConfig, "", "  ")
	if err != nil {
		return
	}
	_ = os.WriteFile(cfgFile(), data, 0644)
}

// ── Getters / setters ──────────────────────────────────────────────────────────

func configGetAPIURL() string     { return globalConfig.APIURL }
func configGetDeviceID() string   { return globalConfig.DeviceID }
func configGetDeviceName() string { return globalConfig.DeviceName }
func configGetToken() string      { return globalConfig.PermanentToken }
func configGetStatus() string     { return globalConfig.DeviceStatus }
func configIsAuthorized() bool {
	return globalConfig.DeviceStatus == "authorized" && globalConfig.PermanentToken != ""
}

func configSetAPIURL(url string) {
	globalConfig.APIURL = url
	configSave()
}

func configSetDeviceName(name string) {
	globalConfig.DeviceName = name
	configSave()
}

func configSetToken(token string) {
	globalConfig.PermanentToken = token
	configSave()
}

func configSetStatus(status string) {
	globalConfig.DeviceStatus = status
	configSave()
}

func configClearCredentials() {
	globalConfig.PermanentToken = ""
	globalConfig.DeviceStatus = "not_registered"
	configSave()
}
