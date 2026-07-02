//go:build windows

// nfc_hid_windows.go — NFC-X reader (VID 0483 / PID 4343) over Windows HID reports.
package main

import (
	"encoding/binary"
	"fmt"
	"strings"
	"sync"
	"unsafe"

	"golang.org/x/sys/windows"
)

const (
	nfcxVendorID  = 0x0483
	nfcxProductID = 0x4343

	nfcHIDMissingThreshold = 3
)

// Captured from Cyb_Nfctool via USBPcap (host → device).
var (
	nfcHIDCmdStatus = []byte{0x55, 0x00, 0x51, 0x00, 0x01, 0x01, 0xFE, 0x01}
	nfcHIDCmdRead   = []byte{0x55, 0x00, 0x69, 0x00, 0x00, 0xFF, 0x00}
)

var (
	modhid      = windows.NewLazySystemDLL("hid.dll")
	modsetupapi = windows.NewLazySystemDLL("setupapi.dll")

	procHidD_GetHidGuid           = modhid.NewProc("HidD_GetHidGuid")
	procHidD_GetAttributes        = modhid.NewProc("HidD_GetAttributes")
	procHidD_GetPreparsedData     = modhid.NewProc("HidD_GetPreparsedData")
	procHidD_FreePreparsedData    = modhid.NewProc("HidD_FreePreparsedData")
	procHidP_GetCaps              = modhid.NewProc("HidP_GetCaps")
	procHidD_GetProductString     = modhid.NewProc("HidD_GetProductString")
	procHidD_GetManufacturerStr   = modhid.NewProc("HidD_GetManufacturerString")
	procHidD_GetSerialNumberStr   = modhid.NewProc("HidD_GetSerialNumberString")

	procSetupDiGetClassDevsW             = modsetupapi.NewProc("SetupDiGetClassDevsW")
	procSetupDiEnumDeviceInterfaces       = modsetupapi.NewProc("SetupDiEnumDeviceInterfaces")
	procSetupDiGetDeviceInterfaceDetailW  = modsetupapi.NewProc("SetupDiGetDeviceInterfaceDetailW")
	procSetupDiDestroyDeviceInfoList     = modsetupapi.NewProc("SetupDiDestroyDeviceInfoList")
)

const (
	digcfPresent         = 0x00000002
	digcfDeviceInterface = 0x00000010
)

type hiddAttributes struct {
	Size          uint32
	VendorID      uint16
	ProductID     uint16
	VersionNumber uint16
}

type spDeviceInterfaceData struct {
	cbSize             uint32
	InterfaceClassGuid windows.GUID
	Flags              uint32
	Reserved           uintptr
}

type nfcHIDSession struct {
	path      string
	h         windows.Handle
	evt       windows.Handle
	reportLen int
	mu        sync.Mutex
}

func nfcEnumerateHIDReaders() []nfcReaderInfo {
	paths, err := nfcHIDFindPaths(nfcxVendorID, nfcxProductID)
	if err != nil || len(paths) == 0 {
		return nil
	}

	seen := make(map[string]struct{})
	var out []nfcReaderInfo
	for _, path := range paths {
		meta := nfcHIDProbeMeta(path)
		id := nfcReaderHIDID(nfcxVendorID, nfcxProductID, meta.serial)
		if _, dup := seen[id]; dup {
			continue
		}
		seen[id] = struct{}{}

		label := "NFC-X HID"
		if meta.product != "" {
			label += " (" + meta.product
			if meta.serial != "" {
				label += " / " + meta.serial
			}
			label += ")"
		}

		out = append(out, nfcReaderInfo{
			ID:      id,
			Label:   label,
			Kind:    nfcBackendHID,
			HIDPath: path,
		})
	}
	return out
}

type nfcHIDMeta struct {
	manufacturer string
	product      string
	serial       string
}

func nfcHIDProbeMeta(path string) nfcHIDMeta {
	h, reportLen := nfcHIDOpenHandle(path)
	if h == windows.InvalidHandle {
		return nfcHIDMeta{}
	}
	_ = reportLen
	defer windows.CloseHandle(h)
	return nfcHIDMeta{
		manufacturer: nfcHIDGetString(h, procHidD_GetManufacturerStr),
		product:      nfcHIDGetString(h, procHidD_GetProductString),
		serial:       nfcHIDGetString(h, procHidD_GetSerialNumberStr),
	}
}

func nfcHIDOpen(path string) (*nfcHIDSession, error) {
	h, reportLen := nfcHIDOpenHandle(path)
	if h == windows.InvalidHandle {
		return nil, fmt.Errorf("cannot open HID device")
	}
	evt, err := windows.CreateEvent(nil, 1, 0, nil)
	if err != nil {
		windows.CloseHandle(h)
		return nil, err
	}
	if reportLen <= 0 {
		reportLen = 65
	}
	return &nfcHIDSession{
		path:      path,
		h:         h,
		evt:       evt,
		reportLen: reportLen,
	}, nil
}

func (s *nfcHIDSession) Close() {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.evt != 0 {
		windows.CloseHandle(s.evt)
		s.evt = 0
	}
	if s.h != windows.InvalidHandle {
		windows.CloseHandle(s.h)
		s.h = windows.InvalidHandle
	}
}

// ReadUID polls the NFC-X with status + read commands. Empty string = no card.
func (s *nfcHIDSession) ReadUID() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.h == windows.InvalidHandle {
		return ""
	}

	report := make([]byte, s.reportLen)
	report[0] = 0x00

	// Status ping (observed before card read in vendor tool).
	copy(report[1:], nfcHIDCmdStatus)
	if err := nfcHIDWriteReport(s.h, s.evt, report); err != nil {
		return ""
	}
	_, _, _ = nfcHIDReadReport(s.h, s.evt, s.reportLen, 200)

	copy(report[1:], nfcHIDCmdRead)
	if err := nfcHIDWriteReport(s.h, s.evt, report); err != nil {
		return ""
	}

	for i := 0; i < 4; i++ {
		resp, n, err := nfcHIDReadReport(s.h, s.evt, s.reportLen, 400)
		if err != nil || n == 0 {
			continue
		}
		if uid := nfcHIDParseUID(resp[:n]); uid != "" {
			return uid
		}
	}
	return ""
}

func nfcHIDOpenHandle(path string) (windows.Handle, int) {
	p16, _ := windows.UTF16PtrFromString(path)
	h, err := windows.CreateFile(
		p16,
		windows.GENERIC_READ|windows.GENERIC_WRITE,
		windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE,
		nil,
		windows.OPEN_EXISTING,
		windows.FILE_FLAG_OVERLAPPED,
		0,
	)
	if err != nil {
		h, err = windows.CreateFile(
			p16,
			windows.GENERIC_READ,
			windows.FILE_SHARE_READ|windows.FILE_SHARE_WRITE,
			nil,
			windows.OPEN_EXISTING,
			windows.FILE_FLAG_OVERLAPPED,
			0,
		)
		if err != nil {
			return windows.InvalidHandle, 0
		}
	}

	reportLen := 65
	var preparsed uintptr
	r, _, _ := procHidD_GetPreparsedData.Call(uintptr(h), uintptr(unsafe.Pointer(&preparsed)))
	if r != 0 && preparsed != 0 {
		var caps [256]byte
		rc, _, _ := procHidP_GetCaps.Call(preparsed, uintptr(unsafe.Pointer(&caps[0])))
		if rc == 0x00110000 {
			reportLen = int(binary.LittleEndian.Uint16(caps[4:]))
			if reportLen <= 0 {
				reportLen = 65
			}
		}
		procHidD_FreePreparsedData.Call(preparsed)
	}
	return h, reportLen
}

func nfcHIDGetString(h windows.Handle, proc *windows.LazyProc) string {
	buf := make([]uint16, 128)
	r, _, _ := proc.Call(uintptr(h), uintptr(unsafe.Pointer(&buf[0])), uintptr(len(buf)*2))
	if r == 0 {
		return ""
	}
	return windows.UTF16ToString(buf)
}

func nfcHIDWriteReport(h windows.Handle, evt windows.Handle, report []byte) error {
	var written uint32
	ov := &windows.Overlapped{HEvent: evt}
	windows.ResetEvent(evt)

	err := windows.WriteFile(h, report, &written, ov)
	if err != nil && err != windows.ERROR_IO_PENDING {
		return err
	}
	w, _ := windows.WaitForSingleObject(evt, 2000)
	if w != windows.WAIT_OBJECT_0 {
		windows.CancelIoEx(h, ov)
		return fmt.Errorf("hid write timeout")
	}
	return windows.GetOverlappedResult(h, ov, &written, false)
}

func nfcHIDReadReport(h windows.Handle, evt windows.Handle, reportLen int, timeoutMs uint32) ([]byte, uint32, error) {
	buf := make([]byte, reportLen)
	var read uint32
	ov := &windows.Overlapped{HEvent: evt}
	windows.ResetEvent(evt)

	err := windows.ReadFile(h, buf, &read, ov)
	if err != nil && err != windows.ERROR_IO_PENDING {
		return buf, 0, err
	}
	w, _ := windows.WaitForSingleObject(evt, timeoutMs)
	if w != windows.WAIT_OBJECT_0 {
		windows.CancelIoEx(h, ov)
		windows.GetOverlappedResult(h, ov, &read, true) //nolint:errcheck
		return buf, 0, nil
	}
	if err := windows.GetOverlappedResult(h, ov, &read, false); err != nil {
		return buf, 0, err
	}
	return buf, read, nil
}

func nfcHIDParseUID(report []byte) string {
	if len(report) < 8 {
		return ""
	}
	data := report[1:]
	if len(data) < 7 || data[0] != 0x55 || data[2] != 0x69 {
		return ""
	}
	payloadLen := int(data[4])
	payloadEnd := 5 + payloadLen
	if payloadEnd > len(data) || payloadLen < 14 {
		return ""
	}
	payload := data[5:payloadEnd]
	uidLenOffset := len(payload) - 7
	if uidLenOffset < 2 {
		return ""
	}
	uidLen := int(payload[uidLenOffset])
	uidStart := 2
	uidEnd := uidStart + uidLen
	if uidLen <= 0 || uidEnd > uidLenOffset {
		return ""
	}
	var sb strings.Builder
	for _, x := range payload[uidStart:uidEnd] {
		fmt.Fprintf(&sb, "%02X", x)
	}
	return sb.String()
}

func nfcHIDFindPaths(vid, pid uint16) ([]string, error) {
	var hidGuid windows.GUID
	procHidD_GetHidGuid.Call(uintptr(unsafe.Pointer(&hidGuid)))

	devInfo, _, _ := procSetupDiGetClassDevsW.Call(
		uintptr(unsafe.Pointer(&hidGuid)),
		0,
		0,
		uintptr(digcfPresent|digcfDeviceInterface),
	)
	if devInfo == 0 || devInfo == ^uintptr(0) {
		return nil, fmt.Errorf("SetupDiGetClassDevs failed")
	}
	defer procSetupDiDestroyDeviceInfoList.Call(devInfo)

	want := fmt.Sprintf("vid_%04x&pid_%04x", vid, pid)
	var paths []string
	var index uint32
	for {
		var ifData spDeviceInterfaceData
		ifData.cbSize = uint32(unsafe.Sizeof(ifData))
		r, _, _ := procSetupDiEnumDeviceInterfaces.Call(
			devInfo,
			0,
			uintptr(unsafe.Pointer(&hidGuid)),
			uintptr(index),
			uintptr(unsafe.Pointer(&ifData)),
		)
		if r == 0 {
			break
		}
		index++

		var reqSize uint32
		procSetupDiGetDeviceInterfaceDetailW.Call(
			devInfo,
			uintptr(unsafe.Pointer(&ifData)),
			0,
			0,
			uintptr(unsafe.Pointer(&reqSize)),
			0,
		)
		if reqSize == 0 {
			continue
		}

		buf := make([]byte, reqSize)
		binary.LittleEndian.PutUint32(buf[0:], 8)
		r, _, _ = procSetupDiGetDeviceInterfaceDetailW.Call(
			devInfo,
			uintptr(unsafe.Pointer(&ifData)),
			uintptr(unsafe.Pointer(&buf[0])),
			uintptr(reqSize),
			0,
			0,
		)
		if r == 0 {
			continue
		}
		pathPtr := (*uint16)(unsafe.Pointer(&buf[4]))
		path := windows.UTF16PtrToString(pathPtr)
		if strings.Contains(strings.ToLower(path), want) {
			paths = append(paths, path)
		}
	}
	return paths, nil
}
