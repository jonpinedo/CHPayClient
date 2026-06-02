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
	registerBtn  *widget.Button
	authorizeBtn *widget.Button
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

	s.statusLabel = widget.NewLabel("")
	s.statusLabel.Alignment = fyne.TextAlignCenter
	s.statusLabel.Wrapping = fyne.TextWrapWord

	s.registerBtn = widget.NewButton("📝  Solicitar Registro", s.doRequestRegistration)
	s.registerBtn.Importance = widget.HighImportance

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
		s.statusLabel,
		s.registerBtn,
		s.authorizeBtn,
	)
	card := widget.NewCard("", "", container.NewPadded(form))

	header := container.NewVBox(title, subtitle)
	return container.NewCenter(
		container.NewVBox(header, card),
	)
}

func (s *RegistrationScreen) doRequestRegistration() {
	name := s.nameEntry.Text
	if name == "" {
		s.statusLabel.SetText("❌ Escribe un nombre para el dispositivo.")
		return
	}
	s.registerBtn.Disable()
	s.registerBtn.SetText("Enviando...")
	s.statusLabel.SetText("")

	go func() {
		err := authRequestRegistration(name)
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


