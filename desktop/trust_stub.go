//go:build !windows

package main

import "fyne.io/fyne/v2"

func handleTrustCertInstallMode() bool { return false }

func trustEnsureInstalled(_ fyne.Window) error { return nil }

func trustEnsureInstalledNative() error { return nil }

func trustShowNativeError(_ error) {}
