// api.go — Llamadas HTTP a la API CHPay y structs de modelo.
package main

import (
	"bytes"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

var httpClient = &http.Client{
	Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true}, //nolint:gosec
	},
	Timeout: 15 * time.Second,
}

// sessionBearer is the in-memory session token (not persisted).
var sessionBearer string

func apiSetBearer(bearer string) { sessionBearer = bearer }
func apiClearBearer()            { sessionBearer = "" }
func apiGetBearer() string       { return sessionBearer }

func apiURL(path string) string {
	base := strings.TrimRight(configGetAPIURL(), "/")
	return base + path
}

func apiHeaders() map[string]string {
	return map[string]string{
		"Authorization": "Bearer " + sessionBearer,
		"Content-Type":  "application/json",
	}
}

// doPost sends a POST request with JSON body and returns the decoded response.
func doPost(path string, body interface{}, useAuth bool) (map[string]interface{}, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest("POST", apiURL(path), bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if useAuth {
		req.Header.Set("Authorization", "Bearer "+sessionBearer)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("HTTP %d: %s", resp.StatusCode, extractDetail(raw))
	}
	var result map[string]interface{}
	json.Unmarshal(raw, &result) //nolint:errcheck
	return result, nil
}

// doGet sends a GET request and returns the raw body bytes and status.
func doGetRaw(path string) ([]byte, int, error) {
	req, err := http.NewRequest("GET", apiURL(path), nil)
	if err != nil {
		return nil, 0, err
	}
	for k, v := range apiHeaders() {
		req.Header.Set(k, v)
	}
	resp, err := httpClient.Do(req)
	if err != nil {
		return nil, 0, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	return raw, resp.StatusCode, nil
}

func extractDetail(body []byte) string {
	var m map[string]interface{}
	if json.Unmarshal(body, &m) == nil {
		if d, ok := m["detail"]; ok {
			return fmt.Sprintf("%v", d)
		}
	}
	s := strings.TrimSpace(string(body))
	if s == "" {
		return "Sin detalles"
	}
	return s
}

// ── Model structs ─────────────────────────────────────────────────────────────

type DeviceInfo struct {
	Nombre string   `json:"nombre"`
	Roles  []string `json:"roles"`
}

type ValidarTarjetaResp struct {
	Nombre      string `json:"nombre"`
	SocioID     int    `json:"socio_id"`
	NumeroSocio int    `json:"numero_socio"`
	Saldo       string `json:"saldo"`
	Permitido   bool   `json:"permitido"`
}

type Transaccion struct {
	ID             int    `json:"id"`
	Tipo           string `json:"tipo"`
	Monto          string `json:"monto"`
	SaldoPosterior string `json:"saldo_posterior"`
	Timestamp      string `json:"timestamp"`
	Descripcion    string `json:"descripcion"`
}

type HistorialResp struct {
	SocioNombre        string        `json:"socio_nombre"`
	Transacciones      []Transaccion `json:"transacciones"`
	TotalTransacciones int           `json:"total_transacciones"`
}

type Socio struct {
	NumeroSocio int    `json:"numero_socio"`
	Nombre      string `json:"nombre"`
	Email       string `json:"email"`
	Telefono    string `json:"telefono"`
	Saldo       string `json:"saldo"`
}

// ── Auth endpoints ────────────────────────────────────────────────────────────

func apiRegisterRequest(deviceID, deviceName string) error {
	_, err := doPost("/api/auth/register-request", map[string]string{
		"imei":   deviceID,
		"nombre": deviceName,
	}, false)
	return err
}

func apiAuthorizeDevice(deviceID, deviceName string) (string, error) {
	result, err := doPost("/api/auth/authorize", map[string]string{
		"imei":   deviceID,
		"nombre": deviceName,
	}, false)
	if err != nil {
		return "", err
	}
	token, _ := result["token"].(string)
	return token, nil
}

func apiCreateSession(deviceID, permanentToken string) (string, int, error) {
	data, _ := json.Marshal(map[string]string{"imei": deviceID, "token": permanentToken})
	req, _ := http.NewRequest("POST", apiURL("/api/auth/session"), bytes.NewReader(data))
	req.Header.Set("Content-Type", "application/json")
	resp, err := httpClient.Do(req)
	if err != nil {
		return "", 0, err
	}
	defer resp.Body.Close()
	raw, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != 200 {
		return "", resp.StatusCode, fmt.Errorf("HTTP %d: %s", resp.StatusCode, extractDetail(raw))
	}
	var m map[string]interface{}
	json.Unmarshal(raw, &m) //nolint:errcheck
	bearer, _ := m["bearer"].(string)
	return bearer, 200, nil
}

func apiGetDeviceInfo() DeviceInfo {
	raw, code, err := doGetRaw("/api/auth/me")
	if err != nil || code != 200 {
		return DeviceInfo{}
	}
	var info DeviceInfo
	json.Unmarshal(raw, &info) //nolint:errcheck
	return info
}

// ── Tarjetas ──────────────────────────────────────────────────────────────────

func apiValidarTarjeta(uid string) (*ValidarTarjetaResp, error) {
	result, err := doPost("/api/tarjetas/validar", map[string]string{"uid": uid}, true)
	if err != nil {
		return nil, err
	}
	// Re-encode and decode into struct
	b, _ := json.Marshal(result)
	var resp ValidarTarjetaResp
	json.Unmarshal(b, &resp) //nolint:errcheck
	return &resp, nil
}

// ── Pagos ─────────────────────────────────────────────────────────────────────

func apiHacerPago(uid string, monto float64, descripcion string) (string, error) {
	result, err := doPost("/api/pagos/", map[string]interface{}{
		"uid":         uid,
		"monto":       monto,
		"descripcion": descripcion,
	}, true)
	if err != nil {
		return "", err
	}
	saldo, _ := result["saldo_posterior"].(string)
	if saldo == "" {
		if v, ok := result["saldo_posterior"].(float64); ok {
			saldo = fmt.Sprintf("%.2f", v)
		}
	}
	return saldo, nil
}

// ── Recargas ──────────────────────────────────────────────────────────────────

func apiHacerRecarga(uid string, monto float64, descripcion string) (string, error) {
	result, err := doPost("/api/recargas/", map[string]interface{}{
		"uid":         uid,
		"monto":       monto,
		"descripcion": descripcion,
	}, true)
	if err != nil {
		return "", err
	}
	saldo, _ := result["saldo_posterior"].(string)
	if saldo == "" {
		if v, ok := result["saldo_posterior"].(float64); ok {
			saldo = fmt.Sprintf("%.2f", v)
		}
	}
	return saldo, nil
}

func apiGetHistorial(uid string, limite int) (*HistorialResp, error) {
	raw, code, err := doGetRaw(fmt.Sprintf("/api/recargas/historial/%s?limite=%d", uid, limite))
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("HTTP %d", code)
	}
	var resp HistorialResp
	if err := json.Unmarshal(raw, &resp); err != nil {
		return nil, err
	}
	return &resp, nil
}

// ── Admin ─────────────────────────────────────────────────────────────────────

func apiListarSocios() ([]Socio, error) {
	raw, code, err := doGetRaw("/api/admin/socios")
	if err != nil {
		return nil, err
	}
	if code != 200 {
		return nil, fmt.Errorf("HTTP %d", code)
	}
	var socios []Socio
	json.Unmarshal(raw, &socios) //nolint:errcheck
	return socios, nil
}

func apiCrearSocio(nombre, email, telefono, saldoInicial string) (map[string]interface{}, error) {
	body := map[string]interface{}{
		"nombre":        nombre,
		"saldo_inicial": saldoInicial,
	}
	if email != "" {
		body["email"] = email
	}
	if telefono != "" {
		body["telefono"] = telefono
	}
	return doPost("/api/admin/socios", body, true)
}

func apiAsociarTarjeta(numeroSocio int, uid string) error {
	_, err := doPost("/api/admin/tarjetas", map[string]interface{}{
		"numero_socio": numeroSocio,
		"uid":          uid,
	}, true)
	return err
}

// ── Health ────────────────────────────────────────────────────────────────────

func apiCheckHealth() bool {
	client := &http.Client{
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true}, //nolint:gosec
		},
		Timeout: 5 * time.Second,
	}
	req, err := http.NewRequest("GET", apiURL("/health"), nil)
	if err != nil {
		return false
	}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == 200
}
