package main

import (
	_ "embed"

	"fyne.io/fyne/v2"
)

//go:embed icon.png
var iconPngBytes []byte

// AppIcon es el icono estático de la aplicación (CHBlack.png embebido).
var AppIcon = fyne.NewStaticResource("icon.png", iconPngBytes)
