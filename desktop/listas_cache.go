// listas_cache.go — In-memory cache for price lists loaded at session start.
package main

import (
	"fmt"
	"sync"
)

var (
	listasCache      []ListaPrecios        // available lists for the chapter
	listasDetalle    map[int]*ListaDetalle // listaID → full detail with items
	listasIconos     map[int][]byte        // itemID → icon bytes
	listasCacheMu    sync.RWMutex
	listasCacheCapID int
)

// listasLoadCache loads all price lists and their items for the given chapter.
// Called once after successful auth in showMainApp.
func listasLoadCache(capituloID int) {
	listasCacheMu.Lock()
	defer listasCacheMu.Unlock()

	listasCacheCapID = capituloID
	listasDetalle = make(map[int]*ListaDetalle)
	listasIconos = make(map[int][]byte)

	listas, err := apiGetListas(capituloID)
	if err != nil {
		fmt.Printf("⚠️ Error cargando listas: %v\n", err)
		listasCache = nil
		return
	}
	listasCache = listas

	// Pre-load detail and icons for each list
	for _, l := range listas {
		detalle, err := apiGetListaDetalle(capituloID, l.ID)
		if err != nil {
			continue
		}
		listasDetalle[l.ID] = detalle

		// Load icons in background
		for _, item := range detalle.Items {
			if item.TieneIcono {
				ico, _ := apiGetItemIcono(capituloID, l.ID, item.ID)
				if len(ico) > 0 {
					listasIconos[item.ID] = ico
				}
			}
		}
	}
}

// listasGetAll returns cached list headers.
func listasGetAll() []ListaPrecios {
	listasCacheMu.RLock()
	defer listasCacheMu.RUnlock()
	return listasCache
}

// listasGetDetalle returns cached detail for a list.
func listasGetDetalle(listaID int) *ListaDetalle {
	listasCacheMu.RLock()
	defer listasCacheMu.RUnlock()
	return listasDetalle[listaID]
}

// listasGetIcono returns cached icon bytes for an item.
func listasGetIcono(itemID int) []byte {
	listasCacheMu.RLock()
	defer listasCacheMu.RUnlock()
	return listasIconos[itemID]
}
