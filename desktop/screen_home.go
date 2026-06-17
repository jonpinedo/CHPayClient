// screen_home.go — Home screen.
// - Card info persists 2 minutes after card removal (cancelled on new card).
// - "Cobrar" button enabled only for TERMINAL role; "Recargar" for CAJA.
// - Historial panel below action buttons.
package main

import (
	"fmt"
	"strconv"
	"sync"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/data/binding"
	"fyne.io/fyne/v2/widget"
)

const cardClearDelay = 2 * time.Minute

// HomeScreen is the main landing screen after login.
type HomeScreen struct {
	win            fyne.Window
	roles          []string
	deviceName     string
	capituloNombre string
	onGoPago       func()
	onGoRecarga    func()

	// State (protected by mu)
	mu          sync.Mutex
	uid         string
	cardName    string
	cardBalance float64
	cardValid   bool
	clearTimer  *time.Timer

	// UI bindings (goroutine-safe)
	uidBind    binding.String
	nameBind   binding.String
	readerBind binding.String

	// Canvas text for balance (needs color changes)
	balanceText *canvas.Text

	// Buttons (nil if role absent)
	cobrarBtn   *widget.Button
	recargarBtn *widget.Button

	// Historial panel
	historial *HistorialWidget
}

func newHomeScreen(
	win fyne.Window,
	roles []string,
	deviceName string,
	capituloNombre string,
	onGoPago func(),
	onGoRecarga func(),
) *HomeScreen {
	return &HomeScreen{
		win:            win,
		roles:          roles,
		deviceName:     deviceName,
		capituloNombre: capituloNombre,
		onGoPago:       onGoPago,
		onGoRecarga:    onGoRecarga,
		uidBind:        binding.NewString(),
		nameBind:       binding.NewString(),
		readerBind:     binding.NewString(),
	}
}

func (h *HomeScreen) build() fyne.CanvasObject {
	// Initialise bindings
	h.uidBind.Set("Esperando tarjeta...")          //nolint:errcheck
	h.nameBind.Set("Acerca una tarjeta al lector") //nolint:errcheck

	// Update reader status now (NFC may already be running)
	reader := nfcGetCurrentReader()
	h.setReaderStatus(reader)

	// ── Header ────────────────────────────────────────────────────────────────
	rolesText := "Sin roles"
	if len(h.roles) > 0 {
		rolesText = ""
		for i, r := range h.roles {
			if i > 0 {
				rolesText += "  ·  "
			}
			rolesText += r
		}
	}
	deviceLbl := widget.NewLabelWithStyle(
		"🖥  "+h.deviceName, fyne.TextAlignLeading, fyne.TextStyle{Bold: true},
	)
	capLbl := widget.NewLabel("📍 Capítulo: " + h.capituloNombre)
	rolesLbl := widget.NewLabel("Roles: " + rolesText)

	// ── Reader status ─────────────────────────────────────────────────────────
	readerLabel := widget.NewLabelWithData(h.readerBind)

	// ── Card panel ────────────────────────────────────────────────────────────
	uidLabel := widget.NewLabelWithData(h.uidBind)
	nameLabel := widget.NewLabelWithData(h.nameBind)
	nameLabel.TextStyle = fyne.TextStyle{Bold: true}

	h.balanceText = canvas.NewText("", colorGray)
	h.balanceText.TextSize = 30
	h.balanceText.TextStyle = fyne.TextStyle{Bold: true}

	cardPanel := widget.NewCard("💳  Tarjeta", "", container.NewVBox(
		uidLabel,
		nameLabel,
		container.NewPadded(h.balanceText),
	))

	// ── Action buttons ────────────────────────────────────────────────────────
	actionItems := []fyne.CanvasObject{}

	hasTerminal := false
	hasCaja := false
	for _, r := range h.roles {
		if r == "TERMINAL" {
			hasTerminal = true
		}
		if r == "CAJA" {
			hasCaja = true
		}
	}

	if hasTerminal {
		h.cobrarBtn = widget.NewButton("💶  Cobrar", h.onGoPago)
		h.cobrarBtn.Importance = widget.DangerImportance
		h.cobrarBtn.Disable()
		actionItems = append(actionItems, h.cobrarBtn)
	}
	if hasCaja {
		h.recargarBtn = widget.NewButton("💰  Recargar", h.onGoRecarga)
		h.recargarBtn.Importance = widget.SuccessImportance
		h.recargarBtn.Disable()
		actionItems = append(actionItems, h.recargarBtn)
	}

	var actionRow fyne.CanvasObject
	if len(actionItems) == 0 {
		actionRow = widget.NewLabel("")
	} else {
		actionRow = container.NewGridWithColumns(len(actionItems), actionItems...)
	}

	// ── Historial ─────────────────────────────────────────────────────────────
	h.historial = newHistorialWidget("📋  Últimas operaciones")

	return container.NewBorder(
		container.NewVBox(
			container.NewPadded(container.NewVBox(deviceLbl, capLbl, rolesLbl)),
			container.NewPadded(readerLabel),
			container.NewPadded(cardPanel),
			container.NewPadded(actionRow),
		),
		nil, nil, nil,
		container.NewPadded(h.historial.CanvasObject()),
	)
}

// OnShow is called by the navigator when this screen becomes visible.
func (h *HomeScreen) OnShow() {
	reader := nfcGetCurrentReader()
	h.setReaderStatus(reader)

	// Si hay una tarjeta activa, refrescar saldo desde la API
	h.mu.Lock()
	uid := h.uid
	h.mu.Unlock()
	if uid != "" {
		go h.processCard(uid)
	}
}

// SimulateCard processes a UID as if a physical card was tapped (called from Admin).
func (h *HomeScreen) SimulateCard(uid string) {
	go h.processCard(uid)
}

// GetCardInfo returns the current card state (used by pago/recarga screens).
func (h *HomeScreen) GetCardInfo() map[string]interface{} {
	h.mu.Lock()
	defer h.mu.Unlock()
	return map[string]interface{}{
		"uid":    h.uid,
		"nombre": h.cardName,
		"saldo":  h.cardBalance,
		"valida": h.cardValid,
	}
}

// ── NFC Callbacks ─────────────────────────────────────────────────────────────

// OnCardDetected is the NFC callback; spawns a goroutine for the API call.
func (h *HomeScreen) OnCardDetected(uid string) {
	go h.processCard(uid)
}

// OnCardRemoved schedules a 2-minute delayed clear.
func (h *HomeScreen) OnCardRemoved() {
	h.mu.Lock()
	if h.clearTimer != nil {
		h.clearTimer.Stop()
	}
	h.clearTimer = time.AfterFunc(cardClearDelay, h.clearCard)
	h.mu.Unlock()
}

// OnReaderChange updates the reader status label.
func (h *HomeScreen) OnReaderChange(reader string) {
	h.setReaderStatus(reader)
}

// ── Internals ─────────────────────────────────────────────────────────────────

func (h *HomeScreen) processCard(uid string) {
	h.mu.Lock()
	if h.clearTimer != nil {
		h.clearTimer.Stop()
		h.clearTimer = nil
	}
	h.uid = uid
	h.mu.Unlock()

	h.uidBind.Set("UID: " + uid) //nolint:errcheck
	h.nameBind.Set("Consultando...")
	h.balanceText.Text = ""
	h.balanceText.Refresh()
	h.setButtonsEnabled(false)
	if h.historial != nil {
		h.historial.Clear()
	}

	result, err := apiValidarTarjeta(uid)
	if err != nil {
		h.nameBind.Set("Error: " + err.Error()) //nolint:errcheck
		return
	}

	balance, _ := strconv.ParseFloat(result.Saldo, 64)

	h.mu.Lock()
	h.cardName = result.Nombre
	h.cardBalance = balance
	h.cardValid = result.Permitido
	h.mu.Unlock()

	h.nameBind.Set(result.Nombre) //nolint:errcheck

	if result.NumeroSocio != 0 {
		h.uidBind.Set(fmt.Sprintf("Socio #%d  ·  UID: %s", result.NumeroSocio, uid)) //nolint:errcheck
	}

	if balance > 0 {
		h.balanceText.Color = colorGreen
	} else {
		h.balanceText.Color = colorRed
	}
	h.balanceText.Text = fmt.Sprintf("%.2f €", balance)
	h.balanceText.Refresh()

	h.setButtonsEnabled(result.Permitido)

	// Aviso de monedero creado
	if result.MonederoCreado {
		go func() {
			h.nameBind.Set("ℹ️ Monedero creado en " + h.capituloNombre + ". Saldo: 0.00€") //nolint:errcheck
			time.Sleep(4 * time.Second)
			h.nameBind.Set(result.Nombre) //nolint:errcheck
		}()
	}

	if h.historial != nil {
		h.historial.Load(uid)
	}
}

func (h *HomeScreen) clearCard() {
	h.mu.Lock()
	h.uid = ""
	h.cardName = ""
	h.cardBalance = 0
	h.cardValid = false
	h.clearTimer = nil
	h.mu.Unlock()

	h.uidBind.Set("Esperando tarjeta...")          //nolint:errcheck
	h.nameBind.Set("Acerca una tarjeta al lector") //nolint:errcheck
	h.balanceText.Text = ""
	h.balanceText.Color = colorGray
	h.balanceText.Refresh()
	h.setButtonsEnabled(false)
	if h.historial != nil {
		h.historial.Clear()
	}
}

func (h *HomeScreen) setButtonsEnabled(enabled bool) {
	if h.cobrarBtn != nil {
		if enabled {
			h.cobrarBtn.Enable()
		} else {
			h.cobrarBtn.Disable()
		}
	}
	if h.recargarBtn != nil {
		if enabled {
			h.recargarBtn.Enable()
		} else {
			h.recargarBtn.Disable()
		}
	}
}

func (h *HomeScreen) setReaderStatus(reader string) {
	if reader != "" {
		h.readerBind.Set("NFC: " + reader) //nolint:errcheck
	} else {
		h.readerBind.Set("Sin lector NFC conectado") //nolint:errcheck
	}
}
