// update.go — Sistema de actualizaciones OTA.
// Consulta el servidor, descarga el nuevo EXE y lo aplica mediante auto-reemplazo.
//
// Flujo de actualización:
//  1. checkForUpdate()    → consulta /api/update/version?platform=desktop
//  2. downloadUpdate()    → descarga a %TEMP%\chpay-update.exe
//  3. applyUpdate()       → lanza el nuevo exe con flags --upgrade --target=<ruta> --oldpid=<PID>
//                           y cierra la app actual
//  4. handleUpgradeMode() → el nuevo exe (desde temp) detecta los flags al arrancar,
//                           espera que el proceso antiguo termine, se copia sobre el target,
//                           relanza desde la ruta final y se elimina del temp
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// UpdateInfo representa la respuesta del servidor de versiones.
type UpdateInfo struct {
	VersionCode int    `json:"versionCode"`
	VersionName string `json:"versionName"`
	Mandatory   bool   `json:"mandatory"`
	Changelog   string `json:"changelog"`
	Available   bool   `json:"available"`
}

// checkForUpdate consulta el servidor para ver si hay una versión más nueva.
// No requiere autenticación. Devuelve nil si no hay update o si falla (no bloqueante).
func checkForUpdate() *UpdateInfo {
	url := apiURL("/api/update/version?platform=desktop")

	client := &http.Client{Timeout: 10 * time.Second}
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil
	}

	resp, err := client.Do(req)
	if err != nil {
		return nil
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return nil
	}

	raw, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil
	}

	var info UpdateInfo
	if err := json.Unmarshal(raw, &info); err != nil {
		return nil
	}

	if !info.Available {
		return nil
	}

	// Comparar con versión local
	localCode, _ := strconv.Atoi(AppVersionCode)
	if info.VersionCode <= localCode {
		return nil // ya estamos al día
	}

	return &info
}

// downloadUpdate descarga el EXE desde el servidor a un fichero temporal.
// Requiere bearer token. Llama a onProgress con el porcentaje (0-100) durante la descarga.
// Devuelve la ruta del fichero descargado.
func downloadUpdate(bearer string, onProgress func(percent int, downloaded, total int64)) (string, error) {
	url := apiURL("/api/update/exe")

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return "", fmt.Errorf("error creando request: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+bearer)

	// Cliente sin timeout para descargas grandes
	client := &http.Client{Timeout: 0}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("error de conexión: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != 200 {
		return "", fmt.Errorf("servidor devolvió HTTP %d", resp.StatusCode)
	}

	totalBytes := resp.ContentLength

	// Crear fichero temporal
	tempDir := os.TempDir()
	destPath := filepath.Join(tempDir, "chpay-update.exe")

	// Eliminar si ya existe
	_ = os.Remove(destPath)

	outFile, err := os.Create(destPath)
	if err != nil {
		return "", fmt.Errorf("no se pudo crear fichero temporal: %w", err)
	}
	defer outFile.Close()

	// Descargar con progreso
	var downloaded int64
	buf := make([]byte, 32*1024) // 32KB buffer

	for {
		n, readErr := resp.Body.Read(buf)
		if n > 0 {
			_, writeErr := outFile.Write(buf[:n])
			if writeErr != nil {
				return "", fmt.Errorf("error escribiendo fichero: %w", writeErr)
			}
			downloaded += int64(n)

			if onProgress != nil && totalBytes > 0 {
				percent := int(downloaded * 100 / totalBytes)
				onProgress(percent, downloaded, totalBytes)
			}
		}
		if readErr != nil {
			if readErr == io.EOF {
				break
			}
			return "", fmt.Errorf("error leyendo respuesta: %w", readErr)
		}
	}

	// Verificar que se descargó completo
	if totalBytes > 0 && downloaded != totalBytes {
		return "", fmt.Errorf("descarga incompleta: %d/%d bytes", downloaded, totalBytes)
	}

	return destPath, nil
}

// applyUpdate lanza el exe descargado pasándole la ruta del exe actual para que lo reemplace,
// y cierra la aplicación actual.
func applyUpdate(downloadedExe string) error {
	// Verificar que el fichero existe
	if _, err := os.Stat(downloadedExe); err != nil {
		return fmt.Errorf("fichero no encontrado: %w", err)
	}

	// Ruta del exe actual (este proceso)
	selfPath, err := os.Executable()
	if err != nil {
		return fmt.Errorf("no se pudo obtener la ruta del exe actual: %w", err)
	}
	// Resolver symlinks/junctions
	selfPath, _ = filepath.EvalSymlinks(selfPath)

	selfPID := os.Getpid()

	// Lanzar el nuevo exe con instrucciones de reemplazo
	cmd := exec.Command(downloadedExe,
		"--upgrade",
		"--target="+selfPath,
		fmt.Sprintf("--oldpid=%d", selfPID),
	)
	if err := cmd.Start(); err != nil {
		return fmt.Errorf("no se pudo lanzar el nuevo exe: %w", err)
	}

	// Dar tiempo al proceso hijo para arrancar
	time.Sleep(500 * time.Millisecond)

	// Cerrar la aplicación actual
	os.Exit(0)
	return nil // nunca se ejecuta
}

// handleUpgradeMode detecta si el exe fue lanzado con --upgrade y realiza el reemplazo.
// Devuelve true si estamos en modo upgrade (el caller debe salir sin arrancar la UI).
func handleUpgradeMode() bool {
	args := os.Args[1:]

	// Buscar el flag --upgrade
	isUpgrade := false
	var targetPath string
	var oldPID int

	for _, arg := range args {
		switch {
		case arg == "--upgrade":
			isUpgrade = true
		case strings.HasPrefix(arg, "--target="):
			targetPath = strings.TrimPrefix(arg, "--target=")
		case strings.HasPrefix(arg, "--oldpid="):
			oldPID, _ = strconv.Atoi(strings.TrimPrefix(arg, "--oldpid="))
		}
	}

	if !isUpgrade || targetPath == "" {
		return false
	}

	// Esperar a que el proceso antiguo termine (máx 10s)
	if oldPID > 0 {
		waitForProcessExit(oldPID, 10*time.Second)
	} else {
		time.Sleep(1 * time.Second)
	}

	// Ruta de este exe (el descargado, en temp)
	selfPath, err := os.Executable()
	if err != nil {
		os.Exit(2)
	}

	// Copiar este exe sobre el target (el exe original)
	if err := copyFile(selfPath, targetPath); err != nil {
		// Si falla la copia, igualmente lanzamos la app desde temp
		exec.Command(targetPath).Start() //nolint:errcheck
		os.Exit(3)
	}

	// Lanzar el exe actualizado desde su ubicación final
	cmd := exec.Command(targetPath)
	if err := cmd.Start(); err != nil {
		os.Exit(4)
	}

	// Borrar este exe temporal (lanzamos cmd /c del para evitar locked file)
	// Usamos un pequeño delay para que el proceso hijo arranque primero
	time.Sleep(500 * time.Millisecond)
	selfDir := filepath.Dir(selfPath)
	selfName := filepath.Base(selfPath)
	exec.Command("cmd", "/c",
		fmt.Sprintf("ping 127.0.0.1 -n 2 > nul && del /f /q %s",
			filepath.Join(selfDir, selfName)),
	).Start() //nolint:errcheck

	os.Exit(0)
	return true // nunca se ejecuta, pero satisface el compilador
}

// waitForProcessExit espera a que el proceso con el PID dado termine, hasta timeout.
// En Windows usamos polling ya que os.FindProcess no distingue entre activo y zombi.
func waitForProcessExit(pid int, timeout time.Duration) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		// Intentar abrir el proceso — si falla, ya terminó
		proc, err := os.FindProcess(pid)
		if err != nil {
			return
		}
		// Enviar signal 0 no funciona en Windows, pero podemos intentar Wait()
		// en un proceso que no es hijo nuestro → siempre fallará con error.
		// La solución más robusta es simplemente esperar un tiempo razonable.
		_ = proc
		time.Sleep(300 * time.Millisecond)
	}
}

// copyFile copia src sobre dst, sobreescribiendo si existe.
func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	// Crear/truncar el destino
	out, err := os.Create(dst)
	if err != nil {
		return fmt.Errorf("no se pudo abrir el exe destino: %w", err)
	}
	defer out.Close()

	_, err = io.Copy(out, in)
	return err
}

// getLocalVersionCode devuelve el versionCode local como entero.
func getLocalVersionCode() int {
	code, _ := strconv.Atoi(AppVersionCode)
	return code
}

// formatBytes formatea bytes a una cadena legible (KB, MB).
func formatBytes(bytes int64) string {
	if bytes < 1024 {
		return fmt.Sprintf("%d B", bytes)
	}
	if bytes < 1024*1024 {
		return fmt.Sprintf("%.1f KB", float64(bytes)/1024)
	}
	return fmt.Sprintf("%.1f MB", float64(bytes)/(1024*1024))
}
