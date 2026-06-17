// screen_registration.go — Device registration / authorization screen.
package main

import (
	"time"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/widget"
)

type RegistrationScreen struct {
	win          fyne.Window
	onAuthorized func()
	statusLabel  *widget.Label
	nameEntry    *widget.Entry
	capSelect    *widget.Select
	registerBtn  *widget.Button
	authorizeBtn *widget.Button

	// Capítulos state
	capitulos       []Capitulo
	capitulosLoaded bool
}

func newRegistrationScreen(win fyne.Window, onAuthorized func()) *RegistrationScreen {
	return &RegistrationScreen{win: win, onAuthorized: onAuthorized}
}

func (s *RegistrationScreen) build() fyne.CanvasObject {
	title := widget.NewLabelWithStyle(
		"CHPay Desktop", fyne.TextAlignCenter, fyne.TextStyle{Bold: true},
	)

	subtitle := widget.NewLabel("Terminal de Pagos NFC")
	subtitle.Alignment = fyne.TextAlignCenter

	deviceID := configGetDeviceID()
	idDisplay := deviceID
	if len(idDisplay) > 27 {
		idDisplay = idDisplay[:27] + "..."
	}
	idLabel := widget.NewLabel("UUID: " + idDisplay)
	idLabel.Alignment = fyne.TextAlignCenter

	regTitle := widget.NewLabelWithStyle(
		"Registro del Dispositivo", fyne.TextAlignCenter, fyne.TextStyle{Bold: true},
	)

	s.nameEntry = widget.NewEntry()
	s.nameEntry.SetPlaceHolder("Ej: Terminal Cafetería")
	saved := configGetDeviceName()
	if saved != "" {
		s.nameEntry.SetText(saved)
	}

	// Capítulo selector
	s.capSelect = widget.NewSelect([]string{}, nil)
	s.capSelect.PlaceHolder = "Cargando capítulos..."
	s.capSelect.Disable()

	s.statusLabel = widget.NewLabel("")
	s.statusLabel.Alignment = fyne.TextAlignCenter
	s.statusLabel.Wrapping = fyne.TextWrapWord

	s.registerBtn = widget.NewButton("📝  Solicitar Registro", s.doRequestRegistration)
	s.registerBtn.Importance = widget.HighImportance
	s.registerBtn.Disable() // Disabled until capítulos load

	s.authorizeBtn = widget.NewButton("✅  Ya fui aprobado — Autorizar", s.doAuthorize)
	s.authorizeBtn.Importance = widget.SuccessImportance

	// If already pending, show a reminder
	if configGetStatus() == "pending" {
		s.statusLabel.SetText(
			"⏳ Registro solicitado. Espera la aprobación del administrador,\n" +
				"luego pulsa 'Autorizar'.",
		)
	}

	form := container.NewVBox(
		regTitle,
		idLabel,
		widget.NewLabel("Nombre del dispositivo:"),
		s.nameEntry,
		widget.NewLabel("Capítulo (opcional):"),
		s.capSelect,
		s.statusLabel,
		s.registerBtn,
		s.authorizeBtn,
	)
	card := widget.NewCard("", "", container.NewPadded(form))

	header := container.NewVBox(title, subtitle)

	// Load capítulos asynchronously
	go s.loadCapitulos()

	return container.NewCenter(
		container.NewVBox(header, card),
	)
}

func (s *RegistrationScreen) loadCapitulos() {
	caps, err := apiGetCapitulos()
	if err != nil {
		s.statusLabel.SetText("❌ Error al cargar capítulos: " + err.Error() + "\nPulsa 'Reintentar'.")
		s.registerBtn.SetText("🔄  Reintentar cargar capítulos")
		s.registerBtn.Enable()
		s.registerBtn.OnTapped = func() {
			s.statusLabel.SetText("")
			s.registerBtn.Disable()
			s.registerBtn.SetText("📝  Solicitar Registro")
			go s.loadCapitulos()
		}
		return
	}

	s.capitulos = caps
	s.capitulosLoaded = true

	options := []string{"Sin asignar"}
	for _, c := range caps {
		options = append(options, c.Nombre)
	}
	s.capSelect.Options = options
	s.capSelect.SetSelectedIndex(0)
	s.capSelect.Enable()
	s.capSelect.PlaceHolder = "Selecciona capítulo (opcional)"

	// Restore register button to normal
	s.registerBtn.OnTapped = s.doRequestRegistration
	s.registerBtn.Enable()
	s.registerBtn.SetText("📝  Solicitar Registro")
}

// selectedCapituloID returns the selected chapter ID, or 0 if "Sin asignar".
func (s *RegistrationScreen) selectedCapituloID() int {
	if !s.capitulosLoaded || s.capSelect.SelectedIndex() <= 0 {
		return 0
	}
	idx := s.capSelect.SelectedIndex() - 1 // offset by "Sin asignar"
	if idx >= 0 && idx < len(s.capitulos) {
		return s.capitulos[idx].ID
	}
	return 0
}

func (s *RegistrationScreen) doRequestRegistration() {
	if !s.capitulosLoaded {
		s.statusLabel.SetText("❌ Espera a que se carguen los capítulos.")
		return
	}
	name := s.nameEntry.Text
	if name == "" {
		s.statusLabel.SetText("❌ Escribe un nombre para el dispositivo.")
		return
	}
	s.registerBtn.Disable()
	s.registerBtn.SetText("Enviando...")
	s.statusLabel.SetText("")

	capID := s.selectedCapituloID()

	go func() {
		err := authRequestRegistration(name, capID)
		s.registerBtn.Enable()
		s.registerBtn.SetText("📝  Solicitar Registro")
		if err != nil {
			s.statusLabel.SetText("❌ " + err.Error())
		} else {
			s.statusLabel.SetText(
				"✅ Solicitud enviada. El administrador debe aprobar el dispositivo.\n" +
					"Cuando sea aprobado, pulsa 'Autorizar'.",
			)
		}
	}()
}

func (s *RegistrationScreen) doAuthorize() {
	name := s.nameEntry.Text
	s.authorizeBtn.Disable()
	s.authorizeBtn.SetText("Autorizando...")
	s.statusLabel.SetText("")

	go func() {
		err := authAuthorize(name)
		s.authorizeBtn.Enable()
		s.authorizeBtn.SetText("✅  Ya fui aprobado — Autorizar")
		if err != nil {
			s.statusLabel.SetText("❌ " + err.Error())
		} else {
			s.statusLabel.SetText("✅ Dispositivo autorizado correctamente.")
			// Small delay so the user sees the success message
			go func() {
				time.Sleep(800 * time.Millisecond)
				s.onAuthorized()
			}()
		}
	}()
}
