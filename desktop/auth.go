// auth.go — Flujo de autenticación de 3 pasos.
//  1. register-request → solicitar registro (requiere aprobación admin)
//  2. authorize        → obtener token permanente
//  3. session          → obtener bearer de sesión (en memoria)
package main

import "fmt"

// AuthError carries an HTTP status code so the caller can decide if it's
// a permanent auth failure (401/403) or a transient connectivity issue.
type AuthError struct {
	Msg        string
	StatusCode int
}

func (e *AuthError) Error() string { return e.Msg }
func (e *AuthError) IsAuthError() bool {
	return e.StatusCode == 401 || e.StatusCode == 403
}

// authRequestRegistration is Step 1: request device registration.
func authRequestRegistration(deviceName string, capituloID int) error {
	deviceID := configGetDeviceID()
	err := apiRegisterRequest(deviceID, deviceName, capituloID)
	if err != nil {
		return err
	}
	configSetDeviceName(deviceName)
	configSetStatus("pending")
	return nil
}

// authAuthorize is Step 2: obtain permanent token after admin approval.
func authAuthorize(deviceName string) error {
	deviceID := configGetDeviceID()
	name := deviceName
	if name == "" {
		name = configGetDeviceName()
		if name == "" {
			name = "CHPayDesktop"
		}
	}
	token, err := apiAuthorizeDevice(deviceID, name)
	if err != nil {
		return err
	}
	if token == "" {
		return fmt.Errorf("el servidor no devolvió un token")
	}
	configSetToken(token)
	configSetStatus("authorized")
	return nil
}

// authCreateSession is Step 3: create an in-memory bearer session.
// Returns an *AuthError if credentials are invalid (401/403).
func authCreateSession() (string, error) {
	permanentToken := configGetToken()
	if permanentToken == "" {
		return "", &AuthError{
			Msg:        "Token permanente no disponible. Registra el dispositivo primero.",
			StatusCode: 0,
		}
	}
	bearer, code, err := apiCreateSession(configGetDeviceID(), permanentToken)
	if err != nil {
		return "", &AuthError{Msg: err.Error(), StatusCode: code}
	}
	if bearer == "" {
		return "", &AuthError{Msg: "la sesión no devolvió bearer token", StatusCode: 0}
	}
	apiSetBearer(bearer)
	configSetStatus("authorized")
	return bearer, nil
}

// authTryRecover tries to silently re-authorize (step 2) and start a session.
func authTryRecover() bool {
	if authAuthorize("") == nil {
		_, err := authCreateSession()
		return err == nil
	}
	return false
}

// authLogout clears in-memory bearer and persisted credentials.
func authLogout() {
	apiClearBearer()
	configClearCredentials()
}
