// screen_admin.go — Admin screen: create member + associate NFC card.
// Two tabs: "Crear Socio" and "Asociar Tarjeta".
package main

import (
	"fmt"
	"strings"
	"sync"
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"
)

type AdminScreen struct {
	win               fyne.Window
	onTarjetaAsociada func(uid string)

	// Crear Socio tab
	nombreEntry  *widget.Entry
	emailEntry   *widget.Entry
	telEntry     *widget.Entry
	saldoEntry   *widget.Entry
	crearMsg     *widget.Label
	crearBtn     *widget.Button
	irAsociarBtn *widget.Button
	crearOtroBtn *widget.Button
	socioCreado  int // numero_socio of newly created member

	// Asociar Tarjeta tab
	socios       []Socio
	sociosMu     sync.Mutex
	sociosSelect *widget.Select
	uidEntry     *widget.Entry
	asocMsg      *widget.Label
	asocBtn      *widget.Button
	asocNFCFrame *fyne.Container
	asocStatus   *widget.Label

	// NFC state for associations
	nfcWaiting  bool
	nfcNumSocio int
}

func newAdminScreen(win fyne.Window, onTarjetaAsociada func(uid string)) *AdminScreen {
	return &AdminScreen{win: win, onTarjetaAsociada: onTarjetaAsociada}
}

func (s *AdminScreen) build() fyne.CanvasObject {
	titleLbl := widget.NewLabelWithStyle(
		"Administración", fyne.TextAlignLeading, fyne.TextStyle{Bold: true},
	)

	tabs := container.NewAppTabs(
		container.NewTabItem("👤  Crear Socio", s.buildCrearSocioTab()),
		container.NewTabItem("💳  Asociar Tarjeta", s.buildAsociarTab()),
	)

	return container.NewBorder(
		container.NewPadded(titleLbl),
		nil, nil, nil,
		tabs,
	)
}

// ── Tab: Crear Socio ──────────────────────────────────────────────────────────

func (s *AdminScreen) buildCrearSocioTab() fyne.CanvasObject {
	s.nombreEntry = widget.NewEntry()
	s.nombreEntry.SetPlaceHolder("Juan García López")

	s.emailEntry = widget.NewEntry()
	s.emailEntry.SetPlaceHolder("juan@ejemplo.com")

	s.telEntry = widget.NewEntry()
	s.telEntry.SetPlaceHolder("612345678")

	s.saldoEntry = widget.NewEntry()
	s.saldoEntry.SetPlaceHolder("0.00")
	s.saldoEntry.SetText("0.00")

	s.crearMsg = widget.NewLabel("")
	s.crearMsg.Wrapping = fyne.TextWrapWord

	s.crearBtn = widget.NewButton("👤  Crear Socio", s.doCrearSocio)
	s.crearBtn.Importance = widget.HighImportance

	s.irAsociarBtn = widget.NewButton("💳  Asociar Tarjeta NFC al nuevo socio", s.irAAsociarNuevo)
	s.irAsociarBtn.Disable()

	s.crearOtroBtn = widget.NewButton("➕  Crear otro socio", s.limpiarCrear)
	s.crearOtroBtn.Importance = widget.LowImportance
	s.crearOtroBtn.Disable()

	form := container.NewVBox(
		widget.NewLabel("Nombre completo *"),
		s.nombreEntry,
		widget.NewLabel("Email (opcional)"),
		s.emailEntry,
		widget.NewLabel("Teléfono (opcional)"),
		s.telEntry,
		widget.NewLabel("Saldo inicial (€)"),
		s.saldoEntry,
		s.crearMsg,
		s.crearBtn,
		s.irAsociarBtn,
		s.crearOtroBtn,
	)
	return container.NewPadded(form)
}

func (s *AdminScreen) doCrearSocio() {
	nombre := strings.TrimSpace(s.nombreEntry.Text)
	if len(nombre) < 3 {
		s.crearMsg.SetText("❌ El nombre debe tener al menos 3 caracteres.")
		return
	}
	email := strings.TrimSpace(s.emailEntry.Text)
	tel := strings.TrimSpace(s.telEntry.Text)
	saldo := strings.TrimSpace(s.saldoEntry.Text)
	if saldo == "" {
		saldo = "0.00"
	}

	s.crearBtn.Disable()
	s.crearBtn.SetText("Creando...")

	go func() {
		result, err := apiCrearSocio(nombre, email, tel, saldo)
		s.crearBtn.Enable()
		s.crearBtn.SetText("👤  Crear Socio")
		if err != nil {
			s.crearMsg.SetText("❌ " + err.Error())
			return
		}

		numRaw := result["numero_socio"]
		num := 0
		switch v := numRaw.(type) {
		case float64:
			num = int(v)
		case int:
			num = v
		}

		s.socioCreado = num
		s.crearMsg.SetText(fmt.Sprintf("✅ Socio creado  ·  Número de socio: #%d", num))
		s.irAsociarBtn.Enable()
		s.crearOtroBtn.Enable()
		s.crearBtn.Disable()
	}()
}

func (s *AdminScreen) limpiarCrear() {
	s.nombreEntry.SetText("")
	s.emailEntry.SetText("")
	s.telEntry.SetText("")
	s.saldoEntry.SetText("0.00")
	s.socioCreado = 0
	s.crearMsg.SetText("")
	s.crearBtn.Enable()
	s.irAsociarBtn.Disable()
	s.crearOtroBtn.Disable()
}

func (s *AdminScreen) irAAsociarNuevo() {
	if s.socioCreado == 0 {
		return
	}
	numeroSocio := s.socioCreado
	s.showNFCDialog(numeroSocio)
}

// showNFCDialog shows a modal dialog while waiting for NFC card.
func (s *AdminScreen) showNFCDialog(numeroSocio int) {
	statusLbl := widget.NewLabel("Esperando tarjeta NFC...")
	statusLbl.Alignment = fyne.TextAlignCenter
	statusLbl.Wrapping = fyne.TextWrapWord

	socioLbl := widget.NewLabel(fmt.Sprintf("Socio #%d", numeroSocio))
	socioLbl.Alignment = fyne.TextAlignCenter

	content := container.NewVBox(
		widget.NewLabelWithStyle("📡", fyne.TextAlignCenter, fyne.TextStyle{}),
		widget.NewLabelWithStyle(
			"Acerca la tarjeta NFC al lector",
			fyne.TextAlignCenter,
			fyne.TextStyle{Bold: true},
		),
		socioLbl,
		statusLbl,
	)

	var dlg dialog.Dialog
	cancelBtn := widget.NewButton("Cancelar", func() {
		s.nfcWaiting = false
		nfcSetCallbacks(NFCCallbacks{})
		dlg.Hide()
	})
	cancelBtn.Importance = widget.LowImportance

	withCancel := container.NewVBox(content, container.NewCenter(cancelBtn))
	dlg = dialog.NewCustomWithoutButtons(
		"Asociar Tarjeta NFC", withCancel, s.win,
	)
	dlg.Show()

	s.nfcWaiting = true
	s.nfcNumSocio = numeroSocio
	nfcSetCallbacks(NFCCallbacks{
		OnCardDetected: func(uid string) {
			if !s.nfcWaiting {
				return
			}
			s.nfcWaiting = false
			go func() {
				statusLbl.SetText("Asociando tarjeta...")
				cancelBtn.Disable()
				err := apiAsociarTarjeta(numeroSocio, uid)
				if err != nil {
					statusLbl.SetText("❌ " + err.Error())
					cancelBtn.Enable()
					return
				}
				statusLbl.SetText("✅ Tarjeta asociada correctamente")
				time.Sleep(1500 * time.Millisecond)
				dlg.Hide()
				nfcSetCallbacks(NFCCallbacks{})
				if s.onTarjetaAsociada != nil {
					s.onTarjetaAsociada(uid)
				}
			}()
		},
	})
}

// ── Tab: Asociar Tarjeta ──────────────────────────────────────────────────────

func (s *AdminScreen) buildAsociarTab() fyne.CanvasObject {
	s.sociosSelect = widget.NewSelect([]string{"Cargando..."}, nil)

	refreshBtn := widget.NewButton("🔄  Actualizar lista", s.cargarSocios)
	refreshBtn.Importance = widget.LowImportance

	s.uidEntry = widget.NewEntry()
	s.uidEntry.SetPlaceHolder("AB:CD:EF:12 o ABCDEF12... (vacío = usar NFC)")

	s.asocMsg = widget.NewLabel("")
	s.asocMsg.Wrapping = fyne.TextWrapWord

	// NFC wait inline panel (hidden initially)
	nfcIcon := widget.NewLabel("📡")
	nfcIcon.Alignment = fyne.TextAlignCenter
	s.asocStatus = widget.NewLabel("Acerca la tarjeta NFC al lector...")
	s.asocStatus.Alignment = fyne.TextAlignCenter
	asocCancelBtn := widget.NewButton("Cancelar", s.cancelAsocNFC)
	asocCancelBtn.Importance = widget.LowImportance
	s.asocNFCFrame = container.NewVBox(
		container.NewCenter(nfcIcon),
		container.NewCenter(s.asocStatus),
		container.NewCenter(asocCancelBtn),
	)
	s.asocNFCFrame.Hide()

	s.asocBtn = widget.NewButton("💳  Asociar Tarjeta", s.doAsociarTarjeta)
	s.asocBtn.Importance = widget.HighImportance

	form := container.NewVBox(
		widget.NewLabel("Seleccionar Socio"),
		s.sociosSelect,
		refreshBtn,
		widget.NewLabel("UID manual (opcional — deja vacío para usar NFC)"),
		s.uidEntry,
		s.asocMsg,
		s.asocNFCFrame,
		s.asocBtn,
	)

	// Load socios asynchronously on first build
	go func() {
		time.Sleep(200 * time.Millisecond)
		s.cargarSocios()
	}()

	return container.NewPadded(form)
}

func (s *AdminScreen) cargarSocios() {
	s.sociosSelect.Options = []string{"Cargando..."}
	s.sociosSelect.Refresh()

	go func() {
		list, err := apiListarSocios()
		s.sociosMu.Lock()
		s.socios = list
		s.sociosMu.Unlock()

		if err != nil || len(list) == 0 {
			s.sociosSelect.Options = []string{"(sin socios)"}
			s.sociosSelect.SetSelected("(sin socios)")
			s.sociosSelect.Refresh()
			return
		}

		items := make([]string, len(list))
		for i, sc := range list {
			items[i] = fmt.Sprintf("#%d — %s", sc.NumeroSocio, sc.Nombre)
		}
		s.sociosSelect.Options = items
		s.sociosSelect.SetSelected(items[0])
		s.sociosSelect.Refresh()
	}()
}

func (s *AdminScreen) getSelectedNumeroSocio() int {
	val := s.sociosSelect.Selected
	if !strings.HasPrefix(val, "#") {
		return 0
	}
	var num int
	fmt.Sscanf(val[1:], "%d", &num)
	return num
}

func (s *AdminScreen) doAsociarTarjeta() {
	numero := s.getSelectedNumeroSocio()
	if numero == 0 {
		s.asocMsg.SetText("❌ Selecciona un socio.")
		return
	}

	uidManual := strings.TrimSpace(s.uidEntry.Text)
	if uidManual != "" {
		uid := strings.ToUpper(strings.ReplaceAll(uidManual, ":", ""))
		go s.doAsociar(numero, uid)
		return
	}

	// Wait for NFC
	s.nfcNumSocio = numero
	s.nfcWaiting = true
	s.asocNFCFrame.Show()
	s.asocBtn.Disable()
	s.asocStatus.SetText("Acerca la tarjeta NFC al lector...")
	s.asocMsg.SetText("")

	nfcSetCallbacks(NFCCallbacks{
		OnCardDetected: func(uid string) {
			if !s.nfcWaiting {
				return
			}
			s.nfcWaiting = false
			go s.doAsociar(s.nfcNumSocio, uid)
		},
	})
}

func (s *AdminScreen) doAsociar(numero int, uid string) {
	s.asocStatus.SetText("Asociando tarjeta...")
	err := apiAsociarTarjeta(numero, uid)
	if err != nil {
		s.asocMsg.SetText("❌ " + err.Error())
		s.asocNFCFrame.Hide()
		s.asocBtn.Enable()
		return
	}
	s.asocStatus.SetText("✅ Tarjeta asociada correctamente")
	time.Sleep(1500 * time.Millisecond)
	nfcSetCallbacks(NFCCallbacks{})
	if s.onTarjetaAsociada != nil {
		s.onTarjetaAsociada(uid)
	}
}

func (s *AdminScreen) cancelAsocNFC() {
	s.nfcWaiting = false
	nfcSetCallbacks(NFCCallbacks{})
	s.asocNFCFrame.Hide()
	s.asocBtn.Enable()
}
