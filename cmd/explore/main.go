// Command explore is clmac's disk usage browser: a bar-chart drill-down
// UI in the style of tw93/mole's disk analyzer. View-only — it reveals
// files in Finder but never deletes; `clmac clean`/`clmac orphans` own
// deletion.
//
// lib/explore.sh execs this binary when present (falling back to its own
// bash implementation otherwise) and passes the root locations via
// --roots so they stay single-sourced in _explore_root_defs rather than
// duplicated here.
package main

import (
	"flag"
	"fmt"
	"os"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
)

func parseRoots(spec string) []rootDef {
	if spec == "" {
		return defaultRoots()
	}
	var roots []rootDef
	for _, part := range strings.Split(spec, "|") {
		if part == "" {
			continue
		}
		kv := strings.SplitN(part, ":", 2)
		if len(kv) != 2 || kv[1] == "" {
			continue
		}
		if _, err := os.Stat(kv[1]); err != nil {
			continue
		}
		roots = append(roots, rootDef{label: kv[0], path: kv[1]})
	}
	if len(roots) == 0 {
		return defaultRoots()
	}
	return roots
}

// defaultRoots mirrors lib/explore.sh's _explore_root_defs for standalone
// runs of this binary (e.g. manual testing without going through bash).
func defaultRoots() []rootDef {
	home, _ := os.UserHomeDir()
	candidates := []rootDef{
		{"Home", home},
		{"App Library", home + "/Library"},
		{"Applications", "/Applications"},
		{"System Library", "/Library"},
		{"Volumes", "/Volumes"},
	}
	var roots []rootDef
	for _, r := range candidates {
		if _, err := os.Stat(r.path); err == nil {
			roots = append(roots, r)
		}
	}
	return roots
}

func main() {
	rootsFlag := flag.String("roots", "", "pipe-separated Label:Path roots, e.g. Home:/Users/x|Applications:/Applications")
	flag.Parse()

	roots := parseRoots(*rootsFlag)
	if len(roots) == 0 {
		fmt.Fprintln(os.Stderr, "clmac explore: no accessible root locations found")
		os.Exit(1)
	}

	p := tea.NewProgram(initialModel(roots), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "clmac explore: %v\n", err)
		os.Exit(1)
	}
}
