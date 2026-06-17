// mainwindow.go — Main window with sidebar navigation.
// Manages a single fyne.Window, swapping screen content on navigation.
package main

import (
	"bytes"
	"image/color"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/dialog"
	"fyne.io/fyne/v2/widget"
)

// screenID constants used for navigation.
const (
	screenHome     = "home"
	screenPago     = "pago"
	screenRecarga  = "recarga"
	screenAdmin    = "admin"
	screenSettings = "settings"
)

// navItem describes a sidebar navigation entry.
type navItem struct {
	label string
	id    string
}

var navItems = []navItem{
	{"🏠  Inicio", screenHome},
	{"💶  Cobrar", screenPago},
	{"💰  Recargar", screenRecarga},
	{"👤  Admin", screenAdmin},
	{"⚙️  Config", screenSettings},
}

// MainWindow manages the sidebar + swappable content area.
type MainWindow struct {
	win            fyne.Window
	roles          []string
	deviceName     string
	capituloNombre string
	capituloLogo   []byte
	pendingUpdate  *UpdateInfo
	onLogout       func()

	// Screens (created once, swapped by navigate)
	homeScreen     *HomeScreen
	pagoScreen     *PagoScreen
	recargaScreen  *RecargaScreen
	adminScreen    *AdminScreen
	settingsScreen *SettingsScreen

	// Navigation
	currentID   string
	content     *fyne.Container // Stack layout — holds exactly one screen
	navBtns     map[string]*widget.Button
	screenCache map[string]fyne.CanvasObject // built once, reused

	// NFC status label (bottom of sidebar)
	nfcStatusText *canvas.Text

	// Update banner (shown if pendingUpdate != nil)
	updateBanner fyne.CanvasObject
}

func newMainWindow(win fyne.Window, roles []string, deviceName string, capituloNombre string, capituloLogo []byte, pendingUpdate *UpdateInfo, onLogout func()) *MainWindow {
	mw := &MainWindow{
		win:            win,
		roles:          roles,
		deviceName:     deviceName,
		capituloNombre: capituloNombre,
		capituloLogo:   capituloLogo,
		pendingUpdate:  pendingUpdate,
		onLogout:       onLogout,
		navBtns:        make(map[string]*widget.Button),
		screenCache:    make(map[string]fyne.CanvasObject),
	}

	// Create all screens up front
	mw.homeScreen = newHomeScreen(win, roles, deviceName, mw.capituloNombre,
		func() { mw.navigate(screenPago) },
		func() { mw.navigate(screenRecarga) },
	)
	mw.pagoScreen = newPagoScreen(win,
		mw.homeScreen.GetCardInfo,
		func() { mw.navigate(screenHome) },
	)
	mw.recargaScreen = newRecargaScreen(win,
		mw.homeScreen.GetCardInfo,
		func() { mw.navigate(screenHome) },
	)
	mw.adminScreen = newAdminScreen(win, func(uid string) {
		mw.navigate(screenHome)
		mw.homeScreen.SimulateCard(uid)
	})
	mw.settingsScreen = newSettingsScreen(win, onLogout)

	return mw
}

func (mw *MainWindow) build() fyne.CanvasObject {
	// ── Sidebar ───────────────────────────────────────────────────────────────
	// Logo del capítulo + nombre
	var headerRow fyne.CanvasObject
	if len(mw.capituloLogo) > 0 {
		logoImg := canvas.NewImageFromReader(bytes.NewReader(mw.capituloLogo), "capitulo_logo")
		logoImg.SetMinSize(fyne.NewSize(36, 36))
		logoImg.FillMode = canvas.ImageFillContain
		capNameLbl := widget.NewLabelWithStyle(
			mw.capituloNombre, fyne.TextAlignLeading, fyne.TextStyle{Bold: true},
		)
		headerRow = container.NewHBox(logoImg, capNameLbl)
	} else {
		headerRow = widget.NewLabelWithStyle(
			"📍 "+mw.capituloNombre, fyne.TextAlignLeading, fyne.TextStyle{Bold: true},
		)
	}
	devLbl := widget.NewLabel(truncate(mw.deviceName, 18))

	navRows := []fyne.CanvasObject{}
	for _, item := range navItems {
		item := item // capture loop variable
		if !mw.hasAccessTo(item.id) {
			continue
		}
		btn := widget.NewButton(item.label, func() {
			mw.navigate(item.id)
		})
		btn.Importance = widget.LowImportance
		btn.Alignment = widget.ButtonAlignLeading
		mw.navBtns[item.id] = btn
		navRows = append(navRows, btn)
	}

	mw.nfcStatusText = canvas.NewText("Sin lector NFC", colorRed)
	mw.nfcStatusText.TextSize = 11

	topSidebar := container.NewVBox(
		append([]fyne.CanvasObject{
			container.NewPadded(headerRow),
			container.NewPadded(devLbl),
		}, navRows...)...,
	)

	sidebar := container.NewBorder(
		topSidebar,
		container.NewPadded(mw.nfcStatusText),
		nil, nil, nil,
	)

	// ── Content area ──────────────────────────────────────────────────────────
	mw.content = container.NewStack()

	// ── Update banner (if pending update) ─────────────────────────────────────
	var mainContent fyne.CanvasObject
	if mw.pendingUpdate != nil {
		mw.updateBanner = mw.buildUpdateBanner()
		mainContent = container.NewBorder(mw.updateBanner, nil, nil, nil, mw.content)
	} else {
		mainContent = mw.content
	}

	// ── Main layout (sidebar left, content right) ─────────────────────────────
	split := container.NewHSplit(sidebar, mainContent)
	split.Offset = 0.18

	// Navigate to home to kick things off
	mw.navigate(screenHome)

	return split
}

// buildUpdateBanner crea el banner de actualización disponible.
func (mw *MainWindow) buildUpdateBanner() fyne.CanvasObject {
	if mw.pendingUpdate == nil {
		return nil
	}

	iconLbl := widget.NewLabel("🔄")
	msgLbl := widget.NewLabel("Nueva versión " + mw.pendingUpdate.VersionName + " disponible")
	msgLbl.TextStyle = fyne.TextStyle{Bold: true}

	installBtn := widget.NewButton("Instalar", func() {
		mw.startOptionalUpdate()
	})
	installBtn.Importance = widget.HighImportance

	dismissBtn := widget.NewButton("Ahora no", func() {
		mw.dismissUpdateBanner()
	})
	dismissBtn.Importance = widget.LowImportance

	banner := container.NewHBox(
		iconLbl,
		msgLbl,
		container.NewHBox(installBtn, dismissBtn),
	)

	// Fondo azul claro
	bgColor := color.RGBA{R: 220, G: 235, B: 255, A: 255}
	bg := canvas.NewRectangle(bgColor)
	bg.SetMinSize(fyne.NewSize(0, 40))

	return container.NewStack(bg, container.NewPadded(banner))
}

func (mw *MainWindow) dismissUpdateBanner() {
	mw.pendingUpdate = nil
	if mw.updateBanner != nil {
		mw.updateBanner.Hide()
	}
}

func (mw *MainWindow) startOptionalUpdate() {
	bearer := apiGetBearer()
	if bearer == "" {
		return
	}

	// Mostrar diálogo de progreso
	progressBar := widget.NewProgressBar()
	progressText := widget.NewLabel("Preparando descarga...")
	progressText.Alignment = fyne.TextAlignCenter

	dlgContent := container.NewVBox(
		widget.NewLabel("Descargando actualización..."),
		progressBar,
		progressText,
	)

	dlg := dialog.NewCustomWithoutButtons("Actualizando", dlgContent, mw.win)
	dlg.Show()

	go func() {
		exePath, err := downloadUpdate(bearer, func(percent int, downloaded, total int64) {
			progressBar.SetValue(float64(percent) / 100.0)
			progressText.SetText(formatBytes(downloaded) + " / " + formatBytes(total))
		})

		if err != nil {
			dlg.Hide()
			errDlg := dialog.NewError(err, mw.win)
			errDlg.Show()
			return
		}

		progressText.SetText("Instalando...")
		if err := applyUpdate(exePath); err != nil {
			dlg.Hide()
			errDlg := dialog.NewError(err, mw.win)
			errDlg.Show()
		}
		// Si applyUpdate tiene éxito, la app se cierra
	}()
}

// navigate switches to the given screen and updates NFC callbacks.
// Screens are built once and cached; OnShow() is called each time.
func (mw *MainWindow) navigate(id string) {
	if !mw.hasAccessTo(id) {
		return
	}

	// Build screen once, then cache
	screen, ok := mw.screenCache[id]
	if !ok {
		screen = mw.buildScreen(id)
		if screen == nil {
			return
		}
		mw.screenCache[id] = screen
	}

	mw.content.Objects = []fyne.CanvasObject{screen}
	mw.content.Refresh()
	mw.currentID = id

	// Update nav button highlights
	for btnID, btn := range mw.navBtns {
		if btnID == id {
			btn.Importance = widget.HighImportance
		} else {
			btn.Importance = widget.LowImportance
		}
		btn.Refresh()
	}

	// Register NFC callbacks for home whenever we navigate there
	if id == screenHome {
		mw.registerHomeNFC()
	}

	// Call OnShow if the screen supports it
	type shower interface{ OnShow() }
	if s, ok := mw.screenByID(id).(shower); ok {
		s.OnShow()
	}
}

// buildScreen builds and returns the CanvasObject for a screen ID.
func (mw *MainWindow) buildScreen(id string) fyne.CanvasObject {
	switch id {
	case screenHome:
		return mw.homeScreen.build()
	case screenPago:
		return mw.pagoScreen.build()
	case screenRecarga:
		return mw.recargaScreen.build()
	case screenAdmin:
		return mw.adminScreen.build()
	case screenSettings:
		return mw.settingsScreen.build()
	}
	return nil
}

// screenByID returns the screen struct pointer for interface dispatch.
func (mw *MainWindow) screenByID(id string) interface{} {
	switch id {
	case screenHome:
		return mw.homeScreen
	case screenPago:
		return mw.pagoScreen
	case screenRecarga:
		return mw.recargaScreen
	case screenAdmin:
		return mw.adminScreen
	case screenSettings:
		return mw.settingsScreen
	}
	return nil
}

// registerHomeNFC sets the home screen's NFC callbacks (including sidebar status).
func (mw *MainWindow) registerHomeNFC() {
	nfcSetCallbacks(NFCCallbacks{
		OnCardDetected: mw.homeScreen.OnCardDetected,
		OnCardRemoved:  mw.homeScreen.OnCardRemoved,
		OnReaderChange: func(reader string) {
			mw.homeScreen.OnReaderChange(reader)
			mw.updateNFCStatus(reader)
		},
	})
	// Sync current reader status immediately
	mw.updateNFCStatus(nfcGetCurrentReader())
}

func (mw *MainWindow) updateNFCStatus(reader string) {
	if reader != "" {
		mw.nfcStatusText.Text = "NFC: " + truncate(reader, 22)
		mw.nfcStatusText.Color = colorGreen
	} else {
		mw.nfcStatusText.Text = "Sin lector NFC"
		mw.nfcStatusText.Color = colorRed
	}
	mw.nfcStatusText.Refresh()
}

// hasAccessTo returns true if the user's roles permit accessing the given screen.
func (mw *MainWindow) hasAccessTo(id string) bool {
	switch id {
	case screenPago:
		return mw.hasRole("TERMINAL")
	case screenRecarga:
		return mw.hasRole("CAJA")
	case screenAdmin:
		return mw.hasRole("ADMIN")
	}
	return true
}

func (mw *MainWindow) hasRole(role string) bool {
	for _, r := range mw.roles {
		if r == role {
			return true
		}
	}
	return false
}

func truncate(s string, n int) string {
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	return string(runes[:n])
}
