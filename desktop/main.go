// main.go — Entry point de CHPay Desktop v2 (Go/Fyne).
//
// Flujo de arranque:
//  1. Cargar configuración
//  2. Si no está autorizado → pantalla de registro
//  3. Autorizado → crear sesión bearer → ventana principal
package main

import (
	"image/color"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/app"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

// Version info — inyectado via ldflags en el build.
// go build -ldflags "-X main.AppVersion=1.0.1 -X main.AppVersionCode=2" ...
var (
	AppVersion     = "1.0.0"
	AppVersionCode = "1"
)

// Colores globales reutilizados en todas las pantallas.
var (
	colorGreen  = color.RGBA{R: 26, G: 122, B: 26, A: 255}
	colorRed    = color.RGBA{R: 192, G: 57, B: 43, A: 255}
	colorBlue   = color.RGBA{R: 21, G: 101, B: 192, A: 255}
	colorGray   = color.RGBA{R: 128, G: 128, B: 128, A: 255}
	colorRowBg  = color.RGBA{R: 245, G: 245, B: 245, A: 200}
	colorOrange = color.RGBA{R: 211, G: 84, B: 0, A: 255}
)

var fyneApp fyne.App

// AppController gestiona el flujo de pantallas sobre una única ventana.
type AppController struct {
	win           fyne.Window
	pendingUpdate *UpdateInfo // update disponible (si no es mandatory)
}

func main() {
	// ── Modo upgrade: si este exe fue descargado para reemplazar el anterior ──
	if handleUpgradeMode() {
		return
	}

	configLoad()

	fyneApp = app.New()
	fyneApp.SetIcon(AppIcon)
	win := fyneApp.NewWindow("CHPay Desktop")
	win.SetIcon(AppIcon)
	win.Resize(fyne.NewSize(520, 460))

	ctrl := &AppController{win: win}
	ctrl.runApp()

	win.ShowAndRun()
}

func (c *AppController) runApp() {
	if !configIsAuthorized() {
		if !authTryRecover() {
			c.showRegistration()
			return
		}
	}
	c.showMainApp()
}

func (c *AppController) showRegistration() {
	c.win.SetTitle("CHPay Desktop — Registro")
	c.win.Resize(fyne.NewSize(520, 580))
	c.win.SetFixedSize(true)

	reg := newRegistrationScreen(c.win, func() {
		c.win.SetFixedSize(false)
		c.showMainApp()
	})
	c.win.SetContent(reg.build())
}

func (c *AppController) showMainApp() {
	bearer, err := authCreateSession()
	if err != nil {
		ae, ok := err.(*AuthError)
		if ok && ae.IsAuthError() {
			authLogout()
			c.showRegistration()
			return
		}
		c.showConnectionError(err.Error(), c.showMainApp)
		return
	}

	// ─── Check de actualización (no bloqueante) ───────────────────────────────
	if update := checkForUpdate(); update != nil {
		if update.Mandatory {
			c.showMandatoryUpdate(update, bearer)
			return
		}
		// Guardar para mostrar banner en home (no implementado aún, se ignora)
		c.pendingUpdate = update
	}

	info := apiGetDeviceInfo()
	roles := info.Roles
	deviceName := info.Nombre
	if deviceName == "" {
		deviceName = configGetDeviceName()
		if deviceName == "" {
			deviceName = "CHPayDesktop"
		}
	}

	// ─── Verificar capítulo asignado (bloquear si no tiene) ───────────────────
	if info.CapituloID == 0 {
		c.showBlockedNoCapitulo()
		return
	}

	// Descargar logo del capítulo (no bloqueante si falla)
	capituloLogo, _ := apiGetCapituloLogo(info.CapituloID)

	// Cargar listas de precios en cache
	listasLoadCache(info.CapituloID)

	// Usar logo como icono de ventana/barra de tareas
	if len(capituloLogo) > 0 {
		iconRes := fyne.NewStaticResource("capitulo_logo", capituloLogo)
		c.win.SetIcon(iconRes)
	}

	c.win.SetTitle("CHPay Desktop — " + info.CapituloNombre + " v" + AppVersion)
	c.win.Resize(fyne.NewSize(980, 600))
	c.win.SetFixedSize(false)

	mw := newMainWindow(c.win, roles, deviceName, info.CapituloNombre, capituloLogo, c.pendingUpdate, func() {
		nfcStop()
		authLogout()
		c.showRegistration()
	})
	c.win.SetContent(mw.build())
	nfcStart()
}

func (c *AppController) showConnectionError(msg string, retryFn func()) {
	title := widget.NewLabelWithStyle(
		"⚠️  Error de Conexión",
		fyne.TextAlignCenter,
		fyne.TextStyle{Bold: true},
	)
	msgLabel := widget.NewLabel(msg)
	msgLabel.Wrapping = fyne.TextWrapWord
	hint := widget.NewLabel("Verifica que Ziti Desktop Edge esté activo.")
	hint.Wrapping = fyne.TextWrapWord

	retryBtn := widget.NewButton("🔄  Reintentar", func() {
		retryFn()
	})
	retryBtn.Importance = widget.HighImportance

	content := container.NewCenter(
		container.NewVBox(title, msgLabel, hint, retryBtn),
	)
	c.win.SetContent(content)
}

// showBlockedNoCapitulo displays a blocking screen when the device has no chapter assigned.
func (c *AppController) showBlockedNoCapitulo() {
	c.win.SetTitle("CHPay Desktop — Sin capítulo")
	c.win.Resize(fyne.NewSize(500, 350))
	c.win.SetFixedSize(true)

	title := widget.NewLabelWithStyle(
		"⚠️  Dispositivo sin capítulo asignado",
		fyne.TextAlignCenter,
		fyne.TextStyle{Bold: true},
	)
	msgLabel := widget.NewLabel(
		"Contacta al administrador para que asigne este dispositivo a un capítulo.",
	)
	msgLabel.Wrapping = fyne.TextWrapWord
	msgLabel.Alignment = fyne.TextAlignCenter

	retryBtn := widget.NewButton("🔄  Reintentar", func() {
		c.win.SetFixedSize(false)
		c.showMainApp()
	})
	retryBtn.Importance = widget.HighImportance

	content := container.NewCenter(
		container.NewVBox(title, widget.NewLabel(""), msgLabel, widget.NewLabel(""), retryBtn),
	)
	c.win.SetContent(content)
}

// showMandatoryUpdate muestra una pantalla bloqueante que obliga a actualizar.
func (c *AppController) showMandatoryUpdate(update *UpdateInfo, bearer string) {
	c.win.SetTitle("CHPay Desktop — Actualización requerida")
	c.win.Resize(fyne.NewSize(500, 400))
	c.win.SetFixedSize(true)

	title := widget.NewLabelWithStyle(
		"🔄  Actualización Requerida",
		fyne.TextAlignCenter,
		fyne.TextStyle{Bold: true},
	)

	versionLbl := widget.NewLabel("Nueva versión: " + update.VersionName)
	versionLbl.Alignment = fyne.TextAlignCenter

	changelogLbl := widget.NewLabel(update.Changelog)
	changelogLbl.Wrapping = fyne.TextWrapWord

	statusLbl := widget.NewLabel("")
	statusLbl.Alignment = fyne.TextAlignCenter

	progressBar := widget.NewProgressBar()
	progressBar.Hide()

	progressText := widget.NewLabel("")
	progressText.Alignment = fyne.TextAlignCenter
	progressText.Hide()

	updateBtn := widget.NewButton("⬇️  Descargar e instalar", nil)
	updateBtn.Importance = widget.HighImportance

	updateBtn.OnTapped = func() {
		updateBtn.Disable()
		updateBtn.SetText("Descargando...")
		progressBar.Show()
		progressText.Show()

		go func() {
			exePath, err := downloadUpdate(bearer, func(percent int, downloaded, total int64) {
				progressBar.SetValue(float64(percent) / 100.0)
				progressText.SetText(formatBytes(downloaded) + " / " + formatBytes(total))
			})

			if err != nil {
				statusLbl.SetText("❌ Error: " + err.Error())
				updateBtn.Enable()
				updateBtn.SetText("⬇️  Reintentar descarga")
				progressBar.Hide()
				progressText.Hide()
				return
			}

			statusLbl.SetText("✅ Descarga completada. Instalando...")
			progressBar.SetValue(1.0)

			if err := applyUpdate(exePath); err != nil {
				statusLbl.SetText("❌ Error al instalar: " + err.Error())
				updateBtn.Enable()
				updateBtn.SetText("⬇️  Reintentar")
			}
			// Si applyUpdate tiene éxito, la app se cierra
		}()
	}

	content := container.NewCenter(
		container.NewVBox(
			title,
			widget.NewLabel(""),
			versionLbl,
			widget.NewLabel(""),
			changelogLbl,
			widget.NewLabel(""),
			statusLbl,
			progressBar,
			progressText,
			widget.NewLabel(""),
			updateBtn,
		),
	)

	c.win.SetContent(content)
}
