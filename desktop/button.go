// button.go — Botones con anti-rebote de clic (ratón/touch que dispara 2 eventos).
package main

import (
	"sync"
	"time"

	"fyne.io/fyne/v2/widget"
)

// Tiempo suficiente para absorber un doble clic accidental / rebote de ratón
// sin notarse en el uso normal del TPV.
const buttonDebounce = 100 * time.Millisecond

// debounceTap envuelve un handler para ignorar pulsaciones repetidas
// en el mismo botón dentro de buttonDebounce.
func debounceTap(fn func()) func() {
	if fn == nil {
		return nil
	}
	var (
		mu   sync.Mutex
		last time.Time
	)
	return func() {
		mu.Lock()
		now := time.Now()
		if !last.IsZero() && now.Sub(last) < buttonDebounce {
			mu.Unlock()
			return
		}
		last = now
		mu.Unlock()
		fn()
	}
}

// newButton es el constructor de botones de la app (sustituye widget.NewButton).
func newButton(label string, tapped func()) *widget.Button {
	return widget.NewButton(label, debounceTap(tapped))
}
