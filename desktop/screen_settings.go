// screen_settings.go — Settings screen: API URL, device info, credentials.
package main

import (
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"
)

type SettingsScreen struct {
	win       fyne.Window
	onLogout  func()
	urlEntry  *widget.Entry
	urlMsg    *widget.Label
	nameEntry *widget.Entry

	nfcReaderStatus *widget.Label
	nfcReaderSelect *widget.Select
	nfcSelectBusy   bool
	onNFCStatus     func(reader string)
}

func newSettingsScreen(win fyne.Window, onLogout func()) *SettingsScreen {
	return &SettingsScreen{win: win, onLogout: onLogout}
}

func (s *SettingsScreen) build() fyne.CanvasObject {
	titleLbl := widget.NewLabelWithStyle(
		"Configuración", fyne.TextAlignLeading, fyne.TextStyle{Bold: true},
	)

	return container.NewBorder(
		container.NewPadded(titleLbl),
		nil, nil, nil,
		container.NewPadded(container.NewVBox(
			s.buildAPISection(),
			s.buildNFCSection(),
			s.buildDeviceSection(),
			s.buildCredentialsSection(),
		)),
	)
}

// ── API URL section ───────────────────────────────────────────────────────────

func (s *SettingsScreen) buildAPISection() fyne.CanvasObject {
	s.urlEntry = widget.NewEntry()
	s.urlEntry.SetText(configGetAPIURL())

	s.urlMsg = widget.NewLabel("")
	s.urlMsg.Alignment = fyne.TextAlignLeading

	saveBtn := widget.NewButton("💾  Guardar URL", s.saveURL)
	saveBtn.Importance = widget.HighImportance

	testBtn := widget.NewButton("🔍  Probar conexión", s.testConnection)
	testBtn.Importance = widget.LowImportance

	buttons := container.NewHBox(saveBtn, testBtn)

	return widget.NewCard("🌐  URL de la API", "", container.NewVBox(
		widget.NewLabel("URL:"),
		s.urlEntry,
		buttons,
		s.urlMsg,
	))
}

func (s *SettingsScreen) saveURL() {
	url := strings.TrimRight(strings.TrimSpace(s.urlEntry.Text), "/")
	if url == "" {
		s.urlMsg.SetText("❌ URL vacía.")
		return
	}
	configSetAPIURL(url)
	s.urlMsg.SetText("✅ URL guardada.")
}

func (s *SettingsScreen) testConnection() {
	s.urlMsg.SetText("Probando...")
	url := strings.TrimRight(strings.TrimSpace(s.urlEntry.Text), "/")
	configSetAPIURL(url)

	go func() {
		ok := apiCheckHealth()
		if ok {
			s.urlMsg.SetText("✅ API accesible.")
		} else {
			s.urlMsg.SetText("❌ No se puede conectar a la API.")
		}
	}()
}

// setNFCStatusCallback updates the sidebar when the user picks a reader here.
func (s *SettingsScreen) setNFCStatusCallback(fn func(reader string)) {
	s.onNFCStatus = fn
}

// OnShow refreshes the NFC reader list when opening Config.
func (s *SettingsScreen) OnShow() {
	s.refreshNFCSection(nfcGetAvailableReaders())
}

// ── NFC reader section ────────────────────────────────────────────────────────

func (s *SettingsScreen) buildNFCSection() fyne.CanvasObject {
	s.nfcReaderStatus = widget.NewLabel("Comprobando lectores...")
	s.nfcReaderStatus.Wrapping = fyne.TextWrapWord

	s.nfcReaderSelect = widget.NewSelect([]string{}, func(selected string) {
		if s.nfcSelectBusy {
			return
		}
		nfcSetSelectedReader(selected)
		s.nfcReaderStatus.SetText("Lector activo: " + selected)
		if s.onNFCStatus != nil {
			s.onNFCStatus(selected)
		}
	})
	s.nfcReaderSelect.Hide()

	hint := widget.NewLabel(
		"Si hay varios lectores conectados al PC, elige cuál usar. La preferencia se guarda automáticamente.",
	)
	hint.Wrapping = fyne.TextWrapWord

	s.refreshNFCSection(nfcGetAvailableReaders())

	return widget.NewCard("📡  Lector NFC", "", container.NewVBox(
		s.nfcReaderStatus,
		s.nfcReaderSelect,
		hint,
	))
}

func (s *SettingsScreen) refreshNFCSection(readers []string) {
	if s.nfcReaderStatus == nil || s.nfcReaderSelect == nil {
		return // Config aún no construida (p. ej. durante arranque)
	}
	active := nfcGetCurrentReader()
	switch len(readers) {
	case 0:
		s.nfcReaderSelect.Hide()
		s.nfcReaderStatus.SetText("Sin lectores NFC detectados.")
	case 1:
		s.nfcReaderSelect.Hide()
		s.nfcReaderStatus.SetText("Lector activo: " + readers[0])
	default:
		s.nfcReaderSelect.Show()
		infos := nfcGetAvailableReaderInfos()
		selectedID := nfcResolveReaderID(infos, nfcGetSelectedReader())
		selectedLabel := readers[0]
		if r, ok := nfcFindReaderByID(infos, selectedID); ok {
			selectedLabel = r.Label
		}
		s.nfcSelectBusy = true
		s.nfcReaderSelect.SetOptions(readers)
		s.nfcReaderSelect.SetSelected(selectedLabel)
		s.nfcSelectBusy = false
		if active != "" {
			s.nfcReaderStatus.SetText("Lector activo: " + active)
		} else {
			s.nfcReaderStatus.SetText("Selecciona el lector a usar:")
		}
	}
}

// ── Device info section ───────────────────────────────────────────────────────

func (s *SettingsScreen) buildDeviceSection() fyne.CanvasObject {
	deviceID := configGetDeviceID()
	deviceName := configGetDeviceName()
	if deviceName == "" {
		deviceName = "(sin nombre)"
	}
	status := configGetStatus()

	statusMap := map[string][2]string{
		"authorized":     {"✅ Autorizado", "green"},
		"pending":        {"⏳ Pendiente", "orange"},
		"not_registered": {"❌ No registrado", "red"},
	}
	statusInfo := [2]string{"Desconocido", "gray"}
	if v, ok := statusMap[status]; ok {
		statusInfo = v
	}

	isHW := strings.HasPrefix(deviceID, "HW-")
	idDisplay := deviceID
	if isHW {
		idDisplay = deviceID[3:]
	}
	if len(idDisplay) > 27 {
		idDisplay = idDisplay[:27] + "..."
	}
	idLabel := "⚠️ UUID generado:"
	if isHW {
		idLabel = "🔒 Hardware UUID:"
	}

	s.nameEntry = widget.NewEntry()
	s.nameEntry.SetText(configGetDeviceName())

	saveNameBtn := widget.NewButton("💾  Guardar nombre", func() {
		n := strings.TrimSpace(s.nameEntry.Text)
		if n != "" {
			configSetDeviceName(n)
		}
	})
	saveNameBtn.Importance = widget.HighImportance

	form := container.NewVBox(
		container.NewGridWithColumns(2,
			widget.NewLabel("Nombre:"), widget.NewLabel(deviceName),
			widget.NewLabel(idLabel), widget.NewLabel(idDisplay),
			widget.NewLabel("Estado:"), widget.NewLabel(statusInfo[0]),
		),
		widget.NewLabel("Cambiar nombre:"),
		s.nameEntry,
		saveNameBtn,
	)

	return widget.NewCard("🖥  Dispositivo", "", form)
}

// ── Credentials section ───────────────────────────────────────────────────────

func (s *SettingsScreen) buildCredentialsSection() fyne.CanvasObject {
	note := widget.NewLabel(
		"Limpiar credenciales forzará un nuevo registro del dispositivo.",
	)
	note.Wrapping = fyne.TextWrapWord

	clearBtn := widget.NewButton("🗑  Limpiar credenciales y re-registrar", func() {
		confirm := dialog.NewConfirm(
			"¿Limpiar credenciales?",
			"Se eliminará el token permanente y tendrás que registrar el dispositivo de nuevo.",
			func(ok bool) {
				if ok {
					configClearCredentials()
					apiClearBearer()
					s.onLogout()
				}
			},
			s.win,
		)
		confirm.Show()
	})
	clearBtn.Importance = widget.DangerImportance

	return widget.NewCard("🔐  Credenciales", "", container.NewVBox(note, clearBtn))
}
