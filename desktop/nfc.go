// nfc.go — NFC polling via PC/SC (winscard.dll) using github.com/ebfe/scard.
//
// Runs a background goroutine that polls every 300 ms.
// UID format: uppercase hex without separators, e.g. "ABCDEF12".
package main

import (
	"encoding/hex"
	"strings"
	"sync"
	"time"

	"github.com/ebfe/scard"
)

// GET UID APDU (ISO 14443 / MIFARE)
var getUIDAPDU = []byte{0xFF, 0xCA, 0x00, 0x00, 0x00}

// NFCCallbacks holds the set of callbacks active for the current screen.
type NFCCallbacks struct {
	OnCardDetected func(uid string) // called once per new card
	OnCardRemoved  func()
	OnReaderChange func(reader string) // empty string = no reader
}

var (
	nfcCbs   NFCCallbacks
	nfcCbsMu sync.Mutex

	nfcRunning       bool
	nfcStopChan      chan struct{}
	nfcCurrentReader string
	nfcLastUID       string
	nfcMu            sync.Mutex
)

// nfcSetCallbacks replaces the active NFC callback set (goroutine-safe).
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

// nfcGetCurrentReader returns the name of the currently connected reader.
func nfcGetCurrentReader() string {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	return nfcCurrentReader
}

// nfcStart launches the polling goroutine (idempotent).
func nfcStart() {
	nfcMu.Lock()
	defer nfcMu.Unlock()
	if nfcRunning {
		return
	}
	nfcRunning = true
	nfcStopChan = make(chan struct{})
	go nfcPollingLoop(nfcStopChan)
}

// nfcStop signals the polling goroutine to exit.
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
	var cardPresent bool
	var lastReaderName string

	for {
		select {
		case <-stop:
			return
		default:
		}

		ctx, err := scard.EstablishContext()
		if err != nil {
			// PC/SC not available — wait and retry
			time.Sleep(2 * time.Second)
			continue
		}

		// Inner loop: keep context alive until it errors
		cardPresent, lastReaderName = nfcInnerLoop(ctx, stop, cardPresent, lastReaderName)
		ctx.Release() //nolint:errcheck

		// If the stop signal was sent, exit
		select {
		case <-stop:
			return
		default:
		}

		time.Sleep(1 * time.Second) // brief pause before re-establishing context
	}
}

func nfcInnerLoop(
	ctx *scard.Context,
	stop <-chan struct{},
	cardPresent bool,
	lastReaderName string,
) (bool, string) {
	for {
		select {
		case <-stop:
			return cardPresent, lastReaderName
		default:
		}

		readers, err := ctx.ListReaders()
		if err != nil {
			// Context may have become invalid
			return cardPresent, lastReaderName
		}

		// ── Reader change detection ───────────────────────────────────────────
		var readerName string
		if len(readers) > 0 {
			readerName = readers[0]
		}
		if readerName != lastReaderName {
			lastReaderName = readerName
			nfcMu.Lock()
			nfcCurrentReader = readerName
			nfcMu.Unlock()

			cb := nfcGetCallbacks()
			if cb.OnReaderChange != nil {
				cb.OnReaderChange(readerName)
			}
			if readerName == "" && cardPresent {
				cardPresent = false
				nfcMu.Lock()
				nfcLastUID = ""
				nfcMu.Unlock()
				if cb.OnCardRemoved != nil {
					cb.OnCardRemoved()
				}
			}
		}

		if readerName == "" {
			time.Sleep(1 * time.Second)
			continue
		}

		// ── Try to connect and read UID ───────────────────────────────────────
		card, err := ctx.Connect(readerName, scard.ShareShared, scard.ProtocolAny)
		if err != nil {
			// No card in reader
			if cardPresent {
				cardPresent = false
				nfcMu.Lock()
				nfcLastUID = ""
				nfcMu.Unlock()
				cb := nfcGetCallbacks()
				if cb.OnCardRemoved != nil {
					cb.OnCardRemoved()
				}
			}
			time.Sleep(300 * time.Millisecond)
			continue
		}

		uid := readUID(card)
		card.Disconnect(scard.LeaveCard) //nolint:errcheck

		if uid != "" {
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
		} else if cardPresent {
			cardPresent = false
			nfcMu.Lock()
			nfcLastUID = ""
			nfcMu.Unlock()
			cb := nfcGetCallbacks()
			if cb.OnCardRemoved != nil {
				cb.OnCardRemoved()
			}
		}

		time.Sleep(300 * time.Millisecond)
	}
}

// readUID transmits the GET UID APDU and returns the UID as uppercase hex.
func readUID(card *scard.Card) string {
	resp, err := card.Transmit(getUIDAPDU)
	if err != nil || len(resp) < 3 {
		return ""
	}
	// Response: [UID bytes...] [SW1] [SW2]
	sw1 := resp[len(resp)-2]
	sw2 := resp[len(resp)-1]
	if sw1 != 0x90 || sw2 != 0x00 {
		return ""
	}
	uidBytes := resp[:len(resp)-2]
	return strings.ToUpper(hex.EncodeToString(uidBytes))
}
