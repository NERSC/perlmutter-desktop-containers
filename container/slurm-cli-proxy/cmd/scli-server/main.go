package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
	"sync"

	"github.com/creack/pty"

	"slurm-cli-proxy/internal/common"
	"slurm-cli-proxy/internal/protocol"
)

func main() {
	log.SetFlags(0)

	socket := flag.String("socket", "", "Unix socket path (default from env)")
	verbose := flag.Bool("verbose", false, "Print request and exit logs")
	allow := flag.String("allow", "srun,sbatch,salloc,squeue,scancel,scancel,scontrol,sacct,sinfo,sshare,sprio", "Comma-separated allowed command names")
	flag.Parse()

	sock, err := resolveSocket(*socket)
	if err != nil {
		log.Fatalf("socket path: %v", err)
	}
	if socketAlreadyExists(sock) {
		if *verbose {
			log.Printf("scli-server socket already exists, not starting: %s", sock)
		}
		return
	}
	if err := setupListenerPath(sock); err != nil {
		log.Fatalf("prepare socket: %v", err)
	}
	ln, err := net.Listen("unix", sock)
	if err != nil {
		log.Fatalf("listen: %v", err)
	}
	defer ln.Close()
	if *verbose {
		log.Printf("scli-server listening on %s", sock)
	}

	allowed := buildAllowed(*allow)

	for {
		conn, err := ln.Accept()
		if err != nil {
			if *verbose {
				log.Printf("accept: %v", err)
			}
			continue
		}
		go handleConn(conn, allowed, *verbose)
	}
}

func resolveSocket(cli string) (string, error) {
	if cli != "" {
		return cli, nil
	}
	return common.DefaultSocketPath()
}

func setupListenerPath(sock string) error {
	if err := common.EnsureSocketDir(sock); err != nil {
		return err
	}
	_ = os.Remove(sock)
	return nil
}

func socketAlreadyExists(sock string) bool {
	info, err := os.Stat(sock)
	if err != nil {
		return false
	}
	return info.Mode()&os.ModeSocket != 0
}

func buildAllowed(csv string) map[string]bool {
	m := make(map[string]bool)
	for _, p := range strings.Split(csv, ",") {
		p = strings.TrimSpace(p)
		if p != "" {
			m[p] = true
		}
	}
	return m
}

func handleConn(c net.Conn, allowed map[string]bool, verbose bool) {
	defer c.Close()
	r := bufio.NewReader(c)
	w := bufio.NewWriter(c)
	sw := &safeWriter{w: w}

	h, err := protocol.ReadHandshake(r)
	if err != nil {
		_ = sw.WriteFrame(protocol.FrameERROR, []byte(err.Error()))
		return
	}

	base := filepath.Base(h.Cmd)
	if !allowed[base] {
		_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("command not allowed: %s", base)))
		return
	}

	path, err := exec.LookPath(h.Cmd)
	if err != nil {
		_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("command not found: %s", h.Cmd)))
		return
	}

	// Build command
	var cmd *exec.Cmd
	usePTY := h.TTY
	if h.TTY && (base == "srun" || base == "salloc") {
		// Prefer running via user shell when TTY requested
		shell := os.Getenv("SHELL")
		if shell == "" {
			shell = "/bin/bash"
		}
		line := shellQuote(path, h.Args)
		// If we are in TTY mode for srun/salloc, use 'script' wrapper to allocate a PTY
		// without requiring this process to own a PTY. This avoids EPERM on setuid exec.
		cmd = exec.Command("script", "-qfec", line, "/dev/null")
		usePTY = false // script internally allocates a pty; we use pipes
		if verbose {
			log.Printf("exec via script: %s -qfec %q /dev/null (cwd=%s)", "script", line, h.Cwd)
		}
	} else if h.TTY {
		// TTY mode for non-slurm commands: run directly
		shell := os.Getenv("SHELL")
		if shell == "" {
			shell = "/bin/bash"
		}
		line := shellQuote(path, h.Args)
		cmd = exec.Command(shell, "-lc", line)
		if verbose {
			log.Printf("exec tty: %s -lc %q (cwd=%s)", shell, line, h.Cwd)
		}
	} else {
		cmd = exec.Command(path, h.Args...)
		if verbose {
			log.Printf("exec: %s %s (cwd=%s)", path, strings.Join(h.Args, " "), h.Cwd)
		}
	}

	cmd.Env = h.Env
	if h.Cwd != "" {
		cmd.Dir = h.Cwd
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	var (
		stdin io.WriteCloser
		stdout io.ReadCloser
		stderr io.ReadCloser
		ptyFile *os.File
	)

	if usePTY {
		if verbose {
			log.Printf("starting PTY child")
		}
		ptyFile, err = pty.Start(cmd)
		if err != nil {
			_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("start tty: %v", err)))
			return
		}
		defer ptyFile.Close()
		if h.Cols > 0 && h.Rows > 0 {
			_ = pty.Setsize(ptyFile, &pty.Winsize{Cols: uint16(h.Cols), Rows: uint16(h.Rows)})
		}
		stdin = ptyFile
		stdout = ptyFile
		stderr = nil // merged into pty
	} else {
		stdin, err = cmd.StdinPipe()
		if err != nil {
			_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("stdin pipe: %v", err)))
			return
		}
		stdout, err = cmd.StdoutPipe()
		if err != nil {
			_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("stdout pipe: %v", err)))
			return
		}
		stderr, err = cmd.StderrPipe()
		if err != nil {
			_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("stderr pipe: %v", err)))
			return
		}
		if verbose {
			log.Printf("starting child with pipes")
		}
		if err := cmd.Start(); err != nil {
			_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("start: %v", err)))
			return
		}
	}

	// Copy child stdout/stderr to frames
	doneCopy := make(chan struct{}, 2)
	if stdout != nil {
		go func() {
			buf := make([]byte, 32*1024)
			for {
				n, err := stdout.Read(buf)
				if n > 0 {
					_ = sw.WriteFrame(protocol.FrameSTDOUT, buf[:n])
				}
				if err != nil {
					break
				}
			}
			doneCopy <- struct{}{}
		}()
	}
	if stderr != nil {
		go func() {
			buf := make([]byte, 32*1024)
			for {
				n, err := stderr.Read(buf)
				if n > 0 {
					_ = sw.WriteFrame(protocol.FrameSTDERR, buf[:n])
				}
				if err != nil {
					break
				}
			}
			doneCopy <- struct{}{}
		}()
	}

	// Read frames from client and forward to child
	go func() {
		for {
			t, payload, err := protocol.ReadFrame(r)
			if err != nil {
				// client closed; close child stdin
				if stdin != nil {
					_ = stdin.Close()
				}
				return
			}
			switch t {
			case protocol.FrameSTDIN:
				if len(payload) > 0 && stdin != nil {
					_, _ = stdin.Write(payload)
				}
			case protocol.FrameSIGNAL:
				var sp protocol.SignalPayload
				_ = json.Unmarshal(payload, &sp)
				pgid, _ := syscall.Getpgid(cmd.Process.Pid)
				_ = syscall.Kill(-pgid, syscall.Signal(sp.Signal))
			case protocol.FrameRESIZE:
				if ptyFile != nil {
					var rp protocol.ResizePayload
					if err := json.Unmarshal(payload, &rp); err == nil {
						_ = pty.Setsize(ptyFile, &pty.Winsize{Cols: uint16(rp.Cols), Rows: uint16(rp.Rows)})
					}
				}
			}
		}
	}()

	// Wait for command to exit
	err = cmd.Wait()
	code, signaled := extractExit(err)
	_ = sw.WriteFrame(protocol.FrameEXIT, mustJSON(protocol.ExitPayload{Code: code, Signaled: signaled}))
	if verbose {
		log.Printf("exit: code=%d signaled=%v for %s %s", code, signaled, path, strings.Join(h.Args, " "))
	}
	// ensure copy goroutines can exit
	if stdin != nil {
		_ = stdin.Close()
	}
	<-doneCopy
}

type safeWriter struct {
	mu sync.Mutex
	w  *bufio.Writer
}

func (sw *safeWriter) WriteFrame(t protocol.FrameType, payload []byte) error {
	sw.mu.Lock()
	defer sw.mu.Unlock()
	if err := protocol.WriteFrame(sw.w, t, payload); err != nil {
		return err
	}
	return sw.w.Flush()
}

func extractExit(err error) (int, bool) {
	if err == nil {
		return 0, false
	}
	if ee, ok := err.(*exec.ExitError); ok {
		if ws, ok := ee.Sys().(syscall.WaitStatus); ok {
			if ws.Signaled() {
				return 128 + int(ws.Signal()), true
			}
			return ws.ExitStatus(), false
		}
	}
	return 1, false
}

func mustJSON(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

// shellQuote returns a single command line string with safe POSIX single-quote escaping.
func shellQuote(cmdPath string, args []string) string {
	var b strings.Builder
	b.WriteString(posixQuote(cmdPath))
	for _, a := range args {
		b.WriteByte(' ')
		b.WriteString(posixQuote(a))
	}
	return b.String()
}

func posixQuote(s string) string {
	if s == "" {
		return "''"
	}
	// Replace ' with '\'' sequence
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

