//go:build !windows

package main

func nfcEnumerateHIDReaders() []nfcReaderInfo { return nil }

type nfcHIDSession struct{}

func nfcHIDOpen(path string) (*nfcHIDSession, error) { return nil, nil }

func (*nfcHIDSession) Close() {}

func (*nfcHIDSession) ReadUID() string { return "" }
