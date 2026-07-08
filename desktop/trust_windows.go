//go:build windows

package main

import (
	"crypto/sha1"
	"crypto/x509"
	_ "embed"
	"encoding/hex"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"time"
	"unsafe"

	"fyne.io/fyne/v2"
	"golang.org/x/sys/windows"
)

//go:embed certs/chpay-signing.cer
var trustCertEmbedded []byte

var (
	modshell32        = windows.NewLazySystemDLL("shell32.dll")
	procShellExecuteW = modshell32.NewProc("ShellExecuteW")
	moduser32         = windows.NewLazySystemDLL("user32.dll")
	procMessageBoxW   = moduser32.NewProc("MessageBoxW")
)

const (
	shellExecuteError = 32
	mbYesNo           = 0x00000004
	mbIconInformation = 0x00000040
	mbIconError       = 0x00000010
	mbOk              = 0x00000000
	idYes             = 6
)

func trustCertThumbprint() (string, error) {
	if len(trustCertEmbedded) < 10 {
		return "", fmt.Errorf("certificado embebido no configurado (ejecuta create-signing-cert.ps1)")
	}
	cert, err := x509.ParseCertificate(trustCertEmbedded)
	if err != nil {
		return "", err
	}
	sum := sha1.Sum(cert.Raw)
	return strings.ToUpper(hex.EncodeToString(sum[:])), nil
}

func trustEnabled() bool {
	_, err := trustCertThumbprint()
	return err == nil
}

func trustCertInstalled() bool {
	thumb, err := trustCertThumbprint()
	if err != nil {
		return false
	}
	cmd := exec.Command("certutil", "-store", "Root", thumb)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}
	return strings.Contains(strings.ToUpper(string(out)), thumb)
}

func trustWriteTempCer() (string, error) {
	tmp, err := os.CreateTemp("", "chpay-signing-*.cer")
	if err != nil {
		return "", err
	}
	path := tmp.Name()
	if _, err := tmp.Write(trustCertEmbedded); err != nil {
		tmp.Close()
		os.Remove(path)
		return "", err
	}
	tmp.Close()
	return path, nil
}

func trustLog(msg string) {
	dir := cfgDir()
	_ = os.MkdirAll(dir, 0755)
	line := fmt.Sprintf("%s %s\n", time.Now().Format(time.RFC3339), msg)
	f, err := os.OpenFile(filepath.Join(dir, "trust.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(line)
}

func trustShowNativeError(err error) {
	msg, _ := windows.UTF16PtrFromString(err.Error())
	title, _ := windows.UTF16PtrFromString("CHPay Desktop")
	procMessageBoxW.Call(0, uintptr(unsafe.Pointer(msg)), uintptr(unsafe.Pointer(title)), mbIconError|mbOk)
}

func trustConfirmNative() (bool, error) {
	text, _ := windows.UTF16PtrFromString(
		"Para que Windows permita CHPay y sus actualizaciones, hay que instalar " +
			"un certificado de confianza.\n\nAparecerá el aviso de administrador (UAC).\n\n¿Continuar?",
	)
	title, _ := windows.UTF16PtrFromString("CHPay Desktop — Certificado de confianza")
	ret, _, _ := procMessageBoxW.Call(0, uintptr(unsafe.Pointer(text)), uintptr(unsafe.Pointer(title)), mbYesNo|mbIconInformation)
	return ret == idYes, nil
}

// trustLaunchElevatedInstall eleva certutil.exe para importar el .cer a LocalMachine\Root.
func trustLaunchElevatedInstall(cerPath string) error {
	certutil := filepath.Join(os.Getenv("SystemRoot"), "System32", "certutil.exe")
	params := fmt.Sprintf(`-addstore Root "%s"`, cerPath)

	verb, _ := syscall.UTF16PtrFromString("runas")
	file, _ := syscall.UTF16PtrFromString(certutil)
	args, _ := syscall.UTF16PtrFromString(params)
	dir, _ := syscall.UTF16PtrFromString(filepath.Dir(certutil))

	ret, _, _ := procShellExecuteW.Call(
		0,
		uintptr(unsafe.Pointer(verb)),
		uintptr(unsafe.Pointer(file)),
		uintptr(unsafe.Pointer(args)),
		uintptr(unsafe.Pointer(dir)),
		0, // SW_HIDE — certutil no necesita ventana
	)
	if ret <= shellExecuteError {
		if ret == 0 {
			return fmt.Errorf("elevación cancelada o denegada (UAC)")
		}
		return fmt.Errorf("ShellExecute falló (código %d)", ret)
	}
	return nil
}

func trustWaitForInstall(timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if trustCertInstalled() {
			return nil
		}
		time.Sleep(500 * time.Millisecond)
	}
	return fmt.Errorf("tiempo de espera agotado; comprueba trust.log en %APPDATA%\\CHPayDesktop")
}

func trustEnsureInstalledNative() error {
	if !trustEnabled() {
		return nil
	}
	if trustCertInstalled() {
		return nil
	}

	ok, err := trustConfirmNative()
	if err != nil {
		return err
	}
	if !ok {
		return fmt.Errorf("instalación del certificado cancelada")
	}

	cerPath, err := trustWriteTempCer()
	if err != nil {
		return err
	}
	defer os.Remove(cerPath)

	trustLog("solicitando UAC para certutil -addstore Root")
	if err := trustLaunchElevatedInstall(cerPath); err != nil {
		trustLog("error UAC: " + err.Error())
		return err
	}

	if err := trustWaitForInstall(90 * time.Second); err != nil {
		trustLog("error espera: " + err.Error())
		return err
	}
	trustLog("certificado instalado OK")
	return nil
}

// handleTrustCertInstallMode: modo legacy/debug (--install-trust-cert).
func handleTrustCertInstallMode() bool {
	if !hasCLIArg("--install-trust-cert") {
		return false
	}
	cerPath, err := trustWriteTempCer()
	if err != nil {
		trustLog("install-trust-cert: " + err.Error())
		os.Exit(1)
	}
	defer os.Remove(cerPath)

	cmd := exec.Command("certutil", "-addstore", "Root", cerPath)
	cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
	out, err := cmd.CombinedOutput()
	if err != nil {
		trustLog(fmt.Sprintf("certutil fallo: %v (%s)", err, strings.TrimSpace(string(out))))
		os.Exit(1)
	}
	if !trustCertInstalled() {
		trustLog("certificado no visible tras importar")
		os.Exit(1)
	}
	trustLog("install-trust-cert OK")
	os.Exit(0)
	return true
}

func trustEnsureInstalled(_ fyne.Window) error {
	return trustEnsureInstalledNative()
}

func hasCLIArg(flag string) bool {
	for _, arg := range os.Args[1:] {
		if arg == flag {
			return true
		}
	}
	return false
}
