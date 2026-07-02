// nfc.go — NFC polling facade: PC/SC + HID backends, shared callbacks.
//
// Runs a background goroutine that polls every 300 ms.
// UID format: uppercase hex without separators, e.g. "ABCDEF12".
package main

import (
	"sync"
	"time"

	"github.com/ebfe/scard"
)

// NFCCallbacks holds the set of callbacks active for the current screen.
type NFCCallbacks struct {
	OnCardDetected func(uid string) // called once per new card
	OnCardRemoved  func()
	OnReaderChange func(reader string) // display label; empty = no reader
}

var (
	nfcCbs   NFCCallbacks
	nfcCbsMu sync.Mutex

	nfcRunning             bool
	nfcStopChan            chan struct{}
	nfcCurrentReader       string // display label of active reader
	nfcLastUID             string
	nfcSelectedReader      string // persisted reader ID (or legacy name)
	nfcAvailableReaderInfos []nfcReaderInfo
	nfcReadersListCb       func([]string)
	nfcReadersListCbMu     sync.Mutex
	nfcMu                  sync.Mutex
)

func nfcSetCallbacks(cb NFCCallbacks) {
	nfcCbsMu.Lock()
	nfcCbs = cb
	nfcCbsMu.Unlock()
}

func nfcGetCallbacks() NFCCallbacks {
	nfcCbsMu.Lock()
	defer nfcCbsMu.Unlock()
	return nfcCbs
}

func nfcSetReadersListCallback(cb func([]string)) {
	nfcReadersListCbMu.Lock()
	nfcReadersListCb = cb
	nfcReadersListCbMu.Unlock()
}

func nfcNotifyReadersList(readers []string) {
	nfcReadersListCbMu.Lock()
	cb := nfcReadersListCb
	nfcReadersListCbMu.Unlock()
	if cb != nil {
		cb(readers)
	}
}

func nfcGetCurrentReader() string {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	return nfcCurrentReader
}

func nfcGetSelectedReader() string {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	return nfcSelectedReader
}

// nfcGetAvailableReaders returns display labels for the settings dropdown.
func nfcGetAvailableReaders() []string {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	return nfcReaderLabels(nfcAvailableReaderInfos)
}

func nfcGetAvailableReaderInfos() []nfcReaderInfo {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	out := make([]nfcReaderInfo, len(nfcAvailableReaderInfos))
	copy(out, nfcAvailableReaderInfos)
	return out
}

// nfcSetSelectedReader persists the reader choice (accepts label or ID).
func nfcSetSelectedReader(labelOrID string) {
	nfcMu.Lock()
	readers := append([]nfcReaderInfo(nil), nfcAvailableReaderInfos...)
	nfcMu.Unlock()

	id := labelOrID
	if r, ok := nfcFindReaderByLabel(readers, labelOrID); ok {
		id = r.ID
	} else {
		id = nfcResolveReaderID(readers, labelOrID)
	}

	nfcMu.Lock()
	if nfcSelectedReader == id {
		nfcMu.Unlock()
		return
	}
	nfcSelectedReader = id
	nfcMu.Unlock()
	configSetNFCReader(id)
}

func nfcStart() {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	if nfcRunning {
		return
	}
	nfcSelectedReader = configGetNFCReader()
	nfcRunning = true
	nfcStopChan = make(chan struct{})
	go nfcPollingLoop(nfcStopChan)
}

func nfcStop() {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	if !nfcRunning {
		return
	}
	nfcRunning = false
	close(nfcStopChan)
}

func nfcPollingLoop(stop <-chan struct{}) {
	var (
		cardPresent  bool
		missingCount int
		lastReaderID string
		hidSession   *nfcHIDSession
		pcscCtx      *scard.Context
	)

	defer func() {
		if hidSession != nil {
			hidSession.Close()
		}
		if pcscCtx != nil {
			pcscCtx.Release() //nolint:errcheck
		}
	}()

	closeBackend := func() {
		if hidSession != nil {
			hidSession.Close()
			hidSession = nil
		}
		if pcscCtx != nil {
			pcscCtx.Release() //nolint:errcheck
			pcscCtx = nil
		}
	}

	for {
		select {
		case <-stop:
			return
		default:
		}

		readers := nfcEnumerateAllReaders()

		nfcMu.Lock()
		listChanged := !nfcReadersInfoEqual(nfcAvailableReaderInfos, readers)
		if listChanged {
			nfcAvailableReaderInfos = append([]nfcReaderInfo(nil), readers...)
		}
		nfcMu.Unlock()
		if listChanged {
			nfcNotifyReadersListInfo(readers)
			nfcMigrateSelectedReaderID(readers)
		}

		reader := nfcPickReaderInfo(readers)

		if reader.ID != lastReaderID {
			closeBackend()
			lastReaderID = reader.ID
			missingCount = 0

			label := reader.Label
			nfcMu.Lock()
			nfcCurrentReader = label
			nfcMu.Unlock()

			cb := nfcGetCallbacks()
			if cb.OnReaderChange != nil {
				cb.OnReaderChange(label)
			}
			if reader.ID == "" && cardPresent {
				cardPresent = false
				nfcMu.Lock()
				nfcLastUID = ""
				nfcMu.Unlock()
				if cb.OnCardRemoved != nil {
					cb.OnCardRemoved()
				}
			}
		}

		if reader.ID == "" {
			time.Sleep(1 * time.Second)
			continue
		}

		var uid string
		switch reader.Kind {
		case nfcBackendPCSC:
			if pcscCtx == nil {
				ctx, err := scard.EstablishContext()
				if err != nil {
					time.Sleep(2 * time.Second)
					continue
				}
				pcscCtx = ctx
			}
			uid = nfcPCSCReadUID(pcscCtx, reader.PCSCName)

		case nfcBackendHID:
			if hidSession == nil {
				sess, err := nfcHIDOpen(reader.HIDPath)
				if err != nil {
					time.Sleep(1 * time.Second)
					continue
				}
				hidSession = sess
			}
			uid = hidSession.ReadUID()
		}

		cardPresent, missingCount = nfcUpdateCardState(
			reader.Kind, cardPresent, missingCount, uid,
		)

		time.Sleep(300 * time.Millisecond)
	}
}

func nfcUpdateCardState(
	kind nfcBackendKind,
	cardPresent bool,
	missingCount int,
	uid string,
) (bool, int) {
	if uid != "" {
		missingCount = 0
		nfcMu.Lock()
		prevUID := nfcLastUID
		nfcMu.Unlock()

		if !cardPresent || uid != prevUID {
			cardPresent = true
			nfcMu.Lock()
			nfcLastUID = uid
			nfcMu.Unlock()
			cb := nfcGetCallbacks()
			if cb.OnCardDetected != nil {
				cb.OnCardDetected(uid)
			}
		}
		return cardPresent, missingCount
	}

	// No card this poll.
	if !cardPresent {
		return false, 0
	}

	if kind == nfcBackendHID {
		missingCount++
		if missingCount < nfcHIDMissingThreshold {
			return cardPresent, missingCount
		}
	}

	cardPresent = false
	missingCount = 0
	nfcMu.Lock()
	nfcLastUID = ""
	nfcMu.Unlock()
	cb := nfcGetCallbacks()
	if cb.OnCardRemoved != nil {
		cb.OnCardRemoved()
	}
	return cardPresent, missingCount
}

// nfcMigrateSelectedReaderID upgrades legacy config values (plain PC/SC names) to stable IDs.
func nfcMigrateSelectedReaderID(readers []nfcReaderInfo) {
	stored := nfcGetSelectedReader()
	resolved := nfcResolveReaderID(readers, stored)
	if resolved == "" || resolved == stored {
		return
	}
	nfcMu.Lock()
	nfcSelectedReader = resolved
	nfcMu.Unlock()
	configSetNFCReader(resolved)
}
