// widget_historial.go — Reusable transaction history widget.
package main

import (
	"fmt"
	"image/color"
	"strconv"
	"strings"

	"fyne.io/fyne/v2"
	"fyne.io/fyne/v2/canvas"
	"fyne.io/fyne/v2/container"
	"fyne.io/fyne/v2/theme"
	"fyne.io/fyne/v2/widget"
)

// HistorialWidget shows a scrollable list of recent transactions.
type HistorialWidget struct {
	vbox       *fyne.Container
	scroll     *container.Scroll
	root       fyne.CanvasObject
	filterTipo string // "" = todas; "COBRO" o "RECARGA" para filtrar
}

func newHistorialWidget(title string, filterTipo string) *HistorialWidget {
	vbox := container.NewVBox()
	scroll := container.NewScroll(vbox)

	titleLabel := widget.NewLabelWithStyle(
		title, fyne.TextAlignLeading, fyne.TextStyle{Bold: true},
	)

	root := container.NewBorder(
		container.NewPadded(titleLabel),
		nil, nil, nil,
		scroll,
	)

	h := &HistorialWidget{vbox: vbox, scroll: scroll, root: root, filterTipo: filterTipo}
	h.showEmpty("Sin datos")
	return h
}

// CanvasObject returns the root widget for embedding in layouts.
func (h *HistorialWidget) CanvasObject() fyne.CanvasObject { return h.root }

// Load fetches and displays transaction history for the given card UID.
// It runs the API call in a goroutine so callers are never blocked.
func (h *HistorialWidget) Load(uid string) {
	h.showEmpty("Cargando...")
	go func() {
		limite := 15
		if h.filterTipo != "" {
			limite = 50 // pedir más para poder filtrar por tipo sin quedarnos cortos
		}
		result, err := apiGetHistorial(uid, limite)
		if err != nil {
			h.showEmpty("Error al cargar")
			return
		}
		objects := make([]fyne.CanvasObject, 0, 15)
		for _, t := range result.Transacciones {
			if h.filterTipo != "" && t.Tipo != h.filterTipo {
				continue
			}
			objects = append(objects, buildHistorialRow(t))
			if len(objects) >= 15 {
				break
			}
		}
		if len(objects) == 0 {
			switch h.filterTipo {
			case "COBRO":
				h.showEmpty("Sin cobros")
			case "RECARGA":
				h.showEmpty("Sin recargas")
			default:
				h.showEmpty("Sin operaciones")
			}
			return
		}
		h.vbox.Objects = objects
		h.vbox.Refresh()
	}()
}

// Clear resets the historial to its empty state.
func (h *HistorialWidget) Clear() {
	h.showEmpty("Sin datos")
}

func (h *HistorialWidget) showEmpty(text string) {
	lbl := widget.NewLabel(text)
	lbl.Alignment = fyne.TextAlignCenter
	h.vbox.Objects = []fyne.CanvasObject{lbl}
	h.vbox.Refresh()
}

func buildHistorialRow(t Transaccion) fyne.CanvasObject {
	monto, _ := strconv.ParseFloat(t.Monto, 64)
	saldo, _ := strconv.ParseFloat(t.SaldoPosterior, 64)

	isRecarga := t.Tipo == "RECARGA"
	var rowColor = colorRed
	icon := "(-)"
	if isRecarga {
		rowColor = colorGreen
		icon = "(+)"
	}

	tipoText := canvas.NewText(fmt.Sprintf("%s %s", icon, t.Tipo), rowColor)
	tipoText.TextStyle = fyne.TextStyle{Bold: true}
	tipoText.TextSize = 11

	montoText := canvas.NewText(fmt.Sprintf("%+.2f €", monto), rowColor)
	montoText.TextStyle = fyne.TextStyle{Bold: true}
	montoText.TextSize = 13

	ts := t.Timestamp
	if len(ts) >= 16 {
		ts = strings.Replace(ts[:16], "T", " ", 1)
	}
	infoText := canvas.NewText(
		fmt.Sprintf("Saldo: %.2f €  ·  %s", saldo, ts),
		colorGray,
	)
	infoText.TextSize = 10

	topRow := container.NewBorder(nil, nil, tipoText, montoText, nil)
	rows := []fyne.CanvasObject{topRow, infoText}

	if t.Tipo == "COBRO" && strings.TrimSpace(t.Operaciones) != "" {
		opsLbl := widget.NewLabel(t.Operaciones)
		opsLbl.Wrapping = fyne.TextWrapWord
		opsLbl.TextStyle = fyne.TextStyle{Italic: true}
		rows = append(rows, opsLbl)
	}

	inner := container.NewPadded(container.NewVBox(rows...))

	bg := canvas.NewRectangle(historialRowBg())
	return container.NewStack(bg, inner)
}

// historialRowBg devuelve el fondo de fila adaptado al tema activo, para que el
// texto (que sigue el color del tema) contraste tanto en modo claro como oscuro.
func historialRowBg() color.Color {
	if fyneApp != nil && fyneApp.Settings().ThemeVariant() == theme.VariantDark {
		// Sutil aclarado sobre el fondo oscuro del tema → texto claro legible.
		return color.NRGBA{R: 255, G: 255, B: 255, A: 28}
	}
	return colorRowBg
}
