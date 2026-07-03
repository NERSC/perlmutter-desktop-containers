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
	"sync"
	"syscall"

	"github.com/creack/pty"

	"slurm-cli-proxy/internal/common"
	"slurm-cli-proxy/internal/protocol"
)

func main() {
	log.SetFlags(0)

	socket := flag.String("socket", "", "Unix socket path (default from env)")
	sshPath := flag.String("ssh-path", "ssh", "Host ssh executable")
	verbose := flag.Bool("verbose", false, "Print request and exit logs")
	flag.Parse()

	sock, err := resolveSocket(*socket)
	if err != nil {
		log.Fatalf("socket path: %v", err)
	}
	if socketAlreadyExists(sock) {
		if *verbose {
			log.Printf("ssh-proxy-server socket already exists, not starting: %s", sock)
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
		log.Printf("ssh-proxy-server listening on %s", sock)
	}

	for {
		conn, err := ln.Accept()
		if err != nil {
			if *verbose {
				log.Printf("accept: %v", err)
			}
			continue
		}
		go handleConn(conn, *sshPath, *verbose)
	}
}

func resolveSocket(cli string) (string, error) {
	if cli != "" {
		return cli, nil
	}
	return common.DefaultSSHProxySocketPath()
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

func handleConn(c net.Conn, sshPath string, verbose bool) {
	defer c.Close()
	r := bufio.NewReader(c)
	w := bufio.NewWriter(c)
	sw := &safeWriter{w: w}

	h, err := protocol.ReadHandshake(r)
	if err != nil {
		_ = sw.WriteFrame(protocol.FrameERROR, []byte(err.Error()))
		return
	}
	if filepath.Base(h.Cmd) != "ssh" {
		_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("command not allowed: %s", h.Cmd)))
		return
	}

	path, err := exec.LookPath(sshPath)
	if err != nil {
		_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("ssh not found: %s", sshPath)))
		return
	}

	var cmd *exec.Cmd
	usePTY := h.TTY
	if h.TTY {
		line := shellQuote(path, h.Args)
		cmd = exec.Command("script", "-qfec", line, "/dev/null")
		usePTY = false
		if verbose {
			log.Printf("exec via script: %s -qfec %q /dev/null (cwd=%s)", "script", line, h.Cwd)
		}
	} else {
		cmd = exec.Command(path, h.Args...)
	}
	cmd.Env = sshEnv(os.Environ(), h.Env)
	if h.Cwd != "" && pathExists(h.Cwd) {
		cmd.Dir = h.Cwd
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	if verbose {
		mode := "pipes"
		if usePTY {
			mode = "pty"
		}
		log.Printf("exec %s: %s %s (cwd=%s)", mode, path, strings.Join(h.Args, " "), cmd.Dir)
	}

	var (
		stdin  io.WriteCloser
		stdout io.ReadCloser
		stderr io.ReadCloser
		ptmx   *os.File
	)

	if usePTY {
		ptmx, err = pty.Start(cmd)
		if err != nil {
			_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("start tty: %v", err)))
			return
		}
		defer ptmx.Close()
		if h.Cols > 0 && h.Rows > 0 {
			_ = pty.Setsize(ptmx, &pty.Winsize{Cols: uint16(h.Cols), Rows: uint16(h.Rows)})
		}
		stdin = ptmx
		stdout = ptmx
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
		if err := cmd.Start(); err != nil {
			_ = sw.WriteFrame(protocol.FrameERROR, []byte(fmt.Sprintf("start: %v", err)))
			return
		}
	}

	var copyWG sync.WaitGroup
	copyOutput := func(t protocol.FrameType, reader io.Reader) {
		defer copyWG.Done()
		buf := make([]byte, 32*1024)
		for {
			n, err := reader.Read(buf)
			if n > 0 {
				_ = sw.WriteFrame(t, buf[:n])
			}
			if err != nil {
				return
			}
		}
	}
	if stdout != nil {
		copyWG.Add(1)
		go copyOutput(protocol.FrameSTDOUT, stdout)
	}
	if stderr != nil {
		copyWG.Add(1)
		go copyOutput(protocol.FrameSTDERR, stderr)
	}

	go func() {
		for {
			t, payload, err := protocol.ReadFrame(r)
			if err != nil {
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
				if cmd.Process != nil {
					pgid, _ := syscall.Getpgid(cmd.Process.Pid)
					_ = syscall.Kill(-pgid, syscall.Signal(sp.Signal))
				}
			case protocol.FrameRESIZE:
				if ptmx != nil {
					var rp protocol.ResizePayload
					if err := json.Unmarshal(payload, &rp); err == nil {
						_ = pty.Setsize(ptmx, &pty.Winsize{Cols: uint16(rp.Cols), Rows: uint16(rp.Rows)})
					}
				}
			}
		}
	}()

	err = cmd.Wait()
	code, signaled := extractExit(err)
	if stdin != nil {
		_ = stdin.Close()
	}
	if ptmx != nil {
		_ = ptmx.Close()
	}
	copyWG.Wait()
	_ = sw.WriteFrame(protocol.FrameEXIT, mustJSON(protocol.ExitPayload{Code: code, Signaled: signaled}))
	if verbose {
		log.Printf("exit: code=%d signaled=%v for %s %s", code, signaled, path, strings.Join(h.Args, " "))
	}
}

func sshEnv(hostEnv, clientEnv []string) []string {
	merged := append([]string{}, hostEnv...)
	hostIndex := make(map[string]int)
	for index, item := range merged {
		name := strings.SplitN(item, "=", 2)[0]
		hostIndex[name] = index
	}
	for _, item := range clientEnv {
		name, _, _ := strings.Cut(item, "=")
		if !clientSSHEnvAllowed(name) {
			continue
		}
		if index, ok := hostIndex[name]; ok {
			merged[index] = item
		} else {
			hostIndex[name] = len(merged)
			merged = append(merged, item)
		}
	}
	return merged
}

func clientSSHEnvAllowed(name string) bool {
	return name == "TERM" || name == "COLORTERM" || name == "LANG" || strings.HasPrefix(name, "LC_")
}

func pathExists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// shellQuote returns a single command line string with safe POSIX single-quote escaping.
func shellQuote(cmdPath string, args []string) string {
	var b strings.Builder
	b.WriteString(posixQuote(cmdPath))
	for _, arg := range args {
		b.WriteByte(' ')
		b.WriteString(posixQuote(arg))
	}
	return b.String()
}

func posixQuote(s string) string {
	if s == "" {
		return "''"
	}
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
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
