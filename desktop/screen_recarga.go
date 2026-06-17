// screen_recarga.go — Recharge screen.
// Left: quick amount buttons + numpad + NFC confirmation. Right: historial.
package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

var montosRapidos = []float64{5, 10, 20, 50}

type RecargaScreen struct {
	win         fyne.Window
	getCardInfo func() map[string]interface{}
	onBack      func()

	// State
	montoStr        string
	nfcWaiting      bool
	montoConfirmado float64

	// UI
	displayLbl    *canvas.Text
	msgLabel      *widget.Label
	descEntry     *widget.Entry
	calcContainer *fyne.Container
	nfcContainer  *fyne.Container
	nfcAmountText *canvas.Text
	nfcStatusLbl  *widget.Label
	nfcCancelBtn  *widget.Button
	historial     *HistorialWidget
}

func newRecargaScreen(win fyne.Window, getCardInfo func() map[string]interface{}, onBack func()) *RecargaScreen {
	return &RecargaScreen{win: win, getCardInfo: getCardInfo, onBack: onBack}
}

// OnShow is called when the screen becomes active.
func (s *RecargaScreen) OnShow() {
	info := s.getCardInfo()
	uid, _ := info["uid"].(string)
	if uid != "" && s.historial != nil {
		s.historial.Load(uid)
	} else if s.historial != nil {
		s.historial.Clear()
	}
	s.setupKeyboard()
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
	nameLbl := widget.NewLabelWithStyle(nombre, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	saldoColor := colorRed
	if saldo > 0 {
		saldoColor = colorGreen
	}
	saldoText := canvas.NewText(fmt.Sprintf("Saldo actual: %.2f €", saldo), saldoColor)
	saldoText.TextSize = 14
	cardHeader := widget.NewCard("", "", container.NewVBox(nameLbl, saldoText))

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
	nfcHint := widget.NewLabelWithStyle(
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
		container.NewCenter(nfcHint),
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
	s.historial = newHistorialWidget("📋  Historial de recargas")
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
	s.montoConfirmado = monto
	s.showNFCWait()

	s.nfcWaiting = true
	nfcSetCallbacks(NFCCallbacks{
		OnCardDetected: func(uid string) {
			if !s.nfcWaiting {
				return
			}
			s.nfcWaiting = false
			go s.validateAndRecharge(uid)
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

	s.nfcStatusLbl.SetText("Procesando recarga...")
	desc := s.descEntry.Text
	if desc == "" {
		desc = "Recarga"
	}
	saldoPost, err := apiHacerRecarga(uid, s.montoConfirmado, desc)
	if err != nil {
		s.nfcStatusLbl.SetText("❌ " + err.Error())
		s.nfcCancelBtn.Enable()
		return
	}

	s.nfcStatusLbl.SetText(fmt.Sprintf("✅ Recarga realizada  ·  Saldo nuevo: %s €", saldoPost))
	if s.historial != nil {
		s.historial.Load(uid)
	}
	s.nfcCancelBtn.SetText("← Volver")
	s.nfcCancelBtn.Enable()

	time.Sleep(2500 * time.Millisecond)
	s.finish()
}

func (s *RecargaScreen) cancelNFC() {
	s.nfcWaiting = false
	s.finish()
}

func (s *RecargaScreen) finish() {
	s.nfcWaiting = false
	s.montoStr = ""
	s.showCalculator()
	s.teardownKeyboard()
	s.onBack()
}

func (s *RecargaScreen) showNFCWait() {
	s.calcContainer.Hide()
	s.nfcContainer.Show()
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
