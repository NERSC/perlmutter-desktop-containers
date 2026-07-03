package common

import (
	"fmt"
	"os"
	"path/filepath"
)

// DefaultSocketPath returns a user-scoped runtime socket path.
// Order: SCLI_SOCKET > XDG_RUNTIME_DIR > ~/.local/run
func DefaultSocketPath() (string, error) {
	if v := os.Getenv("SCLI_SOCKET"); v != "" {
		return v, nil
	}
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return filepath.Join(d, "scli.sock"), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", fmt.Errorf("resolve home: %w", err)
	}
	return filepath.Join(home, ".local", "run", "scli.sock"), nil
}

// EnsureSocketDir ensures the parent directory exists with safe permissions.
func EnsureSocketDir(sock string) error {
	dir := filepath.Dir(sock)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	return nil
}


