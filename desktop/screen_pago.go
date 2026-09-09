// screen_pago.go — Payment calculator with NFC confirmation.
// Left: calculator (ops display + numpad + historial). Right: price list items.
package main

import (
	"bytes"
	"fmt"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/layout"
	"fyne.io/fyne/v2/widget"
)

type pagoOpSnapshot struct {
	displayOps      string
	total           float64
	multiplyPending bool
	multiplyVal     float64
}

type PagoScreen struct {
	win         fyne.Window
	getCardInfo func() map[string]interface{}
	onBack      func(uid string) // uid vacío = cancelar; no vacío = tarjeta usada

	// Calculator state
	mu              sync.Mutex
	displayOps      string
	numActual       string
	total           float64
	multiplyPending bool
	multiplyVal     float64
	opStack         []pagoOpSnapshot // undo history (one entry per committed "+")

	// NFC payment state
	nfcWaiting      bool
	montoConfirmado float64
	lastTxnUID      string // UID del último cobro exitoso (para Volver / auto-retorno)
	leaveGen        atomic.Uint64 // invalida auto-retorno pendiente

	// UI widgets
	opsDisplay     *widget.Label
	opsScroll      *container.Scroll
	totalDisplay   *canvas.Text
	msgLabel       *widget.Label
	descEntry      *widget.Entry
	cardNameLbl    *widget.Label
	cardSaldoText  *canvas.Text
	calcContainer  *fyne.Container
	nfcContainer   *fyne.Container
	nfcAmountText  *canvas.Text
	nfcStatusLbl   *widget.Label
	nfcCancelBtn   *widget.Button
	historial      *HistorialWidget

	// Price list panel
	listaSelect   *widget.Select
	itemsPanel    *fyne.Container
	itemsScroll   *container.Scroll
	selectedLista int
}

func newPagoScreen(win fyne.Window, getCardInfo func() map[string]interface{}, onBack func(uid string)) *PagoScreen {
	return &PagoScreen{win: win, getCardInfo: getCardInfo, onBack: onBack}
}

// OnShow is called when the screen becomes active.
func (s *PagoScreen) OnShow() {
	s.nfcWaiting = false
	s.lastTxnUID = ""
	nfcSetCallbacks(NFCCallbacks{})
	if s.calcContainer != nil {
		s.showCalculator()
	}
	s.refreshCardHeader()
	s.refreshPriceListsIfNeeded()

	info := s.getCardInfo()
	uid, _ := info["uid"].(string)
	if uid != "" && s.historial != nil {
		s.historial.Load(uid)
	} else if s.historial != nil {
		s.historial.Clear()
	}
	s.setupKeyboard()
}

// OnHide clears keyboard and NFC wait when leaving via sidebar.
func (s *PagoScreen) OnHide() {
	s.bumpLeaveGen()
	s.nfcWaiting = false
	s.lastTxnUID = ""
	s.teardownKeyboard()
	nfcSetCallbacks(NFCCallbacks{})
	if s.calcContainer != nil {
		s.showCalculator()
	}
}

func (s *PagoScreen) bumpLeaveGen() uint64 {
	return s.leaveGen.Add(1)
}

func (s *PagoScreen) currentLeaveGen() uint64 {
	return s.leaveGen.Load()
}

func (s *PagoScreen) refreshCardHeader() {
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
	s.cardSaldoText.Text = fmt.Sprintf("Saldo: %.2f €", saldo)
	s.cardSaldoText.Refresh()
}

func (s *PagoScreen) refreshPriceListsIfNeeded() {
	info := apiGetDeviceInfo()
	if info.CapituloID == 0 || !listasIsStale(info.CapituloID) {
		return
	}
	capID := info.CapituloID
	go func() {
		listasLoadCache(capID)
		if s.listaSelect == nil || s.itemsPanel == nil {
			return
		}
		listas := listasGetAll()
		if len(listas) == 0 {
			return
		}
		options := make([]string, len(listas))
		for i, l := range listas {
			options[i] = l.Nombre
		}
		prev := s.listaSelect.Selected
		s.listaSelect.Options = options
		found := false
		for _, o := range options {
			if o == prev {
				s.listaSelect.SetSelected(prev)
				found = true
				break
			}
		}
		if !found {
			s.listaSelect.SetSelected(options[0])
		}
		s.listaSelect.Refresh()
		if s.selectedLista != 0 {
			s.renderItems(s.selectedLista)
		}
	}()
}

func (s *PagoScreen) setupKeyboard() {
	s.win.Canvas().SetOnTypedRune(func(r rune) {
		if s.nfcWaiting || s.win.Canvas().Focused() != nil {
			return
		}
		switch r {
		case '0', '1', '2', '3', '4', '5', '6', '7', '8', '9':
			s.pressNum(string(r))
		case '.', ',':
			s.pressNum(".")
		case '+':
			s.pressAdd()
		case '*':
			s.pressMultiply()
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
				s.processPago()
			}
		}
	})
}

func (s *PagoScreen) teardownKeyboard() {
	s.win.Canvas().SetOnTypedRune(nil)
	s.win.Canvas().SetOnTypedKey(nil)
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
	s.cardNameLbl = widget.NewLabelWithStyle(nombre, fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	saldoColor := colorRed
	if saldo > 0 {
		saldoColor = colorGreen
	}
	s.cardSaldoText = canvas.NewText(fmt.Sprintf("Saldo: %.2f €", saldo), saldoColor)
	s.cardSaldoText.TextSize = 14
	cardHeader := widget.NewCard("", "", container.NewVBox(s.cardNameLbl, s.cardSaldoText))

	// ── Description entry ─────────────────────────────────────────────────────
	s.descEntry = widget.NewEntry()
	s.descEntry.SetPlaceHolder("Descripción (opcional)")

	// ── Ops display (una sola línea: lo nuevo a la derecha, lo viejo se oculta) ─
	s.opsDisplay = widget.NewLabel("")
	s.opsDisplay.Alignment = fyne.TextAlignTrailing
	s.opsDisplay.Wrapping = fyne.TextWrapOff
	s.opsScroll = container.NewHScroll(s.opsDisplay)
	s.opsScroll.Direction = container.ScrollHorizontalOnly
	// Altura fija de una línea para que no empuje el teclado/historial
	s.opsScroll.SetMinSize(fyne.NewSize(80, 28))

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
		s.nfcStatusLbl,
		container.NewCenter(s.nfcCancelBtn),
	)

	// ── Left panel: calculator arriba (altura natural), historial abajo expandible ──
	leftContent := container.NewStack(s.calcContainer, s.nfcContainer)
	s.nfcContainer.Hide()

	s.historial = newHistorialWidget("📋 Últimos cobros", "COBRO")
	if uid != "" {
		s.historial.Load(uid)
	}

	leftPanel := container.NewBorder(
		container.NewVBox(
			cardHeader, s.descEntry, s.opsScroll, totalRow, s.msgLabel,
			leftContent,
		),
		nil, nil, nil,
		container.NewPadded(s.historial.CanvasObject()),
	)

	// ── Right panel: price lists or fallback to empty ─────────────────────────
	rightPanel := s.buildPriceListPanel()

	split := container.NewHSplit(leftPanel, rightPanel)
	split.Offset = 0.50
	return split
}

// buildPriceListPanel creates the right panel with dropdown + scrollable item list.
func (s *PagoScreen) buildPriceListPanel() fyne.CanvasObject {
	listas := listasGetAll()
	if len(listas) == 0 {
		// No price lists available — show placeholder
		noListas := widget.NewLabelWithStyle(
			"Sin listas de precios", fyne.TextAlignCenter, fyne.TextStyle{Italic: true},
		)
		return container.NewCenter(noListas)
	}

	// Build dropdown options
	options := make([]string, len(listas))
	for i, l := range listas {
		options[i] = l.Nombre
	}

	s.itemsPanel = container.NewVBox()
	// Scroll acotado por el Border/HSplit (mismo patrón que el historial).
	// No fijar MinSize alto: si no, el panel crece con el contenido y no aparece barra.
	s.itemsScroll = container.NewScroll(s.itemsPanel)
	s.itemsScroll.Direction = container.ScrollVerticalOnly

	s.listaSelect = widget.NewSelect(options, func(selected string) {
		for _, l := range listas {
			if l.Nombre == selected {
				s.selectedLista = l.ID
				s.renderItems(l.ID)
				break
			}
		}
	})
	s.listaSelect.PlaceHolder = "Seleccionar lista..."

	// Auto-select first list
	if len(listas) > 0 {
		s.listaSelect.SetSelected(listas[0].Nombre)
	}

	header := widget.NewLabelWithStyle("🛒 Carta", fyne.TextAlignLeading, fyne.TextStyle{Bold: true})
	return container.NewBorder(
		container.NewVBox(header, s.listaSelect),
		nil, nil, nil,
		s.itemsScroll,
	)
}

// renderItems populates the items panel with buttons for the selected list.
func (s *PagoScreen) renderItems(listaID int) {
	s.itemsPanel.RemoveAll()

	detalle := listasGetDetalle(listaID)
	if detalle == nil {
		s.itemsPanel.Add(widget.NewLabel("Error cargando items"))
		s.itemsPanel.Refresh()
		return
	}

	for _, item := range detalle.Items {
		item := item // capture
		precio, _ := strconv.ParseFloat(item.Precio, 64)

		// Build row: [icon] Name ........... Price
		var row fyne.CanvasObject

		nameTxt := widget.NewLabel(item.Nombre)
		nameTxt.Wrapping = fyne.TextTruncate
		priceTxt := widget.NewLabelWithStyle(
			fmt.Sprintf("%.2f €", precio),
			fyne.TextAlignTrailing,
			fyne.TextStyle{Bold: true},
		)

		// Try to render icon
		iconData := listasGetIcono(item.ID)
		if len(iconData) > 0 {
			img := canvas.NewImageFromReader(bytes.NewReader(iconData), fmt.Sprintf("item_%d", item.ID))
			img.SetMinSize(fyne.NewSize(24, 24))
			img.FillMode = canvas.ImageFillContain
			row = container.NewBorder(nil, nil, img, priceTxt, nameTxt)
		} else {
			row = container.NewBorder(nil, nil, nil, priceTxt, nameTxt)
		}

		btn := widget.NewButton("", func() {
			s.addItemToTotal(item.Nombre, precio)
		})
		btn.Importance = widget.LowImportance

		// Stack the row content over an invisible button for tap handling
		tappable := container.NewStack(btn, container.New(layout.NewPaddedLayout(), row))
		s.itemsPanel.Add(tappable)
	}
	s.itemsPanel.Refresh()
	if s.itemsScroll != nil {
		s.itemsScroll.Offset = fyne.NewPos(0, 0)
		s.itemsScroll.Refresh()
	}
}

// addItemToTotal adds an item price to the calculator total (equivalent to typing + price).
func (s *PagoScreen) addItemToTotal(nombre string, precio float64) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// If there's a pending number entry, commit it first
	if s.numActual != "" {
		val, _ := strconv.ParseFloat(s.numActual, 64)
		if s.multiplyPending {
			val = s.multiplyVal * val
			s.multiplyPending = false
			s.multiplyVal = 0
		}
		s.opStack = append(s.opStack, pagoOpSnapshot{
			displayOps:      s.displayOps,
			total:           s.total,
			multiplyPending: s.multiplyPending,
			multiplyVal:     s.multiplyVal,
		})
		s.total += val
		s.displayOps += s.numActual + " + "
		s.numActual = ""
	}

	// Snapshot before adding item
	s.opStack = append(s.opStack, pagoOpSnapshot{
		displayOps:      s.displayOps,
		total:           s.total,
		multiplyPending: s.multiplyPending,
		multiplyVal:     s.multiplyVal,
	})

	// If there's a pending multiply (e.g. "3*"), apply it to the item price
	if s.multiplyPending {
		cantidad := s.multiplyVal
		s.total += cantidad * precio
		s.displayOps += fmt.Sprintf("%.0f*%s(%.2f) + ", cantidad, nombre, precio)
		s.multiplyPending = false
		s.multiplyVal = 0
	} else {
		s.total += precio
		s.displayOps += fmt.Sprintf("%s(%.2f) + ", nombre, precio)
	}
	s.refreshDisplay()
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
	// Snapshot state before this "+" (including any pending ×) for undo.
	s.opStack = append(s.opStack, pagoOpSnapshot{
		displayOps:      s.displayOps,
		total:           s.total,
		multiplyPending: s.multiplyPending,
		multiplyVal:     s.multiplyVal,
	})
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
	// Snapshot state before this "×" so backspace can undo it.
	s.opStack = append(s.opStack, pagoOpSnapshot{
		displayOps:      s.displayOps,
		total:           s.total,
		multiplyPending: false,
		multiplyVal:     0,
	})
	s.multiplyVal, _ = strconv.ParseFloat(s.numActual, 64)
	s.displayOps += s.numActual + " × "
	s.numActual = ""
	s.multiplyPending = true
	s.refreshDisplay()
}

func (s *PagoScreen) pressBackspace() {
	s.mu.Lock()
	defer s.mu.Unlock()
	popStack := func() {
		if len(s.opStack) > 0 {
			top := s.opStack[len(s.opStack)-1]
			s.opStack = s.opStack[:len(s.opStack)-1]
			s.displayOps = top.displayOps
			s.total = top.total
			s.multiplyPending = top.multiplyPending
			s.multiplyVal = top.multiplyVal
		} else {
			s.displayOps = ""
			s.total = 0
			s.multiplyPending = false
			s.multiplyVal = 0
		}
	}
	if s.multiplyPending {
		// Cancel the entire × group (numActual + the pending ×), restore to before ×.
		s.numActual = ""
		s.multiplyPending = false
		s.multiplyVal = 0
		popStack()
	} else if s.numActual != "" {
		// Just discard the number being typed; keep committed state.
		s.numActual = ""
	} else {
		// Nothing in progress: undo the last committed "+".
		popStack()
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
	s.opStack = nil
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
	s.opsDisplay.Refresh()
	// Mostrar el final de la cinta (lo más reciente); al borrar reaparece lo anterior
	if s.opsScroll != nil {
		s.opsScroll.Refresh()
		viewW := s.opsScroll.Size().Width
		contentW := s.opsDisplay.MinSize().Width
		if viewW > 0 && contentW > viewW {
			s.opsScroll.Offset = fyne.NewPos(contentW-viewW, 0)
		} else {
			s.opsScroll.Offset = fyne.NewPos(0, 0)
		}
		s.opsScroll.Refresh()
	}
	t := s.totalCalculado()
	if t > 0 {
		s.totalDisplay.Color = colorGreen
	} else {
		s.totalDisplay.Color = colorGray
	}
	s.totalDisplay.Text = fmt.Sprintf("%.2f €", t)
	s.totalDisplay.Refresh()
}

// cadenaOperaciones returns the committed calculator chain (displayOps) for the API.
func (s *PagoScreen) cadenaOperaciones() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	cadena := strings.TrimSpace(s.displayOps + s.numActual)
	cadena = strings.TrimSuffix(cadena, "+")
	cadena = strings.TrimSpace(cadena)
	if len(cadena) > 1000 {
		cadena = cadena[:1000]
	}
	return cadena
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
	s.bumpLeaveGen()
	s.lastTxnUID = ""
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

	if result.MonederoCreado {
		s.nfcStatusLbl.SetText("ℹ️ Monedero creado en este capítulo. Saldo: 0.00€")
		time.Sleep(2 * time.Second)
	}

	s.nfcStatusLbl.SetText("Procesando pago...")
	desc := s.descEntry.Text
	if desc == "" {
		desc = "Pago"
	}
	operaciones := s.cadenaOperaciones()
	saldoPost, err := apiHacerPago(uid, s.montoConfirmado, desc, operaciones)
	if err != nil {
		s.nfcStatusLbl.SetText("❌ " + err.Error())
		s.nfcCancelBtn.Enable()
		return
	}

	s.nfcStatusLbl.SetText(fmt.Sprintf("✅ Pago realizado  ·  Saldo nuevo: %s €", saldoPost))
	if s.historial != nil {
		s.historial.Load(uid)
	}
	s.lastTxnUID = uid
	s.nfcCancelBtn.SetText("← Volver")
	s.nfcCancelBtn.Enable()

	gen := s.bumpLeaveGen()
	time.Sleep(2500 * time.Millisecond)
	if s.currentLeaveGen() != gen {
		return
	}
	s.leaveToHome()
}

// cancelNFC: tras éxito → Inicio; en espera/error → calculadora con importe (D1/D2).
func (s *PagoScreen) cancelNFC() {
	if s.lastTxnUID != "" {
		s.leaveToHome()
		return
	}
	s.abortNFCWait()
}

// abortNFCWait vuelve a la calculadora sin borrar el importe ni ir a Inicio.
func (s *PagoScreen) abortNFCWait() {
	s.bumpLeaveGen()
	s.nfcWaiting = false
	s.lastTxnUID = ""
	nfcSetCallbacks(NFCCallbacks{})
	s.showCalculator()
}

func (s *PagoScreen) leaveToHome() {
	s.bumpLeaveGen()
	uid := s.lastTxnUID
	s.lastTxnUID = ""
	s.nfcWaiting = false
	s.pressClear()
	s.showCalculator()
	s.teardownKeyboard()
	nfcSetCallbacks(NFCCallbacks{})
	if s.onBack != nil {
		s.onBack(uid)
	}
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
