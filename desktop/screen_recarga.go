// screen_recarga.go — Recharge screen.
// Left: quick amount buttons + numpad + NFC confirmation. Right: historial.
// Optional identification (PIN or operator card) when exigir_identificacion_recarga.
package main

import (
	"fmt"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
	"unicode"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"
)

var montosRapidos = []float64{5, 10, 20, 50}

type RecargaScreen struct {
	win         fyne.Window
	getCardInfo func() map[string]interface{}
	onBack      func(uid string) // uid vacío = cancelar; no vacío = tarjeta usada

	// Session flags (refreshed on OnShow)
	exigirIdentificacion bool
	seguridadRecarga     string // desactivada | pin | tarjeta

	// State
	montoStr        string
	nfcWaiting      bool
	waitingOperador bool
	montoConfirmado float64
	clienteUID      string
	lastTxnUID      string // UID de la última recarga exitosa
	leaveGen        atomic.Uint64

	// UI
	displayLbl     *canvas.Text
	msgLabel       *widget.Label
	descEntry      *widget.Entry
	cardNameLbl    *widget.Label
	cardSaldoText  *canvas.Text
	calcContainer  *fyne.Container
	nfcContainer   *fyne.Container
	nfcHintLbl     *widget.Label
	nfcAmountText  *canvas.Text
	nfcStatusLbl   *widget.Label
	nfcCancelBtn   *widget.Button
	historial      *HistorialWidget
}

func newRecargaScreen(win fyne.Window, getCardInfo func() map[string]interface{}, onBack func(uid string)) *RecargaScreen {
	return &RecargaScreen{win: win, getCardInfo: getCardInfo, onBack: onBack}
}

// OnShow is called when the screen becomes active.
func (s *RecargaScreen) OnShow() {
	info := apiGetDeviceInfo()
	s.exigirIdentificacion = info.ExigirIdentificacionRecarga
	s.seguridadRecarga = strings.ToLower(strings.TrimSpace(info.SeguridadRecarga))

	s.nfcWaiting = false
	s.waitingOperador = false
	s.lastTxnUID = ""
	nfcSetCallbacks(NFCCallbacks{})
	if s.calcContainer != nil {
		s.showCalculator()
	}
	s.refreshCardHeader()

	card := s.getCardInfo()
	uid, _ := card["uid"].(string)
	if uid != "" && s.historial != nil {
		s.historial.Load(uid)
	} else if s.historial != nil {
		s.historial.Clear()
	}
	s.setupKeyboard()
}

// OnHide clears keyboard and NFC wait when leaving via sidebar.
func (s *RecargaScreen) OnHide() {
	s.bumpLeaveGen()
	s.nfcWaiting = false
	s.waitingOperador = false
	s.lastTxnUID = ""
	s.clienteUID = ""
	s.teardownKeyboard()
	nfcSetCallbacks(NFCCallbacks{})
	if s.calcContainer != nil {
		s.showCalculator()
	}
}

func (s *RecargaScreen) bumpLeaveGen() uint64 {
	return s.leaveGen.Add(1)
}

func (s *RecargaScreen) currentLeaveGen() uint64 {
	return s.leaveGen.Load()
}

func (s *RecargaScreen) refreshCardHeader() {
	if s.cardNameLbl == nil || s.cardSaldoText == nil {
		return
	}
	info := s.getCardInfo()
	nombre, _ := info["nombre"].(string)
	saldo, _ := info["saldo"].(float64)
	if nombre == "" {
		nombre = "Sin tarjeta leída"
	}
	s.cardNameLbl.SetText(nombre)
	if saldo > 0 {
		s.cardSaldoText.Color = colorGreen
	} else {
		s.cardSaldoText.Color = colorRed
	}
	s.cardSaldoText.Text = fmt.Sprintf("Saldo actual: %.2f €", saldo)
	s.cardSaldoText.Refresh()
}

func (s *RecargaScreen) setupKeyboard() {
	s.win.Canvas().SetOnTypedRune(func(r rune) {
		if s.nfcWaiting || s.win.Canvas().Focused() != nil {
			return
		}
		switch r {
		case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
			s.pressNum(string(r))
		case '.', ',':
			s.pressNum(".")
		}
	})
	s.win.Canvas().SetOnTypedKey(func(ev *fyne.KeyEvent) {
		if s.nfcWaiting {
			return
		}
		switch ev.Name {
		case fyne.KeyBackspace:
			if s.win.Canvas().Focused() == nil {
				s.pressBackspace()
			}
		case fyne.KeyDelete:
			s.pressClear()
		case fyne.KeyReturn, fyne.KeyEnter:
			if s.win.Canvas().Focused() == nil {
				s.processRecarga()
			}
		}
	})
}

func (s *RecargaScreen) teardownKeyboard() {
	s.win.Canvas().SetOnTypedRune(nil)
	s.win.Canvas().SetOnTypedKey(nil)
}

func (s *RecargaScreen) build() fyne.CanvasObject {
	info := s.getCardInfo()
	nombre, _ := info["nombre"].(string)
	saldo, _ := info["saldo"].(float64)
	uid, _ := info["uid"].(string)

	if nombre == "" {
		nombre = "Sin tarjeta leída"
	}

	// ── Card info header ──────────────────────────────────────────────────────
	s.cardNameLbl = widget.NewLabelWithStyle(nombre, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	saldoColor := colorRed
	if saldo > 0 {
		saldoColor = colorGreen
	}
	s.cardSaldoText = canvas.NewText(fmt.Sprintf("Saldo actual: %.2f €", saldo), saldoColor)
	s.cardSaldoText.TextSize = 14
	cardHeader := widget.NewCard("", "", container.NewVBox(s.cardNameLbl, s.cardSaldoText))

	// ── Description entry ─────────────────────────────────────────────────────
	s.descEntry = widget.NewEntry()
	s.descEntry.SetPlaceHolder("Descripción (opcional)")

	// ── Quick amount buttons ──────────────────────────────────────────────────
	quickBtns := make([]fyne.CanvasObject, len(montosRapidos))
	for i, m := range montosRapidos {
		m := m
		btn := widget.NewButton(fmt.Sprintf("%g €", m), func() { s.selectQuick(m) })
		btn.Importance = widget.SuccessImportance
		quickBtns[i] = btn
	}
	quickRow := container.NewGridWithColumns(len(montosRapidos), quickBtns...)

	// ── Amount display ────────────────────────────────────────────────────────
	s.displayLbl = canvas.NewText("0.00 €", colorGray)
	s.displayLbl.TextSize = 44
	s.displayLbl.TextStyle = fyne.TextStyle{Bold: true}
	displayRow := container.NewBorder(nil, nil, nil, s.displayLbl, nil)

	// ── Message ───────────────────────────────────────────────────────────────
	s.msgLabel = widget.NewLabel("")
	s.msgLabel.Alignment = fyne.TextAlignCenter

	// ── Keypad ────────────────────────────────────────────────────────────────
	keypad := s.buildKeypad()
	s.calcContainer = container.NewVBox(keypad)

	// ── NFC wait panel ────────────────────────────────────────────────────────
	nfcIcon := widget.NewLabelWithStyle("📡", fyne.TextAlignCenter, fyne.TextStyle{})
	s.nfcHintLbl = widget.NewLabelWithStyle(
		"Acerca la tarjeta al lector", fyne.TextAlignCenter, fyne.TextStyle{Bold: true},
	)
	s.nfcAmountText = canvas.NewText("", colorBlue)
	s.nfcAmountText.TextSize = 36
	s.nfcAmountText.TextStyle = fyne.TextStyle{Bold: true}

	s.nfcStatusLbl = widget.NewLabel("")
	s.nfcStatusLbl.Alignment = fyne.TextAlignCenter
	s.nfcStatusLbl.Wrapping = fyne.TextWrapWord

	s.nfcCancelBtn = widget.NewButton("Cancelar", s.cancelNFC)
	s.nfcCancelBtn.Importance = widget.LowImportance

	s.nfcContainer = container.NewVBox(
		container.NewCenter(nfcIcon),
		container.NewCenter(s.nfcHintLbl),
		container.NewCenter(s.nfcAmountText),
		s.nfcStatusLbl,
		container.NewCenter(s.nfcCancelBtn),
	)

	// ── Left panel ────────────────────────────────────────────────────────────
	leftContent := container.NewStack(s.calcContainer, s.nfcContainer)
	s.nfcContainer.Hide()

	leftPanel := container.NewBorder(
		container.NewVBox(cardHeader, s.descEntry, quickRow, displayRow, s.msgLabel),
		nil, nil, nil,
		leftContent,
	)

	// ── Right panel: historial ────────────────────────────────────────────────
	s.historial = newHistorialWidget("📋  Historial de recargas", "RECARGA")
	if uid != "" {
		s.historial.Load(uid)
	}

	split := container.NewHSplit(leftPanel, container.NewPadded(s.historial.CanvasObject()))
	split.Offset = 0.58
	return split
}

// ── Input handling ────────────────────────────────────────────────────────────

func (s *RecargaScreen) pressNum(n string) {
	if n == "." && strings.Contains(s.montoStr, ".") {
		return
	}
	s.montoStr += n
	s.updateDisplay()
}

func (s *RecargaScreen) pressBackspace() {
	if len(s.montoStr) > 0 {
		s.montoStr = s.montoStr[:len(s.montoStr)-1]
	}
	s.updateDisplay()
}

func (s *RecargaScreen) pressClear() {
	s.montoStr = ""
	s.updateDisplay()
}

func (s *RecargaScreen) selectQuick(m float64) {
	s.montoStr = fmt.Sprintf("%.2f", m)
	s.updateDisplay()
}

func (s *RecargaScreen) updateDisplay() {
	val, _ := strconv.ParseFloat(s.montoStr, 64)
	if val > 0 {
		s.displayLbl.Color = colorBlue
	} else {
		s.displayLbl.Color = colorGray
	}
	s.displayLbl.Text = fmt.Sprintf("%.2f €", val)
	s.displayLbl.Refresh()
}

// ── Recharge flow ─────────────────────────────────────────────────────────────

func (s *RecargaScreen) processRecarga() {
	if s.montoStr == "" {
		s.setMessage("Ingresa un monto.", colorRed)
		return
	}
	monto, _ := strconv.ParseFloat(s.montoStr, 64)
	if monto <= 0 {
		s.setMessage("El monto debe ser mayor que cero.", colorRed)
		return
	}
	s.bumpLeaveGen()
	s.lastTxnUID = ""
	s.montoConfirmado = monto
	s.waitingOperador = false
	s.clienteUID = ""
	s.showNFCWaitCliente()

	s.nfcWaiting = true
	nfcSetCallbacks(NFCCallbacks{
		OnCardDetected: func(uid string) {
			if !s.nfcWaiting {
				return
			}
			s.nfcWaiting = false
			if s.waitingOperador {
				go s.completeWithOperador(uid)
			} else {
				go s.validateAndRecharge(uid)
			}
		},
	})
}

func (s *RecargaScreen) validateAndRecharge(uid string) {
	s.nfcStatusLbl.SetText("Validando tarjeta...")

	result, err := apiValidarTarjeta(uid)
	if err != nil {
		s.nfcStatusLbl.SetText("❌ " + err.Error())
		s.nfcCancelBtn.Enable()
		return
	}

	if result.MonederoCreado {
		s.nfcStatusLbl.SetText("ℹ️ Monedero creado en este capítulo. Saldo: 0.00€")
		time.Sleep(2 * time.Second)
	}

	s.clienteUID = uid

	if !s.exigirIdentificacion {
		s.postRecarga("", "")
		return
	}

	switch s.seguridadRecarga {
	case "pin":
		s.askPINAndPost()
	case "tarjeta":
		s.waitOperadorCard()
	default:
		// Flag ON but unknown mode — try legacy body; server may return 400.
		s.postRecarga("", "")
	}
}

func (s *RecargaScreen) askPINAndPost() {
	pinEntry := widget.NewPasswordEntry()
	pinEntry.SetPlaceHolder("****")
	pinEntry.Validator = func(val string) error {
		if len(val) != 4 {
			return fmt.Errorf("el PIN debe tener 4 dígitos")
		}
		for _, r := range val {
			if !unicode.IsDigit(r) {
				return fmt.Errorf("solo dígitos numéricos")
			}
		}
		return nil
	}

	// Restrict typed input to digits, max 4
	pinEntry.OnChanged = func(v string) {
		filtered := make([]rune, 0, 4)
		for _, r := range v {
			if unicode.IsDigit(r) {
				filtered = append(filtered, r)
			}
			if len(filtered) >= 4 {
				break
			}
		}
		clean := string(filtered)
		if clean != v {
			pinEntry.SetText(clean)
		}
	}

	form := dialog.NewForm(
		"Identificación requerida",
		"Confirmar",
		"Cancelar",
		[]*widget.FormItem{
			widget.NewFormItem("PIN (4 dígitos)", pinEntry),
		},
		func(ok bool) {
			if !ok {
				s.abortNFCWait()
				return
			}
			pin := pinEntry.Text
			if len(pin) != 4 {
				s.nfcStatusLbl.SetText("❌ El PIN debe tener exactamente 4 dígitos")
				s.nfcCancelBtn.Enable()
				// Re-open dialog for retry
				go func() {
					time.Sleep(300 * time.Millisecond)
					s.askPINAndPost()
				}()
				return
			}
			go s.postRecarga(pin, "")
		},
		s.win,
	)
	s.nfcStatusLbl.SetText("Introduce el PIN del operador")
	s.nfcCancelBtn.Enable()
	form.Show()
	s.win.Canvas().Focus(pinEntry)
}

func (s *RecargaScreen) waitOperadorCard() {
	s.waitingOperador = true
	s.nfcHintLbl.SetText("Acerca la tarjeta del operador")
	s.nfcStatusLbl.SetText("Esperando tarjeta del operador...")
	s.nfcCancelBtn.SetText("Cancelar")
	s.nfcCancelBtn.Enable()

	s.nfcWaiting = true
	nfcSetCallbacks(NFCCallbacks{
		OnCardDetected: func(uid string) {
			if !s.nfcWaiting || !s.waitingOperador {
				return
			}
			s.nfcWaiting = false
			go s.completeWithOperador(uid)
		},
	})
}

func (s *RecargaScreen) completeWithOperador(uidOperador string) {
	s.postRecarga("", uidOperador)
}

func (s *RecargaScreen) postRecarga(pin, uidOperador string) {
	s.nfcStatusLbl.SetText("Procesando recarga...")
	s.nfcCancelBtn.Disable()

	desc := s.descEntry.Text
	if desc == "" {
		desc = "Recarga"
	}

	saldoPost, err := apiHacerRecarga(s.clienteUID, s.montoConfirmado, desc, pin, uidOperador)
	if err != nil {
		s.handleRecargaError(err, pin != "", uidOperador != "")
		return
	}

	s.waitingOperador = false
	s.nfcStatusLbl.SetText(fmt.Sprintf("✅ Recarga realizada  ·  Saldo nuevo: %s €", saldoPost))
	if s.historial != nil {
		s.historial.Load(s.clienteUID)
	}
	s.lastTxnUID = s.clienteUID
	s.nfcCancelBtn.SetText("← Volver")
	s.nfcCancelBtn.Enable()

	gen := s.bumpLeaveGen()
	time.Sleep(2500 * time.Millisecond)
	if s.currentLeaveGen() != gen {
		return
	}
	s.finish()
}

func (s *RecargaScreen) handleRecargaError(err error, usedPIN, usedOperador bool) {
	ae, _ := err.(*APIError)
	msg := err.Error()
	code := ""
	if ae != nil {
		code = ae.Code
		if ae.Message != "" {
			msg = ae.Message
		}
	}

	s.nfcStatusLbl.SetText("❌ " + msg)
	s.nfcCancelBtn.Enable()

	switch code {
	case "PIN_INVALIDO", "IDENTIFICACION_REQUERIDA":
		if s.seguridadRecarga == "pin" || usedPIN {
			go func() {
				time.Sleep(800 * time.Millisecond)
				s.askPINAndPost()
			}()
			return
		}
		if s.seguridadRecarga == "tarjeta" || usedOperador {
			go func() {
				time.Sleep(800 * time.Millisecond)
				s.waitOperadorCard()
			}()
			return
		}
	case "TARJETA_OPERADOR_INVALIDA":
		go func() {
			time.Sleep(800 * time.Millisecond)
			s.waitOperadorCard()
		}()
		return
	case "IDENTIFICACION_MODO_INCORRECTO":
		s.nfcStatusLbl.SetText("❌ Error de cliente: modo de identificación incorrecto")
	}
}

// cancelNFC: tras éxito → Inicio; en espera/error → calculadora con importe (D1/D2).
func (s *RecargaScreen) cancelNFC() {
	if s.lastTxnUID != "" {
		s.finish()
		return
	}
	s.abortNFCWait()
}

func (s *RecargaScreen) abortNFCWait() {
	s.bumpLeaveGen()
	s.nfcWaiting = false
	s.waitingOperador = false
	s.clienteUID = ""
	s.lastTxnUID = ""
	nfcSetCallbacks(NFCCallbacks{})
	s.showCalculator()
}

func (s *RecargaScreen) finish() {
	s.bumpLeaveGen()
	uid := s.lastTxnUID
	s.lastTxnUID = ""
	s.clienteUID = ""
	s.nfcWaiting = false
	s.waitingOperador = false
	s.montoStr = ""
	nfcSetCallbacks(NFCCallbacks{})
	s.showCalculator()
	s.teardownKeyboard()
	if s.onBack != nil {
		s.onBack(uid)
	}
}

func (s *RecargaScreen) showNFCWaitCliente() {
	s.calcContainer.Hide()
	s.nfcContainer.Show()
	s.nfcHintLbl.SetText("Acerca la tarjeta al lector")
	s.nfcAmountText.Text = fmt.Sprintf("+%.2f €", s.montoConfirmado)
	s.nfcAmountText.Refresh()
	s.nfcStatusLbl.SetText("Esperando tarjeta...")
	s.nfcCancelBtn.SetText("Cancelar")
	s.nfcCancelBtn.Enable()
}

func (s *RecargaScreen) showCalculator() {
	s.nfcContainer.Hide()
	s.calcContainer.Show()
}

func (s *RecargaScreen) setMessage(text string, _ interface{}) {
	s.msgLabel.SetText(text)
	if text != "" {
		go func() {
			time.Sleep(3 * time.Second)
			s.msgLabel.SetText("")
		}()
	}
}

// ── Keypad builder ────────────────────────────────────────────────────────────

func (s *RecargaScreen) buildKeypad() fyne.CanvasObject {
	num := func(t string) *widget.Button {
		t2 := t
		return widget.NewButton(t2, func() { s.pressNum(t2) })
	}
	op := func(t string, imp widget.ButtonImportance, fn func()) *widget.Button {
		b := widget.NewButton(t, fn)
		b.Importance = imp
		return b
	}
	return container.NewGridWithColumns(4,
		num("7"), num("8"), num("9"), op("C", widget.DangerImportance, s.pressClear),
		num("4"), num("5"), num("6"), op("DEL", widget.WarningImportance, s.pressBackspace),
		num("1"), num("2"), num("3"), op("OK", widget.SuccessImportance, s.processRecarga),
		num("."), num("0"), widget.NewLabel(""), widget.NewLabel(""),
	)
}
