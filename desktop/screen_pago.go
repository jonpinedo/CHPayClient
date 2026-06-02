// screen_pago.go — Payment calculator with NFC confirmation.
// Left: calculator (ops display + numpad). Right: historial.
package main

import (
	"fmt"
	"strconv"
	"strings"
	"sync"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

type PagoScreen struct {
	win         fyne.Window
	getCardInfo func() map[string]interface{}
	onBack      func()

	// Calculator state
	mu              sync.Mutex
	displayOps      string
	numActual       string
	total           float64
	multiplyPending bool
	multiplyVal     float64

	// NFC payment state
	nfcWaiting      bool
	montoConfirmado float64

	// UI widgets
	opsDisplay    *widget.Label
	totalDisplay  *canvas.Text
	msgLabel      *widget.Label
	descEntry     *widget.Entry
	calcContainer *fyne.Container
	nfcContainer  *fyne.Container
	nfcAmountText *canvas.Text
	nfcStatusLbl  *widget.Label
	nfcCancelBtn  *widget.Button
	historial     *HistorialWidget
}

func newPagoScreen(win fyne.Window, getCardInfo func() map[string]interface{}, onBack func()) *PagoScreen {
	return &PagoScreen{win: win, getCardInfo: getCardInfo, onBack: onBack}
}

// OnShow is called when the screen becomes active.
func (s *PagoScreen) OnShow() {
	info := s.getCardInfo()
	uid, _ := info["uid"].(string)
	if uid != "" && s.historial != nil {
		s.historial.Load(uid)
	} else if s.historial != nil {
		s.historial.Clear()
	}
}

func (s *PagoScreen) build() fyne.CanvasObject {
	info := s.getCardInfo()
	nombre, _ := info["nombre"].(string)
	saldo, _ := info["saldo"].(float64)
	uid, _ := info["uid"].(string)

	if nombre == "" {
		nombre = "Sin tarjeta leída"
	}

	// ── Card info header ──────────────────────────────────────────────────────
	nameLbl := widget.NewLabelWithStyle(nombre, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	saldoColor := colorRed
	if saldo > 0 {
		saldoColor = colorGreen
	}
	saldoText := canvas.NewText(fmt.Sprintf("Saldo: %.2f €", saldo), saldoColor)
	saldoText.TextSize = 14
	cardHeader := widget.NewCard("", "", container.NewVBox(nameLbl, saldoText))

	// ── Description entry ─────────────────────────────────────────────────────
	s.descEntry = widget.NewEntry()
	s.descEntry.SetPlaceHolder("Descripción (opcional)")

	// ── Ops display ───────────────────────────────────────────────────────────
	s.opsDisplay = widget.NewLabel("")
	s.opsDisplay.Alignment = fyne.TextAlignTrailing

	// ── Total display ─────────────────────────────────────────────────────────
	s.totalDisplay = canvas.NewText("0.00 €", colorGray)
	s.totalDisplay.TextSize = 44
	s.totalDisplay.TextStyle = fyne.TextStyle{Bold: true}
	totalRow := container.NewBorder(nil, nil, nil, s.totalDisplay, nil)

	// ── Message label ─────────────────────────────────────────────────────────
	s.msgLabel = widget.NewLabel("")
	s.msgLabel.Alignment = fyne.TextAlignCenter

	// ── Keypad ────────────────────────────────────────────────────────────────
	keypad := s.buildKeypad()
	s.calcContainer = container.NewVBox(keypad)

	// ── NFC wait panel (initially hidden) ────────────────────────────────────
	nfcIcon := widget.NewLabelWithStyle("📡", fyne.TextAlignCenter, fyne.TextStyle{})
	nfcHint := widget.NewLabelWithStyle(
		"Acerca la tarjeta al lector", fyne.TextAlignCenter, fyne.TextStyle{Bold: true},
	)
	s.nfcAmountText = canvas.NewText("", colorRed)
	s.nfcAmountText.TextSize = 36
	s.nfcAmountText.TextStyle = fyne.TextStyle{Bold: true}
	nfcAmountRow := container.NewCenter(s.nfcAmountText)

	s.nfcStatusLbl = widget.NewLabel("")
	s.nfcStatusLbl.Alignment = fyne.TextAlignCenter
	s.nfcStatusLbl.Wrapping = fyne.TextWrapWord

	s.nfcCancelBtn = widget.NewButton("Cancelar", s.cancelNFC)
	s.nfcCancelBtn.Importance = widget.LowImportance

	s.nfcContainer = container.NewVBox(
		container.NewCenter(nfcIcon),
		container.NewCenter(nfcHint),
		nfcAmountRow,
		container.NewCenter(s.nfcStatusLbl),
		container.NewCenter(s.nfcCancelBtn),
	)

	// ── Left panel: calculator or NFC wait ────────────────────────────────────
	leftContent := container.NewStack(s.calcContainer, s.nfcContainer)
	s.nfcContainer.Hide()

	leftPanel := container.NewBorder(
		container.NewVBox(cardHeader, s.descEntry, s.opsDisplay, totalRow, s.msgLabel),
		nil, nil, nil,
		leftContent,
	)

	// ── Right panel: historial ────────────────────────────────────────────────
	s.historial = newHistorialWidget("📋  Historial de pagos")
	if uid != "" {
		s.historial.Load(uid)
	}

	split := container.NewHSplit(leftPanel, container.NewPadded(s.historial.CanvasObject()))
	split.Offset = 0.58
	return split
}

// ── Calculator logic ──────────────────────────────────────────────────────────

func (s *PagoScreen) pressNum(n string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if n == "." && strings.Contains(s.numActual, ".") {
		return
	}
	s.numActual += n
	s.refreshDisplay()
}

func (s *PagoScreen) pressAdd() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.numActual == "" {
		return
	}
	val, _ := strconv.ParseFloat(s.numActual, 64)
	if s.multiplyPending {
		val = s.multiplyVal * val
		s.multiplyPending = false
		s.multiplyVal = 0
	}
	s.total += val
	s.displayOps += s.numActual + " + "
	s.numActual = ""
	s.refreshDisplay()
}

func (s *PagoScreen) pressMultiply() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.numActual == "" {
		return
	}
	s.multiplyVal, _ = strconv.ParseFloat(s.numActual, 64)
	s.displayOps += s.numActual + " × "
	s.numActual = ""
	s.multiplyPending = true
	s.refreshDisplay()
}

func (s *PagoScreen) pressBackspace() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.numActual) > 0 {
		s.numActual = s.numActual[:len(s.numActual)-1]
	}
	s.refreshDisplay()
}

func (s *PagoScreen) pressClear() {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.displayOps = ""
	s.numActual = ""
	s.total = 0
	s.multiplyPending = false
	s.multiplyVal = 0
	s.refreshDisplay()
}

// totalCalculado returns the current running total including unsaved numActual.
func (s *PagoScreen) totalCalculado() float64 {
	result := s.total
	if s.numActual != "" {
		val, _ := strconv.ParseFloat(s.numActual, 64)
		if s.multiplyPending {
			result += s.multiplyVal * val
		} else {
			result += val
		}
	}
	return result
}

func (s *PagoScreen) refreshDisplay() {
	ops := s.displayOps + s.numActual
	if s.multiplyPending {
		ops += " (× pendiente)"
	}
	s.opsDisplay.SetText(ops)
	t := s.totalCalculado()
	if t > 0 {
		s.totalDisplay.Color = colorGreen
	} else {
		s.totalDisplay.Color = colorGray
	}
	s.totalDisplay.Text = fmt.Sprintf("%.2f €", t)
	s.totalDisplay.Refresh()
}

// ── Payment flow ──────────────────────────────────────────────────────────────

func (s *PagoScreen) processPago() {
	s.mu.Lock()
	monto := s.totalCalculado()
	s.mu.Unlock()

	if monto <= 0 {
		s.setMessage("Ingresa un monto mayor que cero.", colorRed)
		return
	}
	s.montoConfirmado = monto
	s.showNFCWait()

	s.nfcWaiting = true
	nfcSetCallbacks(NFCCallbacks{
		OnCardDetected: func(uid string) {
			if !s.nfcWaiting {
				return
			}
			s.nfcWaiting = false
			go s.validateAndPay(uid)
		},
	})
}

func (s *PagoScreen) validateAndPay(uid string) {
	s.nfcStatusLbl.SetText("Validando tarjeta...")

	result, err := apiValidarTarjeta(uid)
	if err != nil {
		s.nfcStatusLbl.SetText("❌ " + err.Error())
		s.nfcCancelBtn.Enable()
		return
	}

	saldo, _ := strconv.ParseFloat(result.Saldo, 64)
	if s.montoConfirmado > saldo {
		s.nfcStatusLbl.SetText(fmt.Sprintf("❌ Saldo insuficiente (%.2f €)", saldo))
		s.nfcCancelBtn.Enable()
		return
	}

	s.nfcStatusLbl.SetText("Procesando pago...")
	desc := s.descEntry.Text
	if desc == "" {
		desc = "Pago"
	}
	saldoPost, err := apiHacerPago(uid, s.montoConfirmado, desc)
	if err != nil {
		s.nfcStatusLbl.SetText("❌ " + err.Error())
		s.nfcCancelBtn.Enable()
		return
	}

	s.nfcStatusLbl.SetText(fmt.Sprintf("✅ Pago realizado  ·  Saldo nuevo: %s €", saldoPost))
	if s.historial != nil {
		s.historial.Load(uid)
	}
	s.nfcCancelBtn.SetText("← Volver")
	s.nfcCancelBtn.Enable()

	time.Sleep(2500 * time.Millisecond)
	s.resetToCalculator()
}

func (s *PagoScreen) cancelNFC() {
	s.nfcWaiting = false
	s.pressClear()
	s.showCalculator()
	s.onBack()
}

func (s *PagoScreen) resetToCalculator() {
	s.nfcWaiting = false
	s.pressClear()
	s.showCalculator()
	s.onBack()
}

func (s *PagoScreen) showNFCWait() {
	s.calcContainer.Hide()
	s.nfcContainer.Show()
	s.nfcAmountText.Text = fmt.Sprintf("%.2f €", s.montoConfirmado)
	s.nfcAmountText.Refresh()
	s.nfcStatusLbl.SetText("Esperando tarjeta...")
	s.nfcCancelBtn.SetText("Cancelar")
	s.nfcCancelBtn.Enable()
}

func (s *PagoScreen) showCalculator() {
	s.nfcContainer.Hide()
	s.calcContainer.Show()
}

func (s *PagoScreen) setMessage(text string, col interface{}) {
	s.msgLabel.SetText(text)
	if text != "" {
		go func() {
			time.Sleep(3 * time.Second)
			s.msgLabel.SetText("")
		}()
	}
}

// ── Keypad builder ────────────────────────────────────────────────────────────

func (s *PagoScreen) buildKeypad() fyne.CanvasObject {
	num := func(t string) *widget.Button {
		t2 := t
		b := widget.NewButton(t2, func() { s.pressNum(t2) })
		return b
	}
	op := func(t string, imp widget.ButtonImportance, fn func()) *widget.Button {
		b := widget.NewButton(t, fn)
		b.Importance = imp
		return b
	}

	okBtn := op("OK", widget.DangerImportance, s.processPago)

	return container.NewGridWithColumns(4,
		num("7"), num("8"), num("9"), op("C", widget.DangerImportance, s.pressClear),
		num("4"), num("5"), num("6"), op("DEL", widget.WarningImportance, s.pressBackspace),
		num("1"), num("2"), num("3"), op("+", widget.WarningImportance, s.pressAdd),
		num("."), num("0"), op("×", widget.WarningImportance, s.pressMultiply), okBtn,
	)
}


