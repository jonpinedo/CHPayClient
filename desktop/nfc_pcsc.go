// nfc_pcsc.go — PC/SC reader enumeration and UID read (winscard).
package main

import (
	"encoding/hex"
	"strings"

	"github.com/ebfe/scard"
)

// GET UID APDU (ISO 14443 / MIFARE)
var getUIDAPDU = []byte{0xFF, 0xCA, 0x00, 0x00, 0x00}

func nfcEnumeratePCSCReaders() []nfcReaderInfo {
	ctx, err := scard.EstablishContext()
	if err != nil {
		return nil
	}
	defer ctx.Release() //nolint:errcheck

	names, err := ctx.ListReaders()
	if err != nil {
		return nil
	}
	out := make([]nfcReaderInfo, 0, len(names))
	for _, name := range names {
		out = append(out, nfcReaderInfo{
			ID:       nfcReaderPCSCID(name),
			Label:    name,
			Kind:     nfcBackendPCSC,
			PCSCName: name,
		})
	}
	return out
}

// nfcPCSCReadUID connects to readerName, reads UID, disconnects. Empty string = no card.
func nfcPCSCReadUID(ctx *scard.Context, readerName string) string {
	card, err := ctx.Connect(readerName, scard.ShareShared, scard.ProtocolAny)
	if err != nil {
		return ""
	}
	defer card.Disconnect(scard.LeaveCard) //nolint:errcheck
	return nfcPCSCReadUIDFromCard(card)
}

func nfcPCSCReadUIDFromCard(card *scard.Card) string {
	resp, err := card.Transmit(getUIDAPDU)
	if err != nil || len(resp) < 3 {
		return ""
	}
	sw1 := resp[len(resp)-2]
	sw2 := resp[len(resp)-1]
	if sw1 != 0x90 || sw2 != 0x00 {
		return ""
	}
	uidBytes := resp[:len(resp)-2]
	return strings.ToUpper(hex.EncodeToString(uidBytes))
}
