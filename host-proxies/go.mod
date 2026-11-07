module github.com/nersc/perlmutter-desktop-containers/host-proxies

go 1.19

require (
	github.com/creack/pty v1.1.18
	golang.org/x/term v0.5.0
)

require golang.org/x/sys v0.5.0 // indirect

replace golang.org/x/sys => golang.org/x/sys v0.5.0
