package common

import (
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

// DefaultSocketPath returns a user-scoped runtime socket path.
// Order: SCLI_SOCKET > XDG_RUNTIME_DIR > node-local /tmp.
func DefaultSocketPath() (string, error) {
	if v := os.Getenv("SCLI_SOCKET"); v != "" {
		return v, nil
	}
	return defaultRuntimeSocketPath("scli"), nil
}

// DefaultSSHProxySocketPath returns a user-scoped SSH proxy socket path.
// Order: SSH_PROXY_SOCKET > XDG_RUNTIME_DIR > node-local /tmp.
func DefaultSSHProxySocketPath() (string, error) {
	if v := os.Getenv("SSH_PROXY_SOCKET"); v != "" {
		return v, nil
	}
	return defaultRuntimeSocketPath("ssh-proxy"), nil
}

// EnsureSocketDir ensures the parent directory exists with safe permissions.
func EnsureSocketDir(sock string) error {
	dir := filepath.Dir(sock)
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return err
	}
	return nil
}

// SocketAcceptsConnection reports whether a Unix socket exists and accepts a connection.
func SocketAcceptsConnection(sock string) bool {
	conn, err := net.DialTimeout("unix", sock, 500*time.Millisecond)
	if err != nil {
		return false
	}
	_ = conn.Close()
	return true
}

func defaultRuntimeSocketPath(name string) string {
	filename := name + "-" + safeHostname() + ".sock"
	if d := os.Getenv("XDG_RUNTIME_DIR"); d != "" {
		return filepath.Join(d, filename)
	}
	return filepath.Join(os.TempDir(), "vnc-novnc-"+osUid(), filename)
}

func safeHostname() string {
	host, err := os.Hostname()
	if err != nil || host == "" {
		host = "unknown"
	}
	var b strings.Builder
	for _, r := range host {
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '.' || r == '-' {
			b.WriteRune(r)
		} else {
			b.WriteByte('_')
		}
	}
	if b.Len() == 0 {
		return "unknown"
	}
	return b.String()
}

func osUid() string {
	return strconv.Itoa(os.Getuid())
}
