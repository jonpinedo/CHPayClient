// nfc_reader.go — reader registry: stable IDs, display labels, PC/SC + HID backends.
package main

import (
	"fmt"
	"strings"
)

type nfcBackendKind string

const (
	nfcBackendPCSC nfcBackendKind = "pcsc"
	nfcBackendHID  nfcBackendKind = "hid"
)

// nfcReaderInfo describes one selectable NFC reader.
type nfcReaderInfo struct {
	ID       string
	Label    string
	Kind     nfcBackendKind
	PCSCName string // Kind == pcsc
	HIDPath  string // Kind == hid — Windows device interface path
}

func nfcReaderPCSCID(name string) string {
	return "pcsc:" + name
}

func nfcReaderHIDID(vid, pid uint16, serial string) string {
	if serial == "" {
		serial = "unknown"
	}
	return fmt.Sprintf("hid:nfcx:%04x:%04x:%s", vid, pid, serial)
}

func (r nfcReaderInfo) equal(other nfcReaderInfo) bool {
	return r.ID == other.ID &&
		r.Label == other.Label &&
		r.Kind == other.Kind &&
		r.PCSCName == other.PCSCName &&
		r.HIDPath == other.HIDPath
}

func nfcReadersInfoEqual(a, b []nfcReaderInfo) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if !a[i].equal(b[i]) {
			return false
		}
	}
	return true
}

func nfcReaderLabels(readers []nfcReaderInfo) []string {
	out := make([]string, len(readers))
	for i, r := range readers {
		out[i] = r.Label
	}
	return out
}

func nfcFindReaderByID(readers []nfcReaderInfo, id string) (nfcReaderInfo, bool) {
	for _, r := range readers {
		if r.ID == id {
			return r, true
		}
	}
	return nfcReaderInfo{}, false
}

func nfcFindReaderByLabel(readers []nfcReaderInfo, label string) (nfcReaderInfo, bool) {
	for _, r := range readers {
		if r.Label == label {
			return r, true
		}
	}
	return nfcReaderInfo{}, false
}

// nfcResolveReaderID maps a persisted config value or UI label to a reader ID.
func nfcResolveReaderID(readers []nfcReaderInfo, stored string) string {
	if stored == "" {
		return ""
	}
	if strings.HasPrefix(stored, "pcsc:") || strings.HasPrefix(stored, "hid:") {
		if _, ok := nfcFindReaderByID(readers, stored); ok {
			return stored
		}
		// Stale ID — fall through to legacy matching.
	}
	// Legacy: plain PC/SC reader name stored before prefixed IDs.
	legacyID := nfcReaderPCSCID(stored)
	if _, ok := nfcFindReaderByID(readers, legacyID); ok {
		return legacyID
	}
	if r, ok := nfcFindReaderByLabel(readers, stored); ok {
		return r.ID
	}
	for _, r := range readers {
		if r.Kind == nfcBackendPCSC && r.PCSCName == stored {
			return r.ID
		}
	}
	return stored
}

func nfcPickReaderInfo(readers []nfcReaderInfo) nfcReaderInfo {
	if len(readers) == 0 {
		return nfcReaderInfo{}
	}
	selectedID := nfcResolveReaderID(readers, nfcGetSelectedReader())
	if selectedID != "" {
		if r, ok := nfcFindReaderByID(readers, selectedID); ok {
			return r
		}
	}
	return readers[0]
}

func nfcEnumerateAllReaders() []nfcReaderInfo {
	var out []nfcReaderInfo
	out = append(out, nfcEnumeratePCSCReaders()...)
	out = append(out, nfcEnumerateHIDReaders()...)
	return out
}

func nfcNotifyReadersListInfo(readers []nfcReaderInfo) {
	nfcNotifyReadersList(nfcReaderLabels(readers))
}
